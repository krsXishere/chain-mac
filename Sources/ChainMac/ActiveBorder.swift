import AppKit

// A ring drawn around the focused column's window. It is a separate click-through
// panel, not something the app draws, so it works for every app and never takes
// focus or mouse events from the window underneath.
@MainActor
final class ActiveBorder {
    private let panel: NSPanel
    private let view = ActiveBorderView()
    private var lastFrame: CGRect?
    private var lastCanvas: CGRect = .zero
    /// True while Mission Control is up. The ring is a floating panel on every
    /// Space, so it would otherwise be drawn over the zoomed-out desktops.
    private var suppressed = false
    private var watcher: Timer?

    /// Menu-toggleable. Turning it off hides the ring at once.
    var isEnabled = true {
        didSet {
            if isEnabled { update(axFrame: lastFrame, clippedTo: lastCanvas) } else { panel.orderOut(nil) }
        }
    }

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above ordinary windows, below the menu bar and the minimap.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view

        // There is no notification for Mission Control, so it is polled. Twenty
        // checks a second hide the ring before the zoom-out animation shows it.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMissionControl() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    private func checkMissionControl() {
        let active = Self.missionControlActive()
        guard active != suppressed else { return }
        suppressed = active
        update(axFrame: lastFrame, clippedTo: lastCanvas)
    }

    /// While Mission Control is open the Dock owns an extra full-screen window at
    /// layer 18, which is absent in normal use.
    private static func missionControlActive() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first?.processIdentifier,
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let display = CGDisplayBounds(CGMainDisplayID())
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == dock,
                  (info[kCGWindowLayer as String] as? Int) == 18,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) >= display.width,
                  (bounds["Height"] ?? 0) >= display.height
            else { continue }
            return true
        }
        return false
    }

    /// `axFrame` is in AX coordinates (top-left origin, y down), which is what the
    /// controller reads from the window. Nil hides the ring.
    func update(axFrame: CGRect?, clippedTo canvas: CGRect = .zero) {
        lastFrame = axFrame
        lastCanvas = canvas
        guard isEnabled, !suppressed, var frame = axFrame else {
            panel.orderOut(nil)
            return
        }
        // A column partly pushed off the span would otherwise draw its ring
        // outside the screen; keep to what is actually visible.
        if !canvas.isEmpty { frame = frame.intersection(canvas) }
        guard !frame.isNull, frame.width > 8, frame.height > 8 else {
            panel.orderOut(nil)
            return
        }
        let display = CGDisplayBounds(CGMainDisplayID())
        let cocoa = CGRect(
            x: frame.minX,
            y: display.height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
        if panel.frame != cocoa {
            panel.setFrame(cocoa, display: true)
            view.frame = CGRect(origin: .zero, size: cocoa.size)
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

@MainActor
private final class ActiveBorderView: NSView {
    private static let lineWidth: CGFloat = 3
    private static let radius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        // Stroke inside the window's own frame so the ring never spills onto the
        // neighbouring column.
        let rect = bounds.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.radius, yRadius: Self.radius)
        path.lineWidth = Self.lineWidth
        NSColor(srgbRed: 0.95, green: 0.66, blue: 0.22, alpha: 1).setStroke()
        path.stroke()
    }
}
