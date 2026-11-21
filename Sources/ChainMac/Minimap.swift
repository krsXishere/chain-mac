import AppKit

// A minimap of the strip: one rectangle per column, sized by width and marked for
// focus. Absolute window positions are useless on a scrolling strip, because most
// columns sit off screen; what the user needs is "where am I" and "how many are
// left", and that is what the map shows.
@MainActor
final class Minimap {
    private let panel: NSPanel
    private let view = MinimapView()
    private var hideTask: DispatchWorkItem?

    fileprivate static let height: CGFloat = 44
    fileprivate static let padding: CGFloat = 10
    fileprivate static let gap: CGFloat = 3
    /// Points per unit of width ratio: a 0.5 column is 23pt wide on the map.
    fileprivate static let unit: CGFloat = 46

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.backgroundColor = NSColor(white: 0.11, alpha: 0.92).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor(white: 1, alpha: 0.14).cgColor
    }

    /// Ratios are relative widths, so a 0.6 column is drawn three times as wide as
    /// a 0.2 one and the map reads like the strip itself.
    func show(ratios: [CGFloat], focused: Int) {
        guard !ratios.isEmpty else { return }
        view.ratios = ratios
        view.focused = focused

        let widths = ratios.map { max(0.05, $0) }
        // Matches MinimapView.draw: the panel is as wide as the bars it draws, so
        // a wide column does not get squeezed by the frame.
        let barWidth = widths.reduce(0, +) * Self.unit
        let size = CGSize(
            width: barWidth + Self.gap * CGFloat(max(0, widths.count - 1)) + Self.padding * 2,
            height: Self.height
        )
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.minY + 80
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        view.frame = CGRect(origin: .zero, size: size)
        view.needsDisplay = true
        panel.orderFrontRegardless()

        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: task)
    }

}

@MainActor
final class MinimapView: NSView {
    var ratios: [CGFloat] = []
    var focused = 0

    override func draw(_ dirtyRect: NSRect) {
        guard !ratios.isEmpty else { return }
        let inset = Minimap.padding
        let gap = Minimap.gap
        let height = bounds.height - inset * 2
        var x = inset
        for (index, ratio) in ratios.enumerated() {
            let width = ratio * Minimap.unit
            let rect = CGRect(x: x, y: inset, width: width, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            if index == focused {
                NSColor(srgbRed: 0.95, green: 0.66, blue: 0.22, alpha: 1).setFill()
            } else {
                NSColor(white: 1, alpha: 0.20).setFill()
            }
            path.fill()
            x += width + gap
        }
    }
}
