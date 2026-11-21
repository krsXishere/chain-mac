import AppKit
import ScrollCore

// Owns the live workspace: which windows are on the strip, where focus is, and
// how the strip is drawn. Hotkeys, the menu and later the minimap all funnel
// through `perform`, so there is exactly one place where state mutates.
@MainActor
final class StripController {
    private(set) var state = StripState()
    /// One entry per column. Column order is app order, so the strip lays out per
    /// app rather than per window.
    private var columns: [[AXWindowHandle]] = []

    /// The window a column is showing.
    private func window(at index: Int) -> AXWindowHandle? {
        guard columns.indices.contains(index) else { return nil }
        let rows = columns[index]
        guard !rows.isEmpty else { return nil }
        return rows[0]
    }

    var windowCount: Int { columns.count }
    private var presets = Presets.defaultWidths
    var gaps = Gaps()
    /// Menu-toggleable: some apps stutter under a 120Hz position stream, and the
    /// user should be able to turn that off without rebuilding.
    var isAnimated = true
    private var canvas: CGRect = .zero
    /// How much wider a column really is than its frame, because the app enforces
    /// a minimum size. Neighbours shift by this, otherwise the real window would
    /// lie on top of them.
    private var overflow: [Int: CGFloat] = [:]

    /// Where each window is heading. Sliding is done on one axis only: a window is
    /// always at its final width, so interpolating x alone never fights an app's
    /// minimum size and never makes a column shrink on the way.
    private var targetX: [Int: CGFloat] = [:]
    private var slideTimer: Timer?
    private var slideFrames = 0
    // Centering is a mode, not a one-shot: the focused column stays in the middle
    // of the span until it is turned off again.
    private var isCentered = false
    // Columns the OS refuses to move. Remembered so every later slide does not
    // spend frames discovering the same thing.
    private var stuck: [Int] = []
    /// Last few moves, surfaced by Diagnostics. Guessing which of hotkey, layout or
    // AX is at fault from a screen recording wastes a build every time.
    private(set) var trace: [String] = []

    // Log to a file as well as to the menu. A screen recording cannot show whether
    // the slide timer ran, and asking for a screenshot of an alert every time is
    // three round trips per bug. Tail this file instead.
    private static let logURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/ChainMac.log")

