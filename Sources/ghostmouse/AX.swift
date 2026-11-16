import Foundation
import GhostMouseCore
import AppKit
import ApplicationServices

/// Minimal accessibility wrapper: app discovery, tree walk, element handles and actions.
enum AX {

    // MARK: - Permissions

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - App discovery

    struct AppInfo {
        let pid: pid_t
        let name: String
        let bundleID: String
        let path: String
        let active: Bool
        let hidden: Bool
    }

    static func runningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular || $0.activationPolicy == .accessory }
            .map {
                AppInfo(
                    pid: $0.processIdentifier,
                    name: $0.localizedName ?? "?",
                    bundleID: $0.bundleIdentifier ?? "?",
                    path: $0.bundleURL?.path ?? "?",
                    active: $0.isActive,
                    hidden: $0.isHidden
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func resolveApp(_ spec: String) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        let needle = spec.lowercased()
        // bundle id
        if let exact = apps.first(where: { ($0.bundleIdentifier ?? "").lowercased() == needle }) {
            return exact
        }
        // path
        if let byPath = apps.first(where: { ($0.bundleURL?.path ?? "").lowercased() == needle }) {
            return byPath
        }
        // exact name, then prefix
        if let byName = apps.first(where: { ($0.localizedName ?? "").lowercased() == needle }) {
            return byName
        }
        if let byPrefix = apps.first(where: { ($0.localizedName ?? "").lowercased().hasPrefix(needle) }) {
            return byPrefix
        }
        // not running: launch by bundle id or path
        if spec.contains("/"), FileManager.default.fileExists(atPath: spec) {
            return launch(path: spec)
        }
        return nil
    }

    static func launch(path: String) -> NSRunningApplication? {
        let url = URL(fileURLWithPath: path)
        let cfg = NSWorkspace.OpenConfiguration()
        var result: NSRunningApplication?
        let sem = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { app, _ in
            result = app
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        return result
    }

    // MARK: - Attribute helpers

    static func copy(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as AnyObject?
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        guard let v = copy(el, name) else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    static func children(_ el: AXUIElement) -> [AXUIElement] {
        if let v = copy(el, kAXChildrenAttribute as String) as? [AXUIElement], !v.isEmpty { return v }
        if let v = copy(el, "AXChildrenInNavigationOrder") as? [AXUIElement], !v.isEmpty { return v }
        return []
    }

    static func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
        guard let v = copy(el, name) else { return nil }
        var p = CGPoint.zero
        if CFGetTypeID(v) == AXValueGetTypeID(),
           AXValueGetValue(v as! AXValue, .cgPoint, &p) { return p }
        return nil
    }

    static func size(_ el: AXUIElement, _ name: String) -> CGSize? {
        guard let v = copy(el, name) else { return nil }
        var s = CGSize.zero
        if CFGetTypeID(v) == AXValueGetTypeID(),
           AXValueGetValue(v as! AXValue, .cgSize, &s) { return s }
        return nil
    }

    static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: - Tree

    struct Node {
        let index: Int
        let element: AXUIElement
        let depth: Int
        let path: String
        let role: String
        let title: String
        let value: String
        let identifier: String
        let frame: CGRect?
        let actions: [String]

        var summary: String {
            var s = role
            if !title.isEmpty { s += " \"\(title)\"" }
            if !identifier.isEmpty { s += " id=\(identifier)" }
            if let f = frame, f.width > 0 || f.height > 0 {
                s += " @\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height))"
            }
            if !value.isEmpty { s += " value=\"\(value)\"" }
            return s
        }
    }

    struct Tree {
        let app: String
        let bundleID: String
        let pid: pid_t
        let window: CGRect
        let nodes: [Node]
        var byIndex: [Int: Node] { Dictionary(uniqueKeysWithValues: nodes.map { ($0.index, $0) }) }

        func render() -> String {
            var out = "app: \(app) (\(bundleID)) pid \(pid)\n"
            out += "window: \(Int(window.origin.x)),\(Int(window.origin.y)) \(Int(window.width))x\(Int(window.height))\n"
            for n in nodes {
                let pad = String(repeating: "  ", count: n.depth)
                out += "\(pad)[\(n.index)] \(n.summary)\n"
            }
            return out
        }

        /// Pure-data projection used for diffing and quiescence checks.
        var snapshot: Snapshot {
            let win = "window: \(Int(window.origin.x)),\(Int(window.origin.y)) \(Int(window.width))x\(Int(window.height))"
            return Snapshot(app: app, bundleID: bundleID, pid: pid, windowDescription: win,
                            nodes: nodes.map {
                                NodeSummary(index: $0.index, depth: $0.depth, path: $0.path, summary: $0.summary)
                            })
        }

        var signature: UInt64 { snapshot.signature }
    }

    /// Walk the focused window of an app and number every node in DFS order.
    static func tree(for app: NSRunningApplication, maxNodes: Int = 2000, maxDepth: Int = 80) -> Tree {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var roots: [AXUIElement] = []
        if let focused = copy(ax, kAXFocusedWindowAttribute as String) {
            roots = [focused as! AXUIElement]
        } else if let windows = copy(ax, kAXWindowsAttribute as String) as? [AXUIElement], let first = windows.first {
            roots = [first]
        } else {
            roots = [ax]
        }

        var nodes: [Node] = []
        var windowFrame = CGRect.zero

        func walk(_ el: AXUIElement, depth: Int, path: String, counter: inout Int) {
            guard counter < maxNodes, depth < maxDepth else { return }
            let role = string(el, kAXRoleAttribute as String) ?? "?"
            let title = string(el, kAXTitleAttribute as String)
                ?? string(el, kAXDescriptionAttribute as String)
                ?? ""
            let value = (string(el, kAXValueAttribute as String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let ident = string(el, "AXIdentifier") ?? ""
            var frame: CGRect? = nil
            if let p = point(el, kAXPositionAttribute as String), let s = size(el, kAXSizeAttribute as String) {
                frame = CGRect(origin: p, size: s)
            }
            let idx = counter
            counter += 1
            if role == "AXWindow", let f = frame, f.width > 1 {
                windowFrame = f
            }
            nodes.append(Node(index: idx, element: el, depth: depth, path: path, role: role,
                              title: String(title.prefix(300)),
                              value: String(value.prefix(300)),
                              identifier: ident, frame: frame, actions: actions(el)))
            var childIndex = 0
            for child in children(el) {
                walk(child, depth: depth + 1, path: path + "/" + role + "[" + String(childIndex) + "]",
                     counter: &counter)
                childIndex += 1
            }
        }

        var counter = 0
        for r in roots { walk(r, depth: 0, path: "root", counter: &counter) }

        if windowFrame == CGRect.zero, let f = nodes.first(where: { $0.role == "AXWindow" })?.frame {
            windowFrame = f
        }

        return Tree(app: app.localizedName ?? "?",
                    bundleID: app.bundleIdentifier ?? "?",
                    pid: app.processIdentifier,
                    window: windowFrame,
                    nodes: nodes)
    }

    // MARK: - Mutations

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(el, action as CFString)
    }

    @discardableResult
    static func setValue(_ el: AXUIElement, _ value: String) -> AXError {
        AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFString)
    }

    @discardableResult
    static func setSelectedText(_ el: AXUIElement, _ text: String) -> AXError {
        AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString)
    }

    @discardableResult
    static func setSelectionRange(_ el: AXUIElement, location: Int, length: Int) -> AXError {
        var range = CFRange(location: location, length: length)
        guard let v = AXValueCreate(.cfRange, &range) else { return .failure }
        return AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, v)
    }


    /// Every place a browser might keep the current page URL, best first.
    static func pageURLSignals(app: NSRunningApplication) -> [String] {
        var out: [String] = []
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var window: AXUIElement?
        if let v = copy(ax, kAXFocusedWindowAttribute as String) { window = (v as! AXUIElement) }
        guard let w = window else { return out }

        if let doc = string(w, kAXDocumentAttribute as String), !doc.isEmpty { out.append(doc) }
        if let url = string(w, "AXURL"), !url.isEmpty { out.append(url) }

        var queue: [AXUIElement] = children(w)
        var visited = 0
        while let next = queue.first, visited < 300 {
            queue.removeFirst(); visited += 1
            if string(next, kAXRoleAttribute as String) == "AXWebArea" {
                if let url = string(next, "AXURL"), !url.isEmpty { out.append(url) }
                if let doc = string(next, kAXDocumentAttribute as String), !doc.isEmpty { out.append(doc) }
            }
            queue.append(contentsOf: children(next))
        }

        if let title = string(w, kAXTitleAttribute as String), let guess = GhostMouseCore.TargetPolicy.urlFromTitle(title) {
            out.append(guess)
        }
        return out
    }

    /// Debug aid: report where a browser window keeps its URL.
    static func dumpURLs(app: NSRunningApplication) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var window: AXUIElement?
        if let v = copy(ax, kAXFocusedWindowAttribute as String) { window = (v as! AXUIElement) }
        guard let w = window else { print("no focused window"); return }

        func report(_ el: AXUIElement, _ label: String) {
            var names: CFArray?
            AXUIElementCopyAttributeNames(el, &names)
            let attrs = (names as? [String]) ?? []
            print("\(label): \(attrs.count) attributes")
            for name in attrs where ["AXDocument", "AXURL", "AXTitle", "AXRole"].contains(name) {
                print("   \(name) = \(string(el, name) ?? "<nil>")")
            }
        }

        report(w, "window")
        var queue: [AXUIElement] = children(w)
        var visited = 0
        while let next = queue.first, visited < 500 {
            queue.removeFirst(); visited += 1
            let role = string(next, kAXRoleAttribute as String) ?? ""
            if role == "AXWebArea" || role == "AXGroup" {
                report(next, "\(role)")
            }
            queue.append(contentsOf: children(next))
        }
    }

    /// Cheap position/size read for a running app's focused window.
    static func windowFrame(app: NSRunningApplication) -> CGRect? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let v = copy(ax, kAXFocusedWindowAttribute as String) else { return nil }
        let w = v as! AXUIElement
        guard let p = point(w, kAXPositionAttribute as String),
              let s = size(w, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// The page a browser window currently shows, if it exposes one.
    static func windowURL(app: NSRunningApplication) -> String? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var window: AXUIElement?
        if let v = copy(ax, kAXFocusedWindowAttribute as String) {
            window = (v as! AXUIElement)
        } else if let windows = copy(ax, kAXWindowsAttribute as String) as? [AXUIElement], let first = windows.first {
            window = first
        }
        guard let w = window else { return nil }
        if let doc = string(w, kAXDocumentAttribute as String), !doc.isEmpty { return doc }
        if let url = string(w, "AXURL"), !url.isEmpty { return url }

        // Web content usually carries the URL on the AXWebArea rather than the window.
        var queue: [AXUIElement] = [w]
        var visited = 0
        while let next = queue.first, visited < 200 {
            queue.removeFirst()
            visited += 1
            let role = string(next, kAXRoleAttribute as String) ?? ""
            if role == "AXWebArea" {
                if let url = string(next, "AXURL"), !url.isEmpty { return url }
                if let doc = string(next, kAXDocumentAttribute as String), !doc.isEmpty { return doc }
            }
            queue.append(contentsOf: children(next))
        }
        return nil
    }

    static func focusedElement(of app: NSRunningApplication) -> AXUIElement? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let v = copy(ax, kAXFocusedUIElementAttribute as String) else { return nil }
        return (v as! AXUIElement)
    }

    /// Bring an app forward through the accessibility API, which works for
    /// background/accessory callers where NSRunningApplication.activate() is refused.
    static func forceFrontmost(_ app: NSRunningApplication) {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let v = copy(ax, kAXFocusedWindowAttribute as String) {
            AXUIElementPerformAction(v as! AXUIElement, kAXRaiseAction as CFString)
        }
        AX.activate(app)
    }

    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
