import Foundation

/// Hard denials and the per-app approval store. Pure logic plus file access that
/// takes a directory, so tests can use a temporary one.
public enum TargetPolicy {

    public static let deniedBundleIDs: Set<String> = [
        "com.apple.SecurityAgent",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent.helper",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.1password.safari",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass"
    ]

    public static let deniedNameFragments = [
        "SecurityAgent", "loginwindow", "Keychain Access", "Passwords", "1Password"
    ]

    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium"
    ]

    public static func denialReason(bundleID: String?, name: String, path: String?) -> String? {
        let bundle = bundleID ?? ""
        if deniedBundleIDs.contains(bundle) { return "\(name) is a protected security surface" }
        for fragment in deniedNameFragments where name.localizedCaseInsensitiveContains(fragment) {
            return "\(name) matches a protected security surface"
        }
        if let path = path, path.contains("/System/Library/CoreServices/SecurityAgent") {
            return "\(name) is part of the security agent"
        }
        return nil
    }


    /// Browsers often expose only a window title. If that title is a URL or a bare
    /// host (with optional port and path), treat it as a URL candidate.
    public static func urlFromTitle(_ raw: String) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
        guard !title.isEmpty else { return nil }
        if title.contains("://") { return title }
        let hostLike = #"^[A-Za-z0-9][A-Za-z0-9.-]*(:\d+)?(/.*)?$"#
        if title.range(of: hostLike, options: .regularExpression) != nil,
           (title.contains(".") || title.lowercased().hasPrefix("localhost")) {
            return "http://" + title
        }
        return nil
    }

    public static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return browserBundleIDs.contains(bundleID)
    }

    /// Page-level guard for browser windows. Anything that is not plain http(s), and
    /// anything pointing at a private or loopback host, is refused.
    public static let blockedHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
    public static let blockedHostSuffixes = [".local", ".localhost", ".internal"]
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Blank/new-tab pages are harmless and are where every browsing task starts.
    public static let allowedInternalURLs: Set<String> = [
        "about:blank",
        "about:newtab",
        "chrome://newtab",
        "chrome://new-tab-page",
        "chrome-search://local-ntp",
        "edge://newtab",
        "brave://newtab",
        "vivaldi://newtab"
    ]

    public static func urlDenialReason(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        var internalKey = raw.lowercased()
        while internalKey.hasSuffix("/") { internalKey.removeLast() }
        if allowedInternalURLs.contains(internalKey) { return nil }
        guard let components = URLComponents(string: raw), let scheme = components.scheme?.lowercased() else {
            return "the current page URL could not be parsed, so it cannot be judged safe: \(raw)"
        }
        if !allowedSchemes.contains(scheme) {
            return "Automation is blocked on '\(scheme)' URLs. Only http and https pages can be driven. Blocked URL: \(raw)"
        }
        let host = (components.host ?? "").lowercased()
        if host.isEmpty { return nil }
        if blockedHosts.contains(host) || blockedHostSuffixes.contains(where: { host.hasSuffix($0) }) {
            return "Automation is blocked on private or loopback hosts. Blocked URL: \(raw)"
        }
        return nil
    }
}

/// Approval records live in one JSON file.
public struct PolicyStore {

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("approvals.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    public func approvals() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }

    public func isApproved(_ bundleID: String, autoApprove: Bool = false) -> Bool {
        if autoApprove { return true }
        return approvals()[bundleID] != nil
    }

    public func approve(_ bundleID: String, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var dict = approvals()
        dict[bundleID] = ["approvedAt": ISO8601DateFormatter().string(from: date)]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    public func revoke(_ bundleID: String) throws {
        var dict = approvals()
        dict.removeValue(forKey: bundleID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
}
