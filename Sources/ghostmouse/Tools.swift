import Foundation
import GhostMouseCore
import AppKit
import CoreGraphics

/// Tool definitions, session state and dispatch. The names, parameters and
/// Tool surface: snapshot, act, and read the operating guide.
enum Tools {

    struct AppState {
        let tree: AX.Tree
        let shot: Capture.Shot?
        let at: Date
    }

    static var states: [pid_t: AppState] = [:]

    // MARK: - Schema

    static func definitions() -> [[String: Any]] {
        func tool(_ name: String, _ description: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
            [
                "name": name,
                "description": description,
                "inputSchema": ["type": "object", "properties": props, "required": required]
            ]
        }
        let app = ["type": "string", "description": "App name, path, or bundle identifier"]
        let index = ["type": "integer", "description": "Element index from the latest get_app_state"]
        let x = ["type": "number", "description": "X in screenshot pixels"]
        let y = ["type": "number", "description": "Y in screenshot pixels"]

        return [
            tool("list_apps",
                 "List running applications with name, bundle identifier, path and pid.",
                 [:], []),
            tool("get_app_state",
                 "Snapshot an app's key window: accessibility tree with numbered elements, a screenshot, and recognised text when the tree is sparse. Call this before acting, because element indices come from the snapshot.",
                 ["app": app], ["app"]),
            tool("click",
                 "Click an element by index, or click screenshot pixels. Use the right button to open context menus.",
                 ["app": app, "element_index": index, "x": x, "y": y,
                  "click_count": ["type": "integer", "description": "Click count, default 1"],
                  "mouse_button": ["type": "string", "enum": ["left", "right", "middle"],
                                   "description": "Button, default left"]],
                 ["app"]),
            tool("perform_secondary_action",
                 "Run a named secondary accessibility action on an element.",
                 ["app": app, "element_index": index,
                  "action": ["type": "string", "description": "Action name from the element's action list"]],
                 ["app", "element_index", "action"]),
            tool("set_value",
                 "Set the value of a settable accessibility element.",
                 ["app": app, "element_index": index, "value": ["type": "string", "description": "New value"]],
                 ["app", "element_index", "value"]),
            tool("select_text",
                 "Select text inside a text element, or place the caret before or after it.",
                 ["app": app, "element_index": index,
                  "text": ["type": "string", "description": "Text to select"],
                  "prefix": ["type": "string", "description": "Optional text before the target, to disambiguate"],
                  "suffix": ["type": "string", "description": "Optional text after the target, to disambiguate"],
                  "mode": ["type": "string", "enum": ["text", "cursor_before", "cursor_after"],
                           "description": "Select the text or move the caret, default text"]],
                 ["app", "element_index", "text"]),
            tool("scroll",
                 "Scroll a pane by a number of pages in one direction.",
                 ["app": app, "direction": ["type": "string", "enum": ["up", "down", "left", "right"],
                                            "description": "Direction"],
                  "pages": ["type": "number", "description": "Pages to scroll, fractions allowed, default 1"],
                  "element_index": ["type": "integer", "description": "Scroll at this element instead of the window centre"],
                  "x": ["type": "number", "description": "Scroll at this screenshot X"],
                  "y": ["type": "number", "description": "Scroll at this screenshot Y"]],
                 ["app", "direction"]),
            tool("drag",
                 "Press, move and release between two screenshot points.",
                 ["app": app,
                  "start_x": ["type": "number", "description": "Start X"],
                  "start_y": ["type": "number", "description": "Start Y"],
                  "end_x": ["type": "number", "description": "End X"],
                  "end_y": ["type": "number", "description": "End Y"]],
                 ["app", "start_x", "start_y", "end_x", "end_y"]),
            tool("press_key",
                 "Send a key or key combination. Accepts xdotool style: a, Return, Tab, super+c, Page_Down, KP_0.",
                 ["app": app, "key": ["type": "string", "description": "Key or combination"]],
                 ["app", "key"]),
            tool("hover",
                 "Move the pointer over an element or point without clicking. Reveals controls that only appear on hover.",
                 ["app": app, "element_index": index, "x": x, "y": y],
                 ["app"]),
            tool("type_text",
                 "Type text into the focused element. Unicode and emoji are supported.",
                 ["app": app, "text": ["type": "string", "description": "Text to type"]],
                 ["app", "text"]),
            tool("get_playbook",
                 "Read this server's operating guide, optionally with notes for one app. Read this before concluding an app cannot be driven.",
                 ["app": ["type": "string", "description": "Optional app name, path, or bundle identifier"]],
                 [])
        ]
    }

