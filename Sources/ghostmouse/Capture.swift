import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ScreenCaptureKit

/// Window screenshot via ScreenCaptureKit, matching the "Skyshot" idea:
/// one image of the target app's key window, in pixels.
enum Capture {

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    struct Shot {
        let png: Data
        let pixelSize: CGSize
        let windowFrame: CGRect   // points, global (top-left origin)
        let scale: CGFloat        // pixels per point
    }

    enum CaptureError: Error, CustomStringConvertible {
        case noPermission
        case windowNotFound(String)
        case encodeFailed

        var description: String {
            switch self {
            case .noPermission: return "screen recording permission is not granted"
            case .windowNotFound(let s): return "no captureable window for \(s)"
            case .encodeFailed: return "could not encode screenshot as PNG"
            }
        }
    }

    static func captureWindow(pid: pid_t, hintFrame: CGRect?) async throws -> Shot {
        guard hasPermission else { throw CaptureError.noPermission }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
        }

        guard let window = pick(candidates, hintFrame: hintFrame) else {
            throw CaptureError.windowNotFound("pid \(pid)")
        }

        let scale = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = encodePNG(image) else { throw CaptureError.encodeFailed }

        return Shot(png: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    windowFrame: window.frame,
                    scale: scale)
    }


    /// Capture what the user actually sees in a rectangle, including overlay/child
    /// windows. Window-scoped capture misses those, which matters for apps that draw
    /// cards or popovers in separate windows.
    static func captureRegion(frame: CGRect) async throws -> Shot {
        guard hasPermission else { throw CaptureError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
                ?? content.displays.first else {
            throw CaptureError.windowNotFound("display for \(frame)")
        }
        let scale = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0

        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: frame.origin.x - display.frame.origin.x,
                                   y: frame.origin.y - display.frame.origin.y,
                                   width: frame.width,
                                   height: frame.height)
        config.width = Int(frame.width * scale)
        config.height = Int(frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let png = encodePNG(image) else { throw CaptureError.encodeFailed }
        return Shot(png: png,
                    pixelSize: CGSize(width: image.width, height: image.height),
                    windowFrame: frame,
                    scale: scale)
    }

    private static func pick(_ windows: [SCWindow], hintFrame: CGRect?) -> SCWindow? {
        guard !windows.isEmpty else { return nil }
        guard let hint = hintFrame else {
            return windows.max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) })
        }
        let scored = windows.map { w -> (SCWindow, CGFloat) in
            let dx = abs(w.frame.origin.x - hint.origin.x)
            let dy = abs(w.frame.origin.y - hint.origin.y)
            let dw = abs(w.frame.width - hint.width)
            let dh = abs(w.frame.height - hint.height)
            return (w, dx + dy + dw + dh)
        }
        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