    private func note(_ line: String) {
        trace.append(line)
        if trace.count > 60 { trace.removeFirst() }
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: Self.logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: Self.logURL)
        }
    }

    var onChange: (() -> Void)?
    /// Called after every mutation with the widths and focus to draw on the
    /// minimap. Nil until the UI wires one up.
    var onMinimap: (([CGFloat], Int) -> Void)?

    private func publishMinimap() {
        guard let onMinimap, !state.columns.isEmpty else { return }
        onMinimap(state.columns.map { $0.widthRatio }, state.focused)
    }

    /// Adopt the tiled windows of every running app as the current strip.
    /// Every column starts at the default preset: a window keeps the width it is
    /// given, so dividing the screen by the window count is exactly the grid
    /// behaviour the strip exists to avoid.
    @discardableResult
    func refresh() -> Int {
        adopt(AXBridge.tiledWindows(), widths: [:], fallbackRatio: state.columns.first?.widthRatio)
        layout(animated: false)
        publishMinimap()
        onChange?()
        return columns.count
    }

    /// Rebuilds the columns from a flat window list, one column per app. Widths are
    /// keyed by the column's first window so a window keeps the width it was given
    /// across a refresh or a Space switch; anything unseen falls back to the
    /// preset. Dividing the screen by the window count would be exactly the grid
    /// behaviour the strip exists to avoid.
    private func adopt(
        _ found: [AXWindowHandle],
        widths: [String: CGFloat],
        fallbackRatio: CGFloat?
    ) {
        columns = found.map { [$0] }

        let fallback = fallbackRatio ?? (presets.count > 2 ? presets[2] : 0.5)
        state.columns = columns.map { rows in
            let key = rows.first.map { Self.widthKey($0) } ?? ""
            return ColumnState(
                windowIDs: rows.map { $0.windowID },
                widthRatio: widths[key] ?? fallback
            )
        }
        state.pinnedLeft = []
        state.pinnedRight = []
        state.anchor = 0
        state.pinnedSpan = nil
        state.focused = min(state.focused, max(0, columns.count - 1))
    }

    /// Widths belong to a window, not to a position, so they survive a rebuild.
    private static func widthKey(_ window: AXWindowHandle) -> String {
        "\(window.pid)\(window.windowID)"
    }

    /// A Space switch changes which windows exist without changing the strip, so
    /// only the membership is rebuilt: same app, same width.
    func syncToCurrentSpace() {
        let found = AXBridge.tiledWindows()
        // Compare as sets: AX does not promise a stable order between two calls, so
        // an order-only difference used to rebuild the strip (and reset the anchor)
        // on every single key press.
        let before = Set(columns.flatMap { $0 }.map { Self.widthKey($0) })
        let after = Set(found.map { Self.widthKey($0) })
        guard before != after else { return }
        note("space sync: \(before.count) -> \(after.count) windows")
        var widths: [String: CGFloat] = [:]
        for (index, rows) in columns.enumerated()
        where state.columns.indices.contains(index) && !rows.isEmpty {
            widths[Self.widthKey(rows[0])] = state.columns[index].widthRatio
        }
        canvas = Self.canvas(for: NSScreen.main)
        adopt(found, widths: widths, fallbackRatio: state.columns.first?.widthRatio)
        overflow = [:]
        layout(animated: false)
        publishMinimap()
        onChange?()
    }

    func perform(_ action: StripAction) {
        note("perform \(action.rawValue) empty=\(columns.isEmpty)")
        guard !columns.isEmpty else { return }
        switch action {
        case .focusLeft: try? state.focusNext(.left)
        case .focusRight: try? state.focusNext(.right)
        case .focusUp: try? state.focusNext(.left)
        case .focusDown: try? state.focusNext(.right)
        case .focusFirst: try? state.focus(index: 0)
        case .focusLast: try? state.focus(index: max(0, columns.count - 1))
        case .moveLeft: try? state.moveFocused(.left)
        case .moveRight: try? state.moveFocused(.right)
        case .moveUp: try? state.focusNext(.left)
        case .moveDown: try? state.focusNext(.right)
        case .cycleWidth:
            Presets.cycle(&state, presets: presets, fits: fits)
        case .fullWidth:
            setRatio(1)
        case .wider:
            grow(by: 0.05)
        case .narrower:
            grow(by: -0.05)
        case .center:
            isCentered.toggle()
        case .taller, .shorter, .equalHeights,
             .stackLeft, .stackRight, .unstackLeft, .unstackRight,
             .toggleTabs, .unfloat:
            // Not wired yet: no silent no-op elsewhere in this switch, so each
            // one becomes a real branch when its layout lands.
            break
        case .float:
            // Floating needs a per-app rule table; until then the key is inert
            // rather than pretending to have done something.
            break
        case .pinLeft:
            try? state.pin(.left)
        case .pinRight:
            try? state.pin(.right)
        case .nextDisplay:
            break
        case .quit:
            NSApplication.shared.terminate(nil)
        }
        state.settleAnchor(
            span: canvas.width - gaps.left - gaps.right,
            gapPerColumn: gaps.right
        )
        // Anchor is the only thing that decides whether the strip pages, so print
        // it on every action: a stuck strip is otherwise indistinguishable from a
        // correct one in the log.
        note("settle \(action) anchor=\(String(describing: state.anchor)) focus=\(state.focused)")
        layout(animated: true)
        // Moving focus has to move the app too: sliding a window into view without
        // raising it leaves the previous app holding the keyboard, so the visible
        // column and the focused column disagree.
        if action.isNavigating {
            activateFocused()
        }
        publishMinimap()
        onChange?()
    }

    private func activateFocused() {
        // No kAXRaiseAction here. Raising the window pulls every other window of
        // that app above its neighbours on screen, which is what makes the columns
        // left of the focused one flash over the strip. Activating the app alone is
        // enough for the keyboard and the menu bar.
        guard let window = window(at: state.focused) else { return }
        window.activateApp()
    }

    /// Cmd+Tab is not a hotkey we can intercept, so the strip follows the app
    /// macOS gives focus to instead. Only the frontmost window is moved: the
    /// strip itself stays where it is, so the app slides into view rather than
    /// being re-tiled.
    func followFrontmost() {
        guard !columns.isEmpty,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        guard let index = columns.firstIndex(where: { $0.contains { $0.pid == app.processIdentifier } }),
              index != state.focused
        else { return }
        try? state.focus(index: index)
        layout(animated: true)
        onChange?()
    }

    private func grow(by delta: CGFloat) {
        let ring = state.scrolling
        let index = ring.contains(state.focused) ? state.focused : (ring.first ?? 0)
        guard columns.indices.contains(index) else { return }
        setRatio(state.columns[index].widthRatio + delta)
    }

    /// Width belongs to the column, not to the focus: it has to survive focus
    /// moves, otherwise every navigation would silently reset what the user set.
    private func setRatio(_ ratio: CGFloat) {
        let ring = state.scrolling
        let index = ring.contains(state.focused) ? state.focused : (ring.first ?? 0)
        guard columns.indices.contains(index) else { return }
        let clamped = min(1, max(0.1, ratio))
        guard fits(clamped) else { return }
        state.columns[index].widthRatio = clamped
    }

    /// A ratio cannot exceed the scrolling span, otherwise the column would run
    /// under a pinned one.
    private func fits(_ ratio: CGFloat) -> Bool {
        let span = canvas.width - gaps.left - gaps.right
        let usable = span * ratio - gaps.right
        return usable > 40
    }

    func layout(animated: Bool) {
        guard !columns.isEmpty else { return }
        canvas = Self.canvas(for: NSScreen.main)
        let frames = StripLayout.frames(
            state: state,
            canvas: canvas,
            gaps: gaps,
            overflow: overflow,
            center: isCentered
        )
        note("layout animated=\(animated) focused=\(state.focused) count=\(columns.count)")
        let placed = StripLayout.stacked(frames: frames, canvas: canvas)
        var next: [Int: CGFloat] = [:]
        var targets: [Int: CGFloat] = [:]
        // One rectangle per column, one window per column: an app's extra windows
        // are not on the strip.
        for (index, frame) in placed.enumerated() where frame != .zero {
            guard let handle = window(at: index) else { continue }
            let err = handle.setSize(frame.size)
            if err != .success {
                note("  size[\(index)] -> \(err.rawValue) want=\(Int(frame.width))")
            }
        }
        // Pass 2: measure, then record x. AX writes are asynchronous: reading a
        // window's width right after setSize returns the old value, which used to
        // register a phantom overflow and push every column to its right off by
        // the same amount. So only the still (non-animated) pass measures, where
        // the previous write has already landed.
        if !animated {
            for (index, frame) in frames.enumerated() where frame != .zero {
                guard let window = window(at: index) else { continue }
                let actual = window.currentFrame()?.width ?? frame.width
                if actual > frame.width + 2 {
                    next[index] = actual - frame.width
                }
            }
        }
        for (index, frame) in frames.enumerated() where frame != .zero {
            targets[index] = placed[index].origin.x
            if !animated {
                placeColumn(index, at: placed[index])
            }
        }
        let grew = next != overflow
        overflow = next
        // Check the chained x values against the widths that were actually asked
        // for, plus whatever a column refused to give up. Comparing against the
        // requested width instead would flag a correct chain as broken.
        if let first = targets.keys.min(), let last = targets.keys.max() {
            var audit: [String] = []
            for i in stride(from: first, to: last, by: 1) {
                guard let a = targets[i], let b = targets[i + 1] else { continue }
                let realWidth = frames[i].width + (next[i] ?? 0)
                let want = realWidth + gaps.right
                let got = b - a
                // Stacked columns are deliberately not w + gap apart.
                let offscreen = placed[i].minX != frames[i].minX || placed[i + 1].minX != frames[i + 1].minX
                if !offscreen && abs(got - want) > 1 {
                    audit.append("[\(i)/\(i + 1)] got=\(Int(got)) want=\(Int(want)) real=\(Int(realWidth)) over=\(Int(next[i] ?? 0))")
                }
            }
            if !audit.isEmpty {
                note("  AUDIT " + audit.joined(separator: " "))
            }
        }
        // A column that refused to shrink moved its neighbours, so lay out once
        // more against the measured widths. `overflow` is already updated, so the
        // second pass cannot recurse.
        if grew {
            let shifted = StripLayout.frames(
                state: state,
                canvas: canvas,
                gaps: gaps,
                overflow: next,
                center: isCentered
            )
            for (index, frame) in shifted.enumerated() where frame != .zero {
                let stacked = StripLayout.stacked(frames: shifted, canvas: canvas)
                targets[index] = stacked[index].origin.x
                if !animated {
                    placeColumn(index, at: stacked[index])
                }
            }
        }
        targetX = targets
        for (index, x) in targets.sorted(by: { $0.key < $1.key }) {
            guard let window = window(at: index) else { continue }
            let actual = window.currentFrame()
            note("  [\(index)] pid=\(window.pid) t=\(window.title.prefix(14)) rows=\(columns[index].count) target=\(Int(x)) now=\(Int(actual?.minX ?? -1)) w=\(Int(actual?.width ?? -1)) over=\(Int(next[index] ?? 0))")
        }
        // macOS refuses to park a window fully off screen, so a column asked for
        // -800 sticks at the rim while the column on top covers it. Send it to the
        // stair from `stacked` instead, which is inside the canvas by design, and
        // let the slide carry it there.
        let edges = StripLayout.stacked(frames: frames, canvas: canvas)
        let onScreen = canvas.minX..<canvas.maxX
        for (index, x) in targets where !onScreen.contains(x) {
            targets[index] = edges[index].origin.x
        }
        // When sliding, the position is left to the timer. Writing it here as well
        // would move the windows in one frame and make the whole slide a no-op.
        if animated && isAnimated {
            startSliding()
        } else {
            stopSliding()
            for (index, x) in targets {
                placeColumn(index, at: CGRect(x: x, y: canvas.minY, width: frames[index].width, height: frames[index].height))
            }
        }
    }

    /// Writes the app's window. Extra windows of the same app are not on the strip.
    private func placeColumn(_ index: Int, at frame: CGRect) {
        window(at: index)?.setPosition(frame.origin)
    }

    // MARK: - Sliding

    private func startSliding() {
        if let existing = slideTimer {
            note("slide start skipped: timer alive valid=\(existing.isValid) frames=\(slideFrames)")
            return
        }
        note("slide start frames=0 targets=\(targetX.count) canvas=\(String(describing: canvas))")
        slideFrames = 0
        stuck.removeAll()
        // A Timer, not CADisplayLink: CADisplayLink needs macOS 14 and sub-pixel
        // positions do not need VSync. 120Hz keeps the slide smooth on ProMotion.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.slideStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        slideTimer = timer
    }

    private func stopSliding() {
        if slideTimer != nil { note("slide stop frames=\(slideFrames)") }
        slideTimer?.invalidate()
        slideTimer = nil
    }

    /// Exponential ease towards the target x. Positions are read back from the app
    /// rather than cached, so a window that ignored a move is picked up next frame
    /// instead of drifting.
    private func slideStep() {
        var pending = false
        var gone = false
        var frame: [String] = []
        for (index, target) in targetX.sorted(by: { $0.key < $1.key }) where columns.indices.contains(index) && !stuck.contains(index) {
            guard let window = window(at: index) else {
                // A window that closed or went away would otherwise keep the timer
                // alive forever, blocked at a target it can never reach.
                frame.append("\(index):noframe")
                gone = true
                continue
            }
            guard let current = window.currentFrame() else {
                frame.append("\(index):noframe")
                gone = true
                continue
            }
            let delta = target - current.minX
            if abs(delta) < 1.5 {
                if abs(delta) > 0.5 { _ = window.setPosition(CGPoint(x: target, y: current.minY)) }
                frame.append("\(index):done")
                continue
            }
            pending = true
            // Ease, but land on a whole point. AX rounds fractional positions, so
            // an unrounded ease parks a pixel short of the target and never
            // arrives; rounding keeps the motion smooth and the endpoint exact.
            let eased = current.minX + delta * 0.22
            let wanted = abs(eased - target) < 2 ? target : eased.rounded()
            var err = window.setPosition(CGPoint(x: wanted, y: current.minY))
            var after = window.currentFrame()?.minX ?? -9999
            // Some apps accept the write and ignore it when the window would leave
            // the display on the right. Re-asserting sizes then the position once
            // is the difference between "moved" and "stuck" for those windows.
            if abs(after - wanted) > 1 {
                _ = window.setSize(current.size)
                err = window.setPosition(CGPoint(x: wanted, y: current.minY))
                let retried = window.currentFrame()?.minX ?? -9999
                if abs(retried - current.minX) < 0.5 {
                    // The app will not move at all: stop asking rather than burn
                    // a timer frame on it for the rest of the session.
                    stuck.append(index)
                    frame.append("\(index):stuck")
                    continue
                }
                after = retried
            }
            frame.append("\(index):\(current.minX)>w\(wanted)/g\(after)/e\(err.rawValue)")
        }
        slideFrames += 1
        // The first frame and every 20th after it: enough to see whether the app
        // accepts the write, without filling the file at 120Hz.
        if slideFrames <= 3 || slideFrames % 20 == 0 {
            note("  slide#\(slideFrames) pending=\(pending) " + frame.joined(separator: " "))
        }
        if !pending {
            note("  slide end after \(slideFrames) frames")
            stopSliding()
        } else if gone && slideFrames > 30 {
            // Stale window: give up instead of spinning at 120Hz.
            note("  slide aborted after \(slideFrames) frames (window gone)")
            stopSliding()
        }
    }

    /// Canvas in AX coordinates: top-left origin, y down, Dock and menu bar
    /// excluded. NSScreen reports bottom-left origin in Cocoa space, so the y of
    /// the visible frame has to be flipped against the display height.
    static func canvas(for screen: NSScreen?) -> CGRect {
        guard let screen else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        let docked = screen.visibleFrame
        let display = CGDisplayBounds(
            CGMainDisplayID()
        )
        return CGRect(
            x: docked.minX,
            y: display.height - docked.maxY,
            width: docked.width,
            height: docked.height
        )
    }
}
