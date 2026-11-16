import AppKit
import GhostMouseCore
import Foundation

/// A small overlay dot that shows where an action is landing. Purely visual, never
/// interactive: it ignores mouse events and lives above normal windows for ~1.2 s.
final class VirtualCursor {

    static let shared = VirtualCursor()

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?
    private let size: CGFloat = 26

    private init() {}

    func show(at point: CGPoint, active: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let win = self.makeWindowIfNeeded()
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
            let flippedY = CGFloat(SettleLogic.flippedY(pointY: Double(point.y), screenMaxY: Double(screen.frame.maxY), size: Double(self.size)))
            win.setFrame(NSRect(x: point.x - self.size / 2, y: flippedY, width: self.size, height: self.size),
                         display: true)
            (win.contentView as? CursorDotView)?.active = active
            win.contentView?.needsDisplay = true
            win.orderFrontRegardless()

            self.hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.window?.orderOut(nil)
            }
            self.hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    private func makeWindowIfNeeded() -> NSWindow {
        if let w = window { return w }
        let w = NonActivatingPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered,
                                   defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.contentView = CursorDotView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        window = w
        return w
    }
}

private final class CursorDotView: NSView {
    var active: Bool = true

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let fill = active ? NSColor.systemBlue.withAlphaComponent(0.35) : NSColor.systemGray.withAlphaComponent(0.3)
        let stroke = active ? NSColor.white : NSColor.systemGray

        let path = NSBezierPath(ovalIn: rect)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Centre dot marks the exact landing point.
        let dot = NSRect(x: bounds.midX - 2, y: bounds.midY - 2, width: 4, height: 4)
        stroke.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}
