import Foundation

/// Quiescence rule: how many consecutive identical samples count as settled.
public enum SettleLogic {

    public static let requiredStableSamples = 3
    public static let pollIntervalMilliseconds = 100
    public static let ceilingSeconds: Double = 2.0
    public static let thinTreeThreshold = 8

    /// True when the newest sample repeats the previous one enough times.
    /// `samples` is the run of signatures observed so far, oldest first.
    public static func isSettled(samples: [UInt64],
                                 required: Int = requiredStableSamples) -> Bool {
        guard required > 1, samples.count >= required else { return false }
        let tail = samples.suffix(required)
        guard let first = tail.first else { return false }
        return tail.allSatisfy { $0 == first }
    }

    /// Screen coordinates are top-left origin; AppKit windows are bottom-left.
    public static func flippedY(pointY: Double, screenMaxY: Double, size: Double) -> Double {
        screenMaxY - pointY - size
    }

    /// A tree too thin to describe the UI should fall back to pixels.
    public static func needsPixelFallback(nodeCount: Int) -> Bool {
        nodeCount < thinTreeThreshold
    }
}
