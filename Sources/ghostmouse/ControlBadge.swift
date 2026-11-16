import AppKit
import Foundation
import GhostMouseCore

/// The "this window is being controlled" badge, plus the Esc-to-cancel escape hatch.
///
/// A small overlay tells the user which window is being driven and offers an escape
/// hatch: pressing Esc cancels the next action.
final class ControlBadge {

    static let shared = ControlBadge()

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private var trackTimer: Timer?
    private var trackedPID: pid_t?
    private var trackedTitle: String = ""
    private(set) var cancelled = false

    private init() {}

    // MARK: - Cancellation

    func startMonitoring() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.keyCode == 53 else { return }   // Esc
            self.cancelled = true
            DispatchQueue.main.async { self.hide() }
        }
    }

    func clearCancel() { cancelled = false }

    var cancelReason: String? {
        cancelled ? "Cancelled by the user (Esc). Nothing further was sent. Call `get_app_state` to resume." : nil
    }

    // MARK: - Badge

    /// Follow the target window so the badge stays glued while the window moves.
    func track(pid: pid_t, appName: String) {
        trackedPID = pid
        trackedTitle = appName
        guard trackTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let pid = self.trackedPID else { return }
            guard let running = NSRunningApplication(processIdentifier: pid) else { return }
            guard let frame = AX.windowFrame(app: running) else { return }
            self.positionBadge(at: frame, appName: self.trackedTitle, active: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer
    }

    func stopTracking() {
        trackTimer?.invalidate()
        trackTimer = nil
        trackedPID = nil
    }

    private func positionBadge(at frame: CGRect, appName: String, active: Bool) {
        guard let win = window else { return }
        let size = win.frame.size
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) ?? NSScreen.main {
            let x = frame.origin.x + 10
            let invertedTop = screen.frame.maxY - frame.origin.y
            let y = invertedTop - size.height - 6
            if win.frame.origin != NSPoint(x: x, y: y) {
                win.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }

    func show(app: String, windowFrame: CGRect?, active: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let title = "GhostMouse is controlling \(app)"
            let subtitle = active ? "Esc to cancel" : "working…"

            let win = self.makeWindowIfNeeded()
            let size = BadgeView.size(for: title, subtitle: subtitle)
            win.setContentSize(size)

            if let frame = windowFrame {
                self.positionBadge(at: frame, appName: app, active: active)
            } else if let screen = NSScreen.main {
                win.setFrameOrigin(NSPoint(x: screen.frame.minX + 24, y: screen.frame.maxY - size.height - 48))
            }

            (win.contentView as? BadgeView)?.configure(title: title, subtitle: subtitle, active: active)
            win.orderFrontRegardless()

            self.hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.window?.orderOut(nil) }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.hideWork?.cancel()
            self?.window?.orderOut(nil)
        }
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let w = window { return w }
        let w = NonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.contentView = BadgeView(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        window = w
        return w
    }
}

private final class BadgeView: NSView {

    private var title: String = ""
    private var subtitle: String = ""
    private var active: Bool = true

    static let accent = NSColor(srgbRed: 0.20, green: 0.61, blue: 1.0, alpha: 0.95)

    private static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let subtitleFont = NSFont.systemFont(ofSize: 10, weight: .regular)

    static func size(for title: String, subtitle: String) -> NSSize {
        let t = (title as NSString).size(withAttributes: [.font: titleFont])
        let s = (subtitle as NSString).size(withAttributes: [.font: subtitleFont])
        let width = max(t.width, s.width) + 24
        return NSSize(width: ceil(width), height: 46)
    }

    func configure(title: String, subtitle: String, active: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.active = active
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
        (active ? BadgeView.accent : NSColor.systemGray.withAlphaComponent(0.9)).setFill()
        path.fill()

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: BadgeView.titleFont,
            .foregroundColor: NSColor.white
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: BadgeView.subtitleFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let inset: CGFloat = 12
        (title as NSString).draw(at: NSPoint(x: inset, y: bounds.height - 24), withAttributes: titleAttrs)
        (subtitle as NSString).draw(at: NSPoint(x: inset, y: 9), withAttributes: subAttrs)
    }
}

/// Overlay panels must never take key focus or activation from the app we are driving.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
