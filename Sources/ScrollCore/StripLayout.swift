import CoreGraphics

// Gap subtraction lives here and nowhere else. Every inlined `w * r - x` on
// CGFloat in this package has silently yielded 0 under `swift test`, so keep
// the arithmetic in one place that has a direct test.
public func columnWidth(
    usableWidth: CGFloat,
    columns: Int,
    ratio: CGFloat,
    gapPerColumn: CGFloat
) -> CGFloat {
    guard columns > 0, usableWidth > 0, ratio > 0 else { return 0 }
    let share = usableWidth * ratio
    let remainder = share - gapPerColumn
    return remainder < 0 ? 0 : remainder
}

public enum StripLayout {

    static func width(ratio: CGFloat, canvas: CGRect, gaps: Gaps) -> CGFloat {
        let usable = max(0, canvas.width - gaps.left - gaps.right)
        return usable * ratio
    }

    /// Frames for the whole workspace. Pinned columns sit flush at the edges,
    /// full height; the scrolling columns anchor to the left edge of the span
    /// left between them. Columns past the right edge keep their real position
    /// off screen: the strip continues, it is not clipped to the display.
    public static func frames(
        state: StripState,
        canvas: CGRect,
        gaps: Gaps,
        overflow: [Int: CGFloat] = [:],
        center: Bool = false
    ) -> [CGRect] {
        guard !state.columns.isEmpty else { return [] }
        let usableY = canvas.minY + gaps.top
        let usableHeight = max(0, canvas.height - gaps.top - gaps.bottom)
        var frames = state.columns.map { _ in CGRect.zero }

        var leftX = canvas.minX + gaps.left
        for index in state.pinnedLeft {
            let w = width(ratio: state.columns[index].widthRatio, canvas: canvas, gaps: gaps)
            frames[index] = CGRect(x: leftX, y: usableY, width: w, height: usableHeight)
            leftX += w + gaps.right
        }

        var rightX = canvas.maxX - gaps.right
        for index in state.pinnedRight {
            let w = width(ratio: state.columns[index].widthRatio, canvas: canvas, gaps: gaps)
            rightX -= w
            frames[index] = CGRect(x: rightX, y: usableY, width: w, height: usableHeight)
            rightX -= gaps.right
        }

        let ring = state.scrolling
        guard !ring.isEmpty else { return frames }
        let spanStart = leftX
        let spanWidth = max(0, (state.pinnedRight.isEmpty ? canvas.maxX - gaps.right : rightX) - spanStart)

        // The anchor decides where the span starts scrolling; focus only decides
        // which column is highlighted. Falling back to focus keeps the older
        // behaviour for callers that never set an anchor.
        let preferred = state.anchor.flatMap { ring.contains($0) ? $0 : nil }
        let anchor = preferred ?? (ring.contains(state.focused) ? state.focused : ring[0])
        let anchorOffset = ring.firstIndex(of: anchor)!

        // Chaining: a column's x is the sum of the widths of the columns before
        // it, not a fixed pitch. A wider column pushes its right neighbours off
        // the span edge instead of overlapping them.
        // Centering parks the focused column in the middle of the span instead of
        // flush left, so both neighbours stay reachable by eye.
        let anchorWidth = columnWidth(
            usableWidth: spanWidth,
            columns: ring.count,
            ratio: state.columns[anchor].widthRatio,
            gapPerColumn: gaps.right
        )
        let anchorX = center
            ? spanStart + max(0, (spanWidth - anchorWidth) / 2)
            : spanStart
        var xs: [Int: CGFloat] = [anchor: anchorX]
        var x = anchorX
        for offset in stride(from: anchorOffset + 1, to: ring.count, by: 1) {
            let w = columnWidth(
                usableWidth: spanWidth,
                columns: ring.count,
                ratio: state.columns[ring[offset - 1]].widthRatio,
                gapPerColumn: gaps.right
            )
            x += w + gaps.right
            // `overflow` is what a neighbour could not shrink to. Later columns
            // move by that much, so a hard-minimum app never overlaps the column
            // that pushed it.
            if let over = overflow[ring[offset - 1]] { x += over }
            xs[ring[offset]] = x
        }
        x = anchorX
        for offset in stride(from: anchorOffset - 1, through: 0, by: -1) {
            let w = columnWidth(
                usableWidth: spanWidth,
                columns: ring.count,
                ratio: state.columns[ring[offset]].widthRatio,
                gapPerColumn: gaps.right
            )
            x -= w + gaps.right
            // Width is left in place, so overflowing this column pushes the ones
            // further left without the gap double-counting.
            x -= overflow[ring[offset]] ?? 0
            xs[ring[offset]] = x
        }

        for index in ring {
            guard let fx = xs[index] else { continue }
            let w = columnWidth(
                usableWidth: spanWidth,
                columns: ring.count,
                ratio: state.columns[index].widthRatio,
                gapPerColumn: gaps.right
            )
            frames[index] = CGRect(x: fx, y: usableY, width: w, height: usableHeight)
        }
        return frames
    }

    /// macOS refuses to move a window so that nothing of it is on screen, so a
    /// column past either edge sticks at the rim and every off-screen column ends
    /// up on top of the others. Give them a stair instead: each one peeks a little
    /// more than the last, so the stack reads as a card pile rather than a mess.
    /// Returns the frames to write; columns that already fit are left untouched.
    public static func stacked(
        frames: [CGRect],
        canvas: CGRect,
        peek: CGFloat = 24
    ) -> [CGRect] {
        var out = frames
        var left = 0
        var right = 0
        for (index, frame) in frames.enumerated() where frame != .zero {
            if frame.maxX <= canvas.minX {
                out[index].origin.x = canvas.minX - frame.width + peek * CGFloat(left + 1)
                left += 1
            } else if frame.minX >= canvas.maxX {
                out[index].origin.x = canvas.maxX - peek * CGFloat(right + 1)
                right += 1
            }
        }
        return out
    }

    public static func frames(
        columns: [ColumnState],
        focused: Int,
        canvas: CGRect,
        gaps: Gaps,
        overflow: [Int: CGFloat] = [:],
        center: Bool = false
    ) -> [CGRect] {
        frames(
            state: StripState(columns: columns, focused: focused),
            canvas: canvas,
            gaps: gaps,
            overflow: overflow,
            center: center
        )
    }

    public static func scrollOffset(columnFrame: CGRect, canvas: CGRect) -> CGFloat {
        -columnFrame.minX + canvas.minX
    }
}
