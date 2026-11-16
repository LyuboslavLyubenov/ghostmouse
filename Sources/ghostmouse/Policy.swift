import Foundation
import AppKit
import GhostMouseCore

/// Thin adapter over GhostMouseCore's pure policy, plus the app-level checks that need
/// AppKit.
enum Policy {

    struct Denied: Error { let reason: String }
    struct NeedsApproval: Error { let bundleID: String; let name: String }

    static let deniedBundleIDs = TargetPolicy.deniedBundleIDs

    static var storeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GhostMouse", isDirectory: true)
    }

    static var store: PolicyStore { PolicyStore(directory: storeDirectory) }
    static var storeURL: URL { store.fileURL }

    static var autoApprove: Bool {
        ProcessInfo.processInfo.environment["GM_AUTO_APPROVE"] == "1"
    }

    // MARK: - Checks

    static func denialReason(for app: NSRunningApplication) -> String? {
        TargetPolicy.denialReason(bundleID: app.bundleIdentifier,
                                  name: app.localizedName ?? "?",
                                  path: app.bundleURL?.path)
    }

    static func isApproved(_ bundleID: String) -> Bool {
        store.isApproved(bundleID, autoApprove: autoApprove)
    }

    static func authorize(_ app: NSRunningApplication) throws -> String {
        if let reason = denialReason(for: app) {
            throw Denied(reason: "Automation is blocked for \(reason). This is a hard rule and cannot be approved.")
        }
        let bundle = app.bundleIdentifier ?? "unknown"
        if isApproved(bundle) { return "" }
        throw NeedsApproval(bundleID: bundle, name: app.localizedName ?? bundle)
    }

    /// Page-level guard, applied only to browsers. Returns the first denial across
    /// every URL signal the app exposes, or nil when nothing is judgeable.
    static func urlDenialReason(for app: NSRunningApplication, signals: [String]) -> String? {
        guard TargetPolicy.isBrowser(app.bundleIdentifier) else { return nil }
        for signal in signals {
            if let reason = TargetPolicy.urlDenialReason(signal) { return reason }
        }
        return nil
    }

    static func hasJudgeableURL(for app: NSRunningApplication) -> Bool {
        guard TargetPolicy.isBrowser(app.bundleIdentifier) else { return true }
        return !AX.pageURLSignals(app: app).isEmpty
    }

    // MARK: - Store

    @discardableResult
    static func approve(_ bundleID: String) throws -> Bool {
        try store.approve(bundleID)
        return true
    }

    static func approvals() -> [String: Any] { store.approvals() }

    static func revoke(_ bundleID: String) throws { try store.revoke(bundleID) }
}