    // MARK: - Result helpers

    struct ToolResult {
        var text: String
        var image: (base64: String, mime: String)? = nil
        var isError: Bool = false
    }

    // MARK: - Dispatch

    static func call(_ name: String, _ args: [String: Any]) async -> ToolResult {
        do {
            switch name {
            case "list_apps": return listApps()
            case "get_app_state": return try await getAppState(args)
            case "click": return try await click(args)
            case "perform_secondary_action": return try await secondaryAction(args)
            case "set_value": return try await setValue(args)
            case "select_text": return try await selectText(args)
            case "scroll": return try await scroll(args)
            case "drag": return try await drag(args)
            case "press_key": return try await pressKey(args)
            case "hover": return try hover(args)
            case "get_playbook": return getPlaybook(args)
            case "type_text": return try await typeText(args)
            default: return ToolResult(text: "unknown tool '\(name)'", isError: true)
            }
        } catch let e as ToolError {
            return ToolResult(text: e.message, isError: true)
        } catch {
            return ToolResult(text: "\(error)", isError: true)
        }
    }

    struct ToolError: Error { let message: String }

    // MARK: - Focus enforcement

    /// Background-first: the shipped product posts events to the target process and
    /// never moves the user's pointer or steals focus. Activation only happens when
    /// GM_STEAL_FOCUS=1.
    static var stealsFocus: Bool { ProcessInfo.processInfo.environment["GM_STEAL_FOCUS"] == "1" }

