import Foundation
import GhostMouseCore

// Plain assertion harness.
//
// `swift test` needs XCTest or swift-testing, and this machine has Command Line
// Tools only (no Xcode), so neither module exists. This runner exercises the same
// cases through `swift run ghostmouse-tests` and exits non-zero on any failure.

var failures = 0
var checks = 0

func check(_ name: String, _ condition: Bool) {
    checks += 1
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func equal<T: Equatable>(_ name: String, _ a: T, _ b: T) {
    checks += 1
    if a == b {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)  (got \(a), want \(b))")
    }
}

// MARK: Settling

print("\n# Settling")
check("three identical samples settle", SettleLogic.isSettled(samples: [7, 7, 7]))
check("two samples are not enough", !SettleLogic.isSettled(samples: [7, 7]))
check("changing samples do not settle", !SettleLogic.isSettled(samples: [7, 7, 8]))
check("long alternating run does not settle", !SettleLogic.isSettled(samples: [1, 2, 3, 4]))
equal("required samples", SettleLogic.requiredStableSamples, 3)
equal("poll interval ms", SettleLogic.pollIntervalMilliseconds, 100)
equal("ceiling seconds", SettleLogic.ceilingSeconds, 2.0)
equal("thin tree threshold", SettleLogic.thinTreeThreshold, 8)
check("thin tree needs pixels", SettleLogic.needsPixelFallback(nodeCount: 3))
check("rich tree does not", !SettleLogic.needsPixelFallback(nodeCount: 8))
equal("coordinate flip", SettleLogic.flippedY(pointY: 10, screenMaxY: 1000, size: 26), 964)

// MARK: Diffing

print("\n# Diffing")
func node(_ i: Int, _ path: String, _ summary: String) -> NodeSummary {
    NodeSummary(index: i, depth: 0, path: path, summary: summary)
}
func snap(_ nodes: [NodeSummary]) -> Snapshot {
    Snapshot(app: "Test", bundleID: "test.app", pid: 1, windowDescription: "window: 0,0 100x100", nodes: nodes)
}

let initial = SnapshotDiff.diff(from: nil, to: snap([node(0, "root/AXWindow[0]", "AXWindow \"W\"")]))
check("initial snapshot reports count", initial.text.contains("initial snapshot: 1 nodes"))

let oldSnap = snap([
    node(0, "root/AXWindow[0]", "AXWindow"),
    node(1, "root/AXWindow[0]/AXButton[0]", "AXButton \"Save\""),
    node(2, "root/AXWindow[0]/AXButton[1]", "AXButton \"Cancel\"")
])
let newSnap = snap([
    node(0, "root/AXWindow[0]", "AXWindow \"Edited\""),
    node(1, "root/AXWindow[0]/AXButton[0]", "AXButton \"Save\""),
    node(2, "root/AXWindow[0]/AXTextField[2]", "AXTextField value=\"hi\"")
])
let d = SnapshotDiff.diff(from: oldSnap, to: newSnap)
equal("added count", d.added, 1)
equal("removed count", d.removed, 1)
equal("changed count", d.changed, 1)
check("diff header", d.text.hasPrefix("diff: +1 -1 ~1"))
check("added line", d.text.contains("[+] AXTextField value=\"hi\""))
check("removed line", d.text.contains("[-] AXButton \"Cancel\""))
check("changed line", d.text.contains("[~] AXWindow") && d.text.contains("-> AXWindow \"Edited\""))

let same = snap([node(0, "root/AXWindow[0]", "AXWindow")])
let none = SnapshotDiff.diff(from: same, to: same)
check("no changes empty", none.isEmpty)
equal("no changes text", none.text, "diff: +0 -0 ~0\nno changes\n")

let many = (0..<100).map { node($0, "root/AXButton[\($0)]", "AXButton \($0)") }
let capped = SnapshotDiff.diff(from: snap([]), to: snap(many), lineLimit: 5)
equal("capped added count", capped.added, 100)
equal("capped emitted lines", capped.text.split(separator: "\n").filter { $0.hasPrefix("[+]") }.count, 5)
check("cap marker", capped.text.contains("…"))

equal("signature stable",
      snap([node(0, "root/AXWindow[0]", "AXWindow")]).signature,
      snap([node(0, "root/AXWindow[0]", "AXWindow")]).signature)
check("signature sensitive",
      snap([node(0, "root/AXWindow[0]", "AXWindow")]).signature
      != snap([node(0, "root/AXWindow[0]", "AXWindow \"Edited\"")]).signature)

// MARK: Target policy

