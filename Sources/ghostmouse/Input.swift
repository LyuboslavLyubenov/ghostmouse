import Foundation
import CoreGraphics
import ApplicationServices

/// Synthetic input, delivered per-process with `CGEvent.postToPid` so the
/// pointer never has to move and focus is not stolen from the user.
enum Input {

    private static let source = CGEventSource(stateID: .hidSystemState)

    // MARK: - Mouse

    static func click(pid: pid_t, at globalPoint: CGPoint, button: CGMouseButton, count: Int, global: Bool = false) {
        let (down, up): (CGEventType, CGEventType)
        switch button {
        case .right: (down, up) = (.rightMouseDown, .rightMouseUp)
        case .center: (down, up) = (.otherMouseDown, .otherMouseUp)
        default: (down, up) = (.leftMouseDown, .leftMouseUp)
        }
        for i in 0..<max(1, count) {
            let d = CGEvent(mouseEventSource: source, mouseType: down, mouseCursorPosition: globalPoint, mouseButton: button)
            let u = CGEvent(mouseEventSource: source, mouseType: up, mouseCursorPosition: globalPoint, mouseButton: button)
            if count > 1 {
                d?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
                u?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
            }
            if global {
                // Some web views only react after seeing pointer motion.
                let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                   mouseCursorPosition: globalPoint, mouseButton: button)
                move?.post(tap: .cghidEventTap)
                usleep(30_000)
                d?.post(tap: .cghidEventTap)
                usleep(90_000)
                u?.post(tap: .cghidEventTap)
            } else {
                d?.postToPid(pid)
                usleep(60_000)
                u?.postToPid(pid)
            }
            usleep(40_000)
        }
    }

    static func move(pid: pid_t, to globalPoint: CGPoint, global: Bool = true) {
        let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                        mouseCursorPosition: globalPoint, mouseButton: .left)
        if global { e?.post(tap: .cghidEventTap) } else { e?.postToPid(pid) }
    }

    static func drag(pid: pid_t, from: CGPoint, to: CGPoint, steps: Int = 24) {
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: from, mouseButton: .left)
        down?.postToPid(pid)
        usleep(60_000)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            let move = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)
            move?.postToPid(pid)
            usleep(8_000)
        }
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: to, mouseButton: .left)
        up?.postToPid(pid)
    }

    static func scroll(pid: pid_t, at globalPoint: CGPoint, pages: Double, direction: String) {
        // One "page" is roughly 800 px of content on a 2x display.
        let magnitude = Int32(max(1.0, pages * 800))
        let dx: Int32, dy: Int32
        switch direction.lowercased() {
        case "up": (dx, dy) = (0, -magnitude)
        case "down": (dx, dy) = (0, magnitude)
        case "left": (dx, dy) = (-magnitude, 0)
        case "right": (dx, dy) = (magnitude, 0)
        default: (dx, dy) = (0, magnitude)
        }
        let steps = 8
        for _ in 0..<steps {
            let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: dy / Int32(steps), wheel2: dx / Int32(steps), wheel3: 0)
            e?.location = globalPoint
            e?.postToPid(pid)
            usleep(12_000)
        }
    }

    // MARK: - Keyboard

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "equal": 24, "9": 25, "7": 26,
        "minus": 27, "8": 28, "0": 29, "bracketright": 30, "o": 31, "u": 32, "bracketleft": 33,
        "i": 34, "p": 35, "Return": 36, "Enter": 36, "l": 37, "j": 38, "apostrophe": 39, "k": 40,
        "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "n": 45, "m": 46, "period": 47,
        "Tab": 48, "space": 49, "grave": 50, "BackSpace": 51, "Escape": 53,
        "super": 55, "Shift_L": 56, "Caps_Lock": 57, "Option_L": 58, "Control_L": 59,
        "Shift_R": 60, "Option_R": 61, "Control_R": 62, "KP_Decimal": 65, "KP_Multiply": 67,
        "KP_Add": 69, "KP_Subtract": 78, "KP_Divide": 75, "KP_Enter": 76,
        "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100,
        "F9": 101, "F10": 109, "F11": 103, "F12": 111,
        "Home": 115, "End": 119, "Page_Up": 116, "Page_Down": 121, "Delete": 117,
        "Left": 123, "Right": 124, "Down": 125, "Up": 126,
        "KP_0": 82, "KP_1": 83, "KP_2": 84, "KP_3": 85, "KP_4": 86,
        "KP_5": 87, "KP_6": 88, "KP_7": 89, "KP_8": 91, "KP_9": 92
    ]

    private static let modifierFlags: [String: CGEventFlags] = [
        "shift": .maskShift, "super": .maskCommand, "cmd": .maskCommand, "command": .maskCommand,
        "ctrl": .maskControl, "control": .maskControl, "alt": .maskAlternate,
        "option": .maskAlternate, "opt": .maskAlternate, "fn": .maskSecondaryFn
    ]

    enum KeySpec {
        case ok(CGKeyCode, CGEventFlags)
        case bad(String)
    }

    /// Pure resolution of an xdotool-style key spec: no events are posted.
    static func resolveKey(_ spec: String) -> KeySpec {
        let parts = spec.split(separator: "+").map(String.init)
        guard let keyPart = parts.last, !keyPart.isEmpty else { return .bad("empty key spec") }
        var flags: CGEventFlags = []
        for mod in parts.dropLast() {
            guard let f = modifierFlags[mod.lowercased()] else {
                return .bad("unknown modifier '\(mod)'")
            }
            flags.insert(f)
        }
        guard let code = keyCodes[keyPart] ?? keyCodes[keyPart.lowercased()] else {
            return .bad("unknown key '\(keyPart)'")
        }
        return .ok(code, flags)
    }

    static func describeKey(_ spec: String) -> String {
        switch resolveKey(spec) {
        case .ok(let code, let flags): return "keycode \(code), flags \(flags.rawValue)"
        case .bad(let e): return "error: \(e)"
        }
    }

    /// Accepts xdotool-style specs: "a", "Return", "super+c", "shift+Tab".
    static func pressKey(pid: pid_t, spec: String) -> String? {
        switch resolveKey(spec) {
        case .bad(let e):
            return e
        case .ok(let code, let flags):
            let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            down?.postToPid(pid)
            usleep(12_000)
            up?.postToPid(pid)
            return nil
        }
    }

    static func typeText(pid: pid_t, text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            var end = min(i + 20, units.count)
            // never split a surrogate pair across chunks
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end += 1 }
            let chunk = Array(units[i..<end])
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            chunk.withUnsafeBufferPointer { buf in
                down?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                up?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            down?.postToPid(pid)
            usleep(3_000)
            up?.postToPid(pid)
            i = end
            usleep(6_000)
        }
    }
}
