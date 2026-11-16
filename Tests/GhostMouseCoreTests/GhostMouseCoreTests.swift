import XCTest
@testable import GhostMouseCore

final class SettleLogicTests: XCTestCase {

    func testThreeIdenticalSamplesAreSettled() {
        XCTAssertTrue(SettleLogic.isSettled(samples: [7, 7, 7]))
    }

    func testTwoSamplesAreNotEnough() {
        XCTAssertFalse(SettleLogic.isSettled(samples: [7, 7]))
    }

    func testChangingSamplesAreNotSettled() {
        XCTAssertFalse(SettleLogic.isSettled(samples: [7, 7, 8]))
        XCTAssertFalse(SettleLogic.isSettled(samples: [1, 2, 3, 4]))
    }

    func testThresholds() {
        XCTAssertEqual(SettleLogic.requiredStableSamples, 3)
        XCTAssertEqual(SettleLogic.pollIntervalMilliseconds, 100)
        XCTAssertEqual(SettleLogic.ceilingSeconds, 2.0)
        XCTAssertEqual(SettleLogic.thinTreeThreshold, 8)
    }

    func testPixelFallbackOnlyForThinTrees() {
        XCTAssertTrue(SettleLogic.needsPixelFallback(nodeCount: 3))
        XCTAssertFalse(SettleLogic.needsPixelFallback(nodeCount: 8))
    }

    func testCoordinateFlip() {
        // A click 10 px from the top of a 1000 pt screen, cursor 26 pt tall.
        XCTAssertEqual(SettleLogic.flippedY(pointY: 10, screenMaxY: 1000, size: 26), 964)
    }
}

final class SnapshotDiffTests: XCTestCase {

    private func node(_ index: Int, _ path: String, _ summary: String) -> NodeSummary {
        NodeSummary(index: index, depth: 0, path: path, summary: summary)
    }

    private func snapshot(_ nodes: [NodeSummary]) -> Snapshot {
        Snapshot(app: "Test", bundleID: "test.app", pid: 1, windowDescription: "window: 0,0 100x100", nodes: nodes)
    }

    func testInitialSnapshotReportsNodeCount() {
        let result = SnapshotDiff.diff(from: nil, to: snapshot([node(0, "root/AXWindow[0]", "AXWindow \"W\"")]))
        XCTAssertEqual(result.added, 0)
        XCTAssertTrue(result.text.contains("initial snapshot: 1 nodes"))
    }

    func testAddedRemovedChangedCounts() {
        let old = snapshot([
            node(0, "root/AXWindow[0]", "AXWindow"),
            node(1, "root/AXWindow[0]/AXButton[0]", "AXButton \"Save\""),
            node(2, "root/AXWindow[0]/AXButton[1]", "AXButton \"Cancel\"")
        ])
        let new = snapshot([
            node(0, "root/AXWindow[0]", "AXWindow \"Edited\""),
            node(1, "root/AXWindow[0]/AXButton[0]", "AXButton \"Save\""),
            node(2, "root/AXWindow[0]/AXTextField[2]", "AXTextField value=\"hi\"")
        ])
        let result = SnapshotDiff.diff(from: old, to: new)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.changed, 1)
        XCTAssertTrue(result.text.hasPrefix("diff: +1 -1 ~1"))
        XCTAssertTrue(result.text.contains("[+] AXTextField value=\"hi\""))
        XCTAssertTrue(result.text.contains("[-] AXButton \"Cancel\""))
        XCTAssertTrue(result.text.contains("[~] AXWindow"))
        XCTAssertTrue(result.text.contains("-> AXWindow \"Edited\""))
    }

    func testNoChanges() {
        let same = snapshot([node(0, "root/AXWindow[0]", "AXWindow")])
        let result = SnapshotDiff.diff(from: same, to: same)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.text, "diff: +0 -0 ~0\nno changes\n")
    }

    func testOutputIsCapped() {
        let old = snapshot([])
        let many = (0..<100).map { node($0, "root/AXButton[\($0)]", "AXButton \($0)") }
        let result = SnapshotDiff.diff(from: old, to: snapshot(many), lineLimit: 5)
        XCTAssertEqual(result.added, 100)
        let bodyLines = result.text.split(separator: "\n").filter { $0.hasPrefix("[+]") }
        XCTAssertEqual(bodyLines.count, 5)
        XCTAssertTrue(result.text.contains("…"))
    }

    func testSignatureIsStableAndSensitive() {
        let a = snapshot([node(0, "root/AXWindow[0]", "AXWindow")])
        let b = snapshot([node(0, "root/AXWindow[0]", "AXWindow")])
        let c = snapshot([node(0, "root/AXWindow[0]", "AXWindow \"Edited\"")])
        XCTAssertEqual(a.signature, b.signature)
        XCTAssertNotEqual(a.signature, c.signature)
    }
}