    @discardableResult
    private static func prepare(_ app: NSRunningApplication) throws -> String {
        guard stealsFocus else { return " (background: focus left with the user)" }
        // Raising a window that is already frontmost dismisses transient popups
        // (event details, menus), so leave it alone when it already has focus.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            return " (already frontmost)"
        }
        for attempt in 1...3 {
            AX.forceFrontmost(app)
            usleep(120_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return attempt == 1 ? "" : " (re-activated, attempt \(attempt))"
            }
        }
        throw ToolError(message: "could not bring \(app.localizedName ?? "the app") to the front; another app keeps focus. Nothing was sent.")
    }

    /// Web-view apps often ignore per-PID synthetic clicks. If the tree does not
    /// move, repeat the click as a global HID event.
    private static func clickWithFallback(app: NSRunningApplication,
                                          at point: CGPoint,
                                          button: CGMouseButton,
                                          count: Int) {
        // Background mode must never move the real pointer, so the global retry is
        // reserved for explicit focus-stealing runs.
        guard stealsFocus else {
            Input.click(pid: app.processIdentifier, at: point, button: button, count: count)
            return
        }
        let before = AX.tree(for: app).signature
        Input.click(pid: app.processIdentifier, at: point, button: button, count: count)
        usleep(350_000)
        if AX.tree(for: app).signature == before {
            Input.click(pid: app.processIdentifier, at: point, button: button, count: count, global: true)
        }
    }

    /// Settle after a mutating action and report what changed.
    private static func recordAction(_ app: NSRunningApplication,
                                     _ state: AppState,
                                     _ note: String) async -> ToolResult {
        let settled = await Settle.wait(for: app)
        ControlBadge.shared.show(app: app.localizedName ?? "the app", windowFrame: settled.tree.window)
        ControlBadge.shared.track(pid: app.processIdentifier, appName: app.localizedName ?? "the app")
        assertion?.release()
        assertion = nil
        let d = SnapshotDiff.diff(from: state.tree.snapshot, to: settled.tree.snapshot)
        states[app.processIdentifier] = AppState(tree: settled.tree, shot: state.shot, at: Date())
        let ms = Int(settled.elapsed * 1000)
        var text = note
        text += "\nsettled in \(ms) ms (\(settled.mode), \(settled.credits) stable samples)"
        text += "\n" + d.text
        text += "Call `get_app_state` for the full tree and a fresh screenshot."
        return ToolResult(text: text)
    }

    // MARK: - Tools

    private static func listApps() -> ToolResult {
        let apps = AX.runningApps()
        var lines = ["\(apps.count) apps"]
        for a in apps {
            lines.append("\(a.name)\t\(a.bundleID)\t\(a.path)\tpid \(a.pid)\(a.active ? "\tactive" : "")\(a.hidden ? "\thidden" : "")")
        }
        return ToolResult(text: lines.joined(separator: "\n"))
    }

    private static func getAppState(_ args: [String: Any]) async throws -> ToolResult {
        let spec = try requireString(args, "app")
        guard let app = AX.resolveApp(spec) else {
            throw ToolError(message: "no running app matches '\(spec)'. Call list_apps first.")
        }
        let previous = states[app.processIdentifier]?.tree
        ControlBadge.shared.clearCancel()
        try authorize(app)
        assertion?.release()
        assertion = DisplayAssertion()
        defer { assertion?.release(); assertion = nil }
        _ = try? prepare(app)
        ControlBadge.shared.track(pid: app.processIdentifier, appName: app.localizedName ?? "the app")

        if !AX.isTrusted {
            AX.requestTrust()
            return ToolResult(text: "Accessibility permission is not granted. Grant Accessibility to this binary in System Settings > Privacy & Security > Accessibility, then call get_app_state again.", isError: true)
        }

        let settled = await Settle.wait(for: app)
        let tree = settled.tree
        ControlBadge.shared.show(app: app.localizedName ?? tree.app, windowFrame: tree.window)

        var shot: Capture.Shot? = nil
        var note = ""
        do {
            if tree.nodes.count < 40 {
                // Thin UI: capture the screen region so child/overlay windows are included.
                shot = try await Capture.captureRegion(frame: tree.window)
            } else {
                shot = try await Capture.captureWindow(pid: app.processIdentifier, hintFrame: tree.window)
            }
        } catch {
            note = "\n\nscreenshot_capture_failed: \(error)"
            if !Capture.hasPermission { note += " (screen recording permission not granted)" }
        }

        states[app.processIdentifier] = AppState(tree: tree, shot: shot, at: Date())

        let d = SnapshotDiff.diff(from: previous?.snapshot, to: tree.snapshot)
        let settleMs = Int(settled.elapsed * 1000)
        var text = "settled in \(settleMs) ms (\(settled.mode), \(settled.credits) stable samples)\n"
        text += d.text
        text += "\n" + tree.render()
        if let path = ProcessInfo.processInfo.environment["GM_SAVE_PNG"], let shot = shot {
            try? shot.png.write(to: URL(fileURLWithPath: path))
        }
        if !playbooksShown.contains(tree.bundleID),
           let pb = Playbooks.forApp(name: tree.app, bundleID: tree.bundleID) {
            playbooksShown.insert(tree.bundleID)
            text = "playbook for \(tree.app), first call only:\n" + pb + "\n\n" + text
        }
        if tree.nodes.count < 40, let shot = shot {
            let lines = OCR.lines(inPNG: shot.png)
            if !lines.isEmpty {
                text += "\n" + OCR.render(lines)
            }
        }
        text += "\nImage pixel size: \(shot.map { "\(Int($0.pixelSize.width))x\(Int($0.pixelSize.height))" } ?? "none")"
        text += note
        text += "\n\nAction completed. Call `get_app_state` to fetch the updated UI state."

        var result = ToolResult(text: text)
        if let png = shot?.png {
            result.image = (png.base64EncodedString(), "image/png")
        }
        return result
    }

    private static func click(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state) = try stateFor(args)
        let focusNote = try prepare(app)
        let count = args["click_count"] as? Int ?? 1
        let button = (args["mouse_button"] as? String).flatMap { b -> CGMouseButton? in
            switch b { case "right": return .right; case "middle": return .center; default: return .left }
        } ?? .left

        if let idx = args["element_index"] as? Int {
            guard let node = state.tree.byIndex[idx] else {
                let age = Int(Date().timeIntervalSince(state.at))
                throw ToolError(message: "element index \(idx) is stale (last snapshot \(age)s ago). Call `get_app_state` and use a fresh index.")
            }
            if let f = node.frame { VirtualCursor.shared.show(at: CGPoint(x: f.midX, y: f.midY)) }
            if button == .left, node.actions.contains(kAXPressAction as String) {
                let err = AX.perform(node.element, kAXPressAction as String)
                if err == .success {
                    return await recordAction(app, state, "Performed AXPress on [\(idx)] \(node.role).\(focusNote)")
                }
            }
            guard let frame = node.frame else {
                throw ToolError(message: "element [\(idx)] has no frame; pass x/y pixel coordinates instead.")
            }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            VirtualCursor.shared.show(at: center)
            clickWithFallback(app: app, at: center, button: button, count: count)
            return await recordAction(app, state, "Clicked [\(idx)] \(node.role) at screen point \(Int(center.x)),\(Int(center.y)).\(focusNote)")
        }

        guard let px = args["x"] as? Double ?? (args["x"] as? Int).map(Double.init),
              let py = args["y"] as? Double ?? (args["y"] as? Int).map(Double.init) else {
            throw ToolError(message: "click needs element_index or both x and y.")
        }
        let point = try globalPoint(px: px, py: py, state: state)
        VirtualCursor.shared.show(at: point)
        clickWithFallback(app: app, at: point, button: button, count: count)
        return await recordAction(app, state, "Clicked screenshot pixel \(Int(px)),\(Int(py)) => screen \(Int(point.x)),\(Int(point.y)).\(focusNote)")
    }

    private static func secondaryAction(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state, idx) = try elementFor(args)
        let focusNote = try prepare(app)
        guard let node = state.tree.byIndex[idx] else {
            throw ToolError(message: "element index \(idx) is stale. Call `get_app_state`.")
        }
        if let f = node.frame { VirtualCursor.shared.show(at: CGPoint(x: f.midX, y: f.midY), active: false) }
        let action = try requireString(args, "action")
        let err = AX.perform(node.element, action)
        guard err == .success else {
            throw ToolError(message: "AXUIElementPerformAction failed (\(err.rawValue)). Available: \(node.actions.joined(separator: ", "))")
        }
        return await recordAction(app, state, "Performed '\(action)' on [\(idx)] \(node.role).\(focusNote)")
    }

    private static func setValue(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state, idx) = try elementFor(args)
        let focusNote = try prepare(app)
        guard let node = state.tree.byIndex[idx] else {
            throw ToolError(message: "element index \(idx) is stale. Call `get_app_state`.")
        }
        let value = try requireString(args, "value")
        let err = AX.setValue(node.element, value)
        guard err == .success else {
            throw ToolError(message: "setting AXValue failed (\(err.rawValue)); the element may not be settable.")
        }
        return await recordAction(app, state, "Set value of [\(idx)] \(node.role).\(focusNote)")
    }

    private static func selectText(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state, idx) = try elementFor(args)
        let focusNote = try prepare(app)
        guard let node = state.tree.byIndex[idx] else {
            throw ToolError(message: "element index \(idx) is stale. Call `get_app_state`.")
        }
        let text = try requireString(args, "text")
        let mode = args["mode"] as? String ?? "text"
        switch mode {
        case "cursor_before", "cursor_after":
            let length = mode == "cursor_before" ? 0 : text.utf16.count
            let err = AX.setSelectionRange(node.element, location: length == 0 ? 0 : length, length: 0)
            guard err == .success else { throw ToolError(message: "placing the cursor failed (\(err.rawValue)).") }
            return await recordAction(app, state, "Placed cursor \(mode == "cursor_before" ? "before" : "after") the text in [\(idx)].\(focusNote)")
        default:
            let err = AX.setSelectedText(node.element, text)
            guard err == .success else {
                throw ToolError(message: "selecting text failed (\(err.rawValue)); the element may not support AXSelectedText.")
            }
            return await recordAction(app, state, "Selected '\(text.prefix(60))' in [\(idx)] \(node.role).\(focusNote)")
        }
    }

    private static func scroll(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state) = try stateFor(args)
        let focusNote = try prepare(app)
        let direction = try requireString(args, "direction")
        let pages = (args["pages"] as? Double) ?? Double(args["pages"] as? Int ?? 1)
        var anchor = CGPoint(x: state.tree.window.midX, y: state.tree.window.midY)
        if let idx = args["element_index"] as? Int, let node = state.tree.byIndex[idx], let f = node.frame {
            anchor = CGPoint(x: f.midX, y: f.midY)
        }
        if let px = args["x"] as? Double ?? (args["x"] as? Int).map(Double.init),
           let py = args["y"] as? Double ?? (args["y"] as? Int).map(Double.init) {
            anchor = try globalPoint(px: px, py: py, state: state)
        }
        VirtualCursor.shared.show(at: anchor, active: false)
        Input.scroll(pid: app.processIdentifier, at: anchor, pages: pages, direction: direction)
        return await recordAction(app, state, "Scrolled \(direction) \(pages) page(s).\(focusNote)")
    }

    private static func drag(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state) = try stateFor(args)
        let focusNote = try prepare(app)
        let sx = try requireNumber(args, "start_x")
        let sy = try requireNumber(args, "start_y")
        let ex = try requireNumber(args, "end_x")
        let ey = try requireNumber(args, "end_y")
        let from = try globalPoint(px: sx, py: sy, state: state)
        let to = try globalPoint(px: ex, py: ey, state: state)
        VirtualCursor.shared.show(at: from)
        Input.drag(pid: app.processIdentifier, from: from, to: to)
        VirtualCursor.shared.show(at: to)
        return await recordAction(app, state, "Dragged from \(Int(sx)),\(Int(sy)) to \(Int(ex)),\(Int(ey)) in screenshot pixels.\(focusNote)")
    }

    private static func pressKey(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state) = try stateFor(args)
        let focusNote = try prepare(app)
        let key = try requireString(args, "key")
        if let problem = Input.pressKey(pid: app.processIdentifier, spec: key) {
            throw ToolError(message: problem)
        }
        return await recordAction(app, state, "Pressed \(key).\(focusNote)")
    }

    private static var playbooksShown: Set<String> = []

    private static func getPlaybook(_ args: [String: Any]) -> ToolResult {
        var text = Playbooks.general()
        if let spec = args["app"] as? String, !spec.isEmpty {
            let app = AX.resolveApp(spec)
            let name = app?.localizedName ?? spec
            let bundle = app?.bundleIdentifier ?? spec
            if let extra = Playbooks.forApp(name: name, bundleID: bundle) {
                text += "\n\n" + extra
            } else {
                text += "\n\nNo app-specific playbook for '\(name)'. Available: \(Playbooks.catalog().joined(separator: ", "))."
            }
        }
        return ToolResult(text: text)
    }

    private static func hover(_ args: [String: Any]) throws -> ToolResult {
        let (app, state) = try stateFor(args)
        var point: CGPoint
        if let idx = args["element_index"] as? Int, let node = state.tree.byIndex[idx], let f = node.frame {
            point = CGPoint(x: f.midX, y: f.midY)
        } else if let px = args["x"] as? Double ?? (args["x"] as? Int).map(Double.init),
                  let py = args["y"] as? Double ?? (args["y"] as? Int).map(Double.init) {
            point = try globalPoint(px: px, py: py, state: state)
        } else {
            throw ToolError(message: "hover needs element_index or both x and y.")
        }
        VirtualCursor.shared.show(at: point, active: false)
        Input.move(pid: app.processIdentifier, to: point)
        return ToolResult(text: "Hovered \(Int(point.x)),\(Int(point.y)).")
    }

    private static func typeText(_ args: [String: Any]) async throws -> ToolResult {
        let (app, state) = try stateFor(args)
        let focusNote = try prepare(app)
        let text = try requireString(args, "text")
        Input.typeText(pid: app.processIdentifier, text: text)
        return await recordAction(app, state, "Typed \(text.count) characters.\(focusNote)")
    }

    // MARK: - Argument plumbing

    private static func requireString(_ args: [String: Any], _ key: String) throws -> String {
        guard let v = args[key] as? String, !v.isEmpty else {
            throw ToolError(message: "missing required string argument '\(key)'")
        }
        return v
    }

    private static func requireNumber(_ args: [String: Any], _ key: String) throws -> Double {
        if let d = args[key] as? Double { return d }
        if let i = args[key] as? Int { return Double(i) }
        if let n = args[key] as? NSNumber { return n.doubleValue }
        throw ToolError(message: "missing required number argument '\(key)'")
    }

    static var assertion: DisplayAssertion?

    private static func stateFor(_ args: [String: Any]) throws -> (NSRunningApplication, AppState) {
        let spec = try requireString(args, "app")
        guard let app = AX.resolveApp(spec) else {
            throw ToolError(message: "no running app matches '\(spec)'. Call list_apps first.")
        }
        try authorize(app)
        assertion?.release()
        assertion = DisplayAssertion()
        guard let state = states[app.processIdentifier] else {
            throw ToolError(message: "no state for \(app.localizedName ?? spec). Call `get_app_state` first; indices and coordinates come from that call.")
        }
        return (app, state)
    }

    /// Policy gate with readable, model-facing wording.
    private static func authorize(_ app: NSRunningApplication) throws {
        if let cancel = ControlBadge.shared.cancelReason {
            throw ToolError(message: cancel)
        }
        do {
            _ = try Policy.authorize(app)
        } catch let denied as Policy.Denied {
            throw ToolError(message: denied.reason)
        } catch let needs as Policy.NeedsApproval {
            throw ToolError(message: "Automation is blocked from using the app '\(needs.name)' until it is approved. Tell the user to run `ghostmouse approve \(needs.bundleID)` in a terminal, or `ghostmouse approve \"\(needs.name)\"`, then retry. Do not work around this by other means.")
        }
        let signals = AX.pageURLSignals(app: app)
        if let reason = Policy.urlDenialReason(for: app, signals: signals) {
            throw ToolError(message: reason)
        }
    }

    private static func elementFor(_ args: [String: Any]) throws -> (NSRunningApplication, AppState, Int) {
        let (app, state) = try stateFor(args)
        guard let idx = args["element_index"] as? Int else {
            throw ToolError(message: "missing required integer argument 'element_index'")
        }
        return (app, state, idx)
    }

    private static func globalPoint(px: Double, py: Double, state: AppState) throws -> CGPoint {
        guard let shot = state.shot else {
            throw ToolError(message: "no screenshot for this app, so pixel coordinates are unknown. Call `get_app_state` again.")
        }
        let scale = shot.scale
        return CGPoint(x: shot.windowFrame.origin.x + px / scale,
                       y: shot.windowFrame.origin.y + py / scale)
    }
}
