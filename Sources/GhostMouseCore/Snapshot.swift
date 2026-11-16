import Foundation

/// A node as it matters to the model: stable path plus a one-line summary.
public struct NodeSummary: Equatable {
    public let index: Int
    public let depth: Int
    public let path: String
    public let summary: String

    public init(index: Int, depth: Int, path: String, summary: String) {
        self.index = index
        self.depth = depth
        self.path = path
        self.summary = summary
    }
}

/// A point-in-time view of one app window. Pure data, so diffing is testable.
public struct Snapshot: Equatable {
    public let app: String
    public let bundleID: String
    public let pid: Int32
    public let windowDescription: String
    public let nodes: [NodeSummary]

    public init(app: String, bundleID: String, pid: Int32, windowDescription: String, nodes: [NodeSummary]) {
        self.app = app
        self.bundleID = bundleID
        self.pid = pid
        self.windowDescription = windowDescription
        self.nodes = nodes
    }

    public var signature: UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for n in nodes {
            for byte in (n.path + "|" + n.summary).utf8 {
                h = (h ^ UInt64(byte)) &* 0x100000001b3
            }
        }
        return h
    }
}

public struct DiffResult {
    public let added: Int
    public let removed: Int
    public let changed: Int
    public let text: String

    public var isEmpty: Bool { added == 0 && removed == 0 && changed == 0 }
}

public enum SnapshotDiff {

    public static let defaultLineLimit = 40

    /// Structural diff keyed by stable path. Bounded so a noisy app cannot flood
    /// the caller with output.
    public static func diff(from previous: Snapshot?,
                            to current: Snapshot,
                            lineLimit: Int = defaultLineLimit) -> DiffResult {
        guard let previous = previous else {
            return DiffResult(added: 0, removed: 0, changed: 0,
                              text: "initial snapshot: \(current.nodes.count) nodes")
        }

        let oldMap = Dictionary(previous.nodes.map { ($0.path, $0.summary) }, uniquingKeysWith: { a, _ in a })
        let newMap = Dictionary(current.nodes.map { ($0.path, $0.summary) }, uniquingKeysWith: { a, _ in a })

        var added: [(String, String)] = []
        var removed: [(String, String)] = []
        var changed: [(String, String, String)] = []

        for (path, summary) in newMap {
            if let old = oldMap[path] {
                if old != summary { changed.append((path, old, summary)) }
            } else {
                added.append((path, summary))
            }
        }
        for (path, summary) in oldMap where newMap[path] == nil {
            removed.append((path, summary))
        }

        var out = "diff: +\(added.count) -\(removed.count) ~\(changed.count)\n"
        var printed = 0
        var truncated = false

        func emit(_ line: String) {
            if printed >= lineLimit { truncated = true; return }
            out += line + "\n"
            printed += 1
        }

        for (_, s) in added.sorted(by: { $0.0 < $1.0 }) { emit("[+] \(s)") }
        for (_, s) in removed.sorted(by: { $0.0 < $1.0 }) { emit("[-] \(s)") }
        for (_, old, new) in changed.sorted(by: { $0.0 < $1.0 }) {
            emit("[~] \(old)")
            emit("    -> \(new)")
        }
        if truncated { out += "…\n" }
        if added.isEmpty && removed.isEmpty && changed.isEmpty { out += "no changes\n" }

        return DiffResult(added: added.count, removed: removed.count, changed: changed.count, text: out)
    }
}
