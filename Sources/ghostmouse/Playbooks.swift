import Foundation

/// Per-app playbooks, written from what actually worked. Served through MCP
/// `initialize.instructions` and the `get_playbook` tool, and attached to the first
/// snapshot of a matching app.
enum Playbooks {

    private static var cache: [String: String] = [:]

    private static var directory: URL? {
        if let res = Bundle.main.resourceURL?
            .appendingPathComponent("playbooks", isDirectory: true),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        // Running straight out of the source tree (swift run) still works.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let local = cwd.appendingPathComponent("playbooks", isDirectory: true)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return nil
    }

    static func load(_ name: String) -> String? {
        if let hit = cache[name] { return hit }
        guard let dir = directory else { return nil }
        let url = dir.appendingPathComponent(name + ".md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        cache[name] = text
        return text
    }

    static func general() -> String {
        load("general") ?? "Call get_app_state before acting. Use element_index values from the latest snapshot."
    }

    static func appKey(name: String, bundleID: String) -> String? {
        let haystack = (name + " " + bundleID).lowercased()
        if haystack.contains("teams") { return "teams" }
        if haystack.contains("chrome") || haystack.contains("chromium") { return "chrome" }
        if haystack.contains("safari") { return "safari" }
        if haystack.contains("textedit") { return "textedit" }
        if haystack.contains("finder") { return "finder" }
        return nil
    }

    static func forApp(name: String, bundleID: String) -> String? {
        guard let key = appKey(name: name, bundleID: bundleID) else { return nil }
        return load(key)
    }

    static func catalog() -> [String] {
        guard let dir = directory else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
    }
}
