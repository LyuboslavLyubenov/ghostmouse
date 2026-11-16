import Foundation
import GhostMouseCore
import AppKit
import CoreGraphics

/// Wait until the target app stops changing before taking a snapshot.
///
/// Rule: poll the accessibility tree every 100 ms and stop when three consecutive
/// samples are identical, or when the 2 s ceiling is reached. When the tree is thin
/// (canvas-style apps expose almost nothing), fall back to comparing a downscaled
/// screenshot hash, because the tree cannot tell us anything.
enum Settle {

    static let pollInterval = useconds_t(SettleLogic.pollIntervalMilliseconds * 1000)
    static let stableSamplesNeeded = SettleLogic.requiredStableSamples
    static let ceiling = SettleLogic.ceilingSeconds
    static let thinTreeThreshold = SettleLogic.thinTreeThreshold

    struct Result {
        let tree: AX.Tree
        let credits: Int      // samples matched
        let elapsed: Double
        let mode: String      // "ax" or "pixels"
    }

    static func wait(for app: NSRunningApplication) async -> Result {
        let start = Date()
        var lastSignature: UInt64 = 0
        var stable = 0
        var tree = AX.tree(for: app)

        while Date().timeIntervalSince(start) < ceiling {
            let signature = tree.signature
            if signature == lastSignature {
                stable += 1
            } else {
                stable = 0
                lastSignature = signature
            }
            if stable >= stableSamplesNeeded - 1 {
                return Result(tree: tree, credits: stable + 1, elapsed: Date().timeIntervalSince(start), mode: "ax")
            }
            usleep(pollInterval)
            tree = AX.tree(for: app)
        }

        // Ceiling reached: if the tree is too thin to be meaningful, check pixels.
        if SettleLogic.needsPixelFallback(nodeCount: tree.nodes.count) {
            let first = await pixelHash(app: app)
            usleep(150_000)
            let second = await pixelHash(app: app)
            if let a = first, let b = second, a != b {
                tree = AX.tree(for: app)
                return Result(tree: tree, credits: stable, elapsed: Date().timeIntervalSince(start), mode: "pixels-unstable")
            }
            return Result(tree: tree, credits: stable, elapsed: Date().timeIntervalSince(start), mode: "pixels-stable")
        }

        return Result(tree: tree, credits: stable, elapsed: Date().timeIntervalSince(start), mode: "ax-ceiling")
    }

    /// 32x32 grayscale hash, enough to notice "something moved" without keeping images.
    private static func pixelHash(app: NSRunningApplication) async -> UInt64? {
        guard let shot = try? await Capture.captureWindow(pid: app.processIdentifier, hintFrame: nil) else { return nil }
        return hashPNG(shot.png)
    }

    private static func hashPNG(_ data: Data) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in data {
            h = (h ^ UInt64(byte)) &* 0x100000001b3
            if h == 0 { h = 1 }
        }
        return h
    }

    /// Runs a mutating action, then waits for the UI to settle.
    static func afterAction(_ app: NSRunningApplication) async -> Result {
        return await wait(for: app)
    }
}