final class TargetPolicyTests: XCTestCase {

    func testDeniedBundles() {
        XCTAssertNotNil(TargetPolicy.denialReason(bundleID: "com.apple.SecurityAgent", name: "SecurityAgent", path: nil))
        XCTAssertNotNil(TargetPolicy.denialReason(bundleID: "com.1password.1password", name: "1Password", path: nil))
        XCTAssertNotNil(TargetPolicy.denialReason(bundleID: "com.apple.Passwords", name: "Passwords", path: nil))
    }

    func testDeniedByName() {
        XCTAssertNotNil(TargetPolicy.denialReason(bundleID: "unknown", name: "Keychain Access", path: nil))
    }

    func testOrdinaryAppIsAllowed() {
        XCTAssertNil(TargetPolicy.denialReason(bundleID: "com.apple.TextEdit", name: "TextEdit", path: "/Applications/TextEdit.app"))
    }

    func testBrowserDetection() {
        XCTAssertTrue(TargetPolicy.isBrowser("com.apple.Safari"))
        XCTAssertTrue(TargetPolicy.isBrowser("com.google.Chrome"))
        XCTAssertFalse(TargetPolicy.isBrowser("com.apple.TextEdit"))
        XCTAssertFalse(TargetPolicy.isBrowser(nil))
    }
}

final class URLPolicyTests: XCTestCase {

    func testHTTPSIsAllowed() {
        XCTAssertNil(TargetPolicy.urlDenialReason("https://example.com/page"))
        XCTAssertNil(TargetPolicy.urlDenialReason("http://example.com"))
    }

    func testNonHTTPSchemesAreDenied() {
        XCTAssertNotNil(TargetPolicy.urlDenialReason("file:///etc/passwd"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("javascript:alert(1)"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("data:text/html,hi"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("ftp://example.com"))
    }

    func testPrivateHostsAreDenied() {
        XCTAssertNotNil(TargetPolicy.urlDenialReason("http://localhost:3000/"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("http://127.0.0.1/"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("http://mybox.local/"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("https://service.internal/"))
    }

    func testBlankAndMissingAreAllowed() {
        XCTAssertNil(TargetPolicy.urlDenialReason(nil))
        XCTAssertNil(TargetPolicy.urlDenialReason(""))
        XCTAssertNil(TargetPolicy.urlDenialReason("about:blank"))
        XCTAssertNil(TargetPolicy.urlDenialReason("chrome://newtab/"))
        XCTAssertNotNil(TargetPolicy.urlDenialReason("chrome://settings"))
    }


    func testTitleDerivedURLs() {
        XCTAssertEqual(TargetPolicy.urlFromTitle("\u{200E}localhost:8765/probe.html"),
                       "http://localhost:8765/probe.html")
        XCTAssertEqual(TargetPolicy.urlFromTitle("example.com"), "http://example.com")
        XCTAssertNil(TargetPolicy.urlFromTitle("Google"))
        XCTAssertEqual(TargetPolicy.urlFromTitle("https://x.com/a"), "https://x.com/a")
    }

    func testUnparseableURLIsDenied() {
        XCTAssertNotNil(TargetPolicy.urlDenialReason("not a url at all"))
    }
}

final class PolicyStoreTests: XCTestCase {

    private func tempStore() -> PolicyStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostmouse-tests-" + UUID().uuidString, isDirectory: true)
        return PolicyStore(directory: dir)
    }

    func testApprovalRoundTrip() throws {
        let store = tempStore()
        XCTAssertFalse(store.isApproved("com.apple.TextEdit"))
        try store.approve("com.apple.TextEdit")
        XCTAssertTrue(store.isApproved("com.apple.TextEdit"))
        XCTAssertNotNil(store.approvals()["com.apple.TextEdit"])
        try store.revoke("com.apple.TextEdit")
        XCTAssertFalse(store.isApproved("com.apple.TextEdit"))
    }

    func testAutoApproveBypassesStore() {
        let store = tempStore()
        XCTAssertTrue(store.isApproved("com.example.anything", autoApprove: true))
        XCTAssertFalse(store.isApproved("com.example.anything", autoApprove: false))
    }

    func testApprovalsAreIndependentPerBundle() throws {
        let store = tempStore()
        try store.approve("a.one")
        XCTAssertTrue(store.isApproved("a.one"))
        XCTAssertFalse(store.isApproved("b.two"))
    }
}