print("\n# Target policy")
check("denied bundle SecurityAgent",
      TargetPolicy.denialReason(bundleID: "com.apple.SecurityAgent", name: "SecurityAgent", path: nil) != nil)
check("denied bundle 1Password",
      TargetPolicy.denialReason(bundleID: "com.1password.1password", name: "1Password", path: nil) != nil)
check("denied bundle Passwords",
      TargetPolicy.denialReason(bundleID: "com.apple.Passwords", name: "Passwords", path: nil) != nil)
check("denied by name fragment",
      TargetPolicy.denialReason(bundleID: "unknown", name: "Keychain Access", path: nil) != nil)
check("ordinary app allowed",
      TargetPolicy.denialReason(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/Applications/TextEdit.app") == nil)
check("Safari is a browser", TargetPolicy.isBrowser("com.apple.Safari"))
check("Chrome is a browser", TargetPolicy.isBrowser("com.google.Chrome"))
check("TextEdit is not a browser", !TargetPolicy.isBrowser("com.apple.TextEdit"))
check("nil bundle is not a browser", !TargetPolicy.isBrowser(nil))

// MARK: URL guard

print("\n# URL guard")
check("https allowed", TargetPolicy.urlDenialReason("https://example.com/page") == nil)
check("http allowed", TargetPolicy.urlDenialReason("http://example.com") == nil)
check("file denied", TargetPolicy.urlDenialReason("file:///etc/passwd") != nil)
check("javascript denied", TargetPolicy.urlDenialReason("javascript:alert(1)") != nil)
check("data denied", TargetPolicy.urlDenialReason("data:text/html,hi") != nil)
check("ftp denied", TargetPolicy.urlDenialReason("ftp://example.com") != nil)
check("localhost denied", TargetPolicy.urlDenialReason("http://localhost:3000/") != nil)
check("loopback denied", TargetPolicy.urlDenialReason("http://127.0.0.1/") != nil)
check("mDNS denied", TargetPolicy.urlDenialReason("http://mybox.local/") != nil)
check("internal denied", TargetPolicy.urlDenialReason("https://service.internal/") != nil)
check("nil allowed", TargetPolicy.urlDenialReason(nil) == nil)
check("empty allowed", TargetPolicy.urlDenialReason("") == nil)
check("about:blank allowed", TargetPolicy.urlDenialReason("about:blank") == nil)
check("chrome://newtab allowed", TargetPolicy.urlDenialReason("chrome://newtab/") == nil)
check("chrome://settings denied", TargetPolicy.urlDenialReason("chrome://settings") != nil)
check("edge://newtab allowed", TargetPolicy.urlDenialReason("edge://newtab") == nil)
check("unparseable denied", TargetPolicy.urlDenialReason("not a url at all") != nil)

// MARK: Approval store


print("\n# URL signals from titles")
equal("title to url (localhost)", TargetPolicy.urlFromTitle("\u{200E}localhost:8765/probe.html") ?? "nil",
      "http://localhost:8765/probe.html")
check("localhost title is denied", TargetPolicy.urlDenialReason(TargetPolicy.urlFromTitle("localhost:8765/probe.html")) != nil)
equal("title to url (domain)", TargetPolicy.urlFromTitle("example.com") ?? "nil", "http://example.com")
check("plain domain title allowed", TargetPolicy.urlDenialReason(TargetPolicy.urlFromTitle("example.com")) == nil)
check("ordinary page title is not a url", TargetPolicy.urlFromTitle("Google") == nil)
check("mDNS title denied", TargetPolicy.urlDenialReason(TargetPolicy.urlFromTitle("mybox.local")) != nil)
equal("explicit scheme kept", TargetPolicy.urlFromTitle("https://x.com/a") ?? "nil", "https://x.com/a")

print("\n# Approval store")
let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("ghostmouse-tests-" + UUID().uuidString, isDirectory: true)
let store = PolicyStore(directory: dir)
check("initially unapproved", !store.isApproved("com.apple.TextEdit"))
do {
    try store.approve("com.apple.TextEdit")
    check("approved after write", store.isApproved("com.apple.TextEdit"))
    check("record persisted", store.approvals()["com.apple.TextEdit"] != nil)
    check("other bundle unaffected", !store.isApproved("b.two"))
    try store.revoke("com.apple.TextEdit")
    check("revoked", !store.isApproved("com.apple.TextEdit"))
} catch {
    check("store operations threw: \(error)", false)
}
check("auto approve bypasses store", store.isApproved("com.example.anything", autoApprove: true))
check("auto approve off respects store", !store.isApproved("com.example.anything", autoApprove: false))

print("\n\(checks - failures)/\(checks) checks passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}
