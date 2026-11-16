import Foundation
import CoreGraphics
import AppKit
import GhostMouseCore

// MCP stdio server. Newline-delimited JSON-RPC 2.0 on stdin/stdout;
// all diagnostics go to stderr so the protocol stream stays clean.

func log(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

func fail(_ id: Any?, _ code: Int, _ message: String) {
    let payload: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id ?? NSNull(),
        "error": ["code": code, "message": message]
    ]
    emit(payload)
}

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
          var text = String(data: data, encoding: .utf8) else { return }
    text += "\n"
    FileHandle.standardOutput.write(text.data(using: .utf8)!)
}

func textResult(_ text: String, isError: Bool = false) -> [String: Any] {
    var result: [String: Any] = [
        "content": [["type": "text", "text": text]],
        "isError": isError
    ]
    result["structuredContent"] = ["text": text]
    return result
}

func handle(_ request: [String: Any]) async {
    guard let method = request["method"] as? String else { return }
    let id = request["id"]
    let isCall = request["id"] != nil

    switch method {
    case "initialize":
        let proto = (request["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2024-11-05"
        emit([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "protocolVersion": proto,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "ghostmouse", "version": "0.1.0"],
                "instructions": Playbooks.general()
            ]
        ])

    case "notifications/initialized", "initialized":
        return

    case "ping":
        if isCall { emit(["jsonrpc": "2.0", "id": id!, "result": [:]]) }

    case "tools/list":
        emit([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["tools": Tools.definitions()]
        ])

    case "tools/call":
        let params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        let outcome = await Tools.call(name, args)
        var content: [[String: Any]] = [["type": "text", "text": outcome.text]]
        if let img = outcome.image {
            content.append(["type": "image", "data": img.base64, "mimeType": img.mime])
        }
        emit([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": ["content": content, "isError": outcome.isError]
        ])

    default:
        if isCall { fail(id, -32601, "method not found: \(method)") }
    }
}

// MARK: - Entry

let argv = CommandLine.arguments

if argv.contains("request-permissions") {
    print("before: accessibility=\(AX.isTrusted) screenRecording=\(Capture.hasPermission)")
    AX.requestTrust()               // shows the Accessibility prompt if not yet granted
    _ = Capture.requestPermission()  // shows the Screen Recording prompt and registers the app
    // Give the system a moment to register this binary with TCC before exiting.
    usleep(1_500_000)
    print("after:  accessibility=\(AX.isTrusted) screenRecording=\(Capture.hasPermission)")
    print("If screenRecording is still false, open System Settings > Privacy & Security >")
    print("Screen Recording and switch on 'GhostMouse', then relaunch.")
    exit(0)
}

if let idx = argv.firstIndex(of: "approve"), idx + 1 < argv.count {
    let spec = argv[idx + 1]
    let app = AX.resolveApp(spec)
    let bundle = app?.bundleIdentifier ?? spec
    do {
        try Policy.approve(bundle)
        print("approved \(app?.localizedName ?? spec) [\(bundle)]")
        exit(0)
    } catch {
        print("could not write approval: \(error)")
        exit(1)
    }
}

if let idx = argv.firstIndex(of: "revoke"), idx + 1 < argv.count {
    let spec = argv[idx + 1]
    let bundle = AX.resolveApp(spec)?.bundleIdentifier ?? spec
    do {
        try Policy.revoke(bundle)
        print("revoked \(bundle)")
        exit(0)
    } catch {
        print("could not revoke: \(error)")
        exit(1)
    }
}

if argv.contains("approvals") {
    let dict = Policy.approvals()
    if dict.isEmpty { print("no approvals recorded") }
    for (bundle, value) in dict.sorted(by: { $0.key < $1.key }) {
        print("\(bundle)\t\(value)")
    }
    print("store: \(Policy.storeURL.path)")
    exit(0)
}

if let idx = argv.firstIndex(of: "policy"), idx + 1 < argv.count {
    let spec = argv[idx + 1]
    let bundle = spec.contains(".") ? spec : (AX.resolveApp(spec)?.bundleIdentifier ?? spec)
    let name = AX.resolveApp(spec)?.localizedName ?? spec
    if let reason = TargetPolicy.denialReason(bundleID: bundle, name: name, path: nil) {
        print("denied: \(reason)")
        exit(0)
    }
    print("blocked: no")
    print("approved: \(Policy.isApproved(bundle))")
    print("auto-approve: \(Policy.autoApprove)")
    exit(0)
}

if let idx = argv.firstIndex(of: "dump-url"), idx + 1 < argv.count {
    guard let app = AX.resolveApp(argv[idx + 1]) else {
        print("no running app matches \(argv[idx + 1])")
        exit(1)
    }
    print("app: \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")]")
    AX.dumpURLs(app: app)
    exit(0)
}

if let idx = argv.firstIndex(of: "move-window"), idx + 3 < argv.count {
    // debug helper: nudge a window so the badge tracker can be tested
    guard let app = AX.resolveApp(argv[idx + 1]),
          let dx = Double(argv[idx + 2]), let dy = Double(argv[idx + 3]),
          var frame = AX.windowFrame(app: app) else {
        print("usage: move-window <app> <dx> <dy>")
        exit(1)
    }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    if let v = AX.copy(ax, kAXFocusedWindowAttribute as String) {
        let w = v as! AXUIElement
        frame.origin.x += CGFloat(dx)
        frame.origin.y += CGFloat(dy)
        var p = CGPoint(x: frame.origin.x, y: frame.origin.y)
        if let value = AXValueCreate(.cgPoint, &p) {
            let err = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, value)
            print("moved \(argv[idx + 1]) by \(dx),\(dy) -> \(err == .success ? "ok" : "failed")")
            exit(err == .success ? 0 : 1)
        }
    }
    print("could not move window")
    exit(1)
}

if argv.contains("selftest") {
    print("accessibility trusted: \(AX.isTrusted)")
    print("screen recording: \(Capture.hasPermission)")
    let apps = AX.runningApps()
    print("running apps: \(apps.count)")
    for a in apps.prefix(5) { print("  \(a.name)  \(a.bundleID)") }
    print("tools: \(Tools.definitions().count)")

    // Key-spec parsing is pure, so it is checkable without permissions.
    print("key specs:")
    for spec in ["a", "Return", "super+c", "shift+Tab", "KP_0", "hyper+z", "z+meta"] {
        print("  \(spec) -> \(Input.describeKey(spec))")
    }

    // PNG encoder round-trip on a synthetic image.
    let cs = CGColorSpaceCreateDeviceRGB()
    if let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                           space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
       let img = ctx.makeImage() {
        let png = Capture.encodePNG(img)
        print("png encode: \(png?.count ?? -1) bytes for 4x4")
    }
    exit(0)
}

// MARK: - Server

log("ghostmouse MCP server ready")

/// Process one JSON-RPC message synchronously on the server thread.
func process(_ object: [String: Any]) {
    let sem = DispatchSemaphore(value: 0)
    Task {
        await handle(object)
        sem.signal()
    }
    sem.wait()
}

func serverLoop() {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail(nil, -32700, "parse error")
            continue
        }
        process(obj)
    }
    exit(0)
}

// Windows and the Esc monitor need an app object and a running main loop, so the
// MCP read loop runs on its own thread and the main thread pumps AppKit events.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
ControlBadge.shared.startMonitoring()

Thread.detachNewThread { serverLoop() }
app.run()
