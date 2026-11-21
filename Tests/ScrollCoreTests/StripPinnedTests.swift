import XCTest
@testable import ScrollCore

// Pin behaviour is what the PRD asks for but nobody has built: columns at the
// screen edges do not scroll, the strip between them anchors, and focus wraps
// instead of stopping at the ends.
final class StripPinnedTests: XCTestCase {
    let canvas = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let gap = Gaps(top: 10, bottom: 10, left: 10, right: 10)

    func state(_ ratios: [CGFloat], focused: Int = 0, widthRatio: CGFloat? = nil) -> StripState {
        StripState(
            columns: ratios.map { ColumnState(windowIDs: [], widthRatio: widthRatio ?? $0) },
            focused: focused
        )
    }

    func testFocusNextKeepsColumnWidthsAndPinsNothing() {
        // Setting a column to full width and then navigating must not reset it or
        // take it out of the ring: width belongs to the column, not to the focus.
        var s = StripState(
            columns: (0..<4).map { _ in ColumnState(windowIDs: [], widthRatio: 0.5) },
            focused: 0
        )
        s.columns[0].widthRatio = 1
        try? s.focusNext(.right)
        XCTAssertEqual(s.focused, 1)
        let w: CGFloat = s.columns[0].widthRatio
        XCTAssertEqual(w, 1, accuracy: 0.001)
        XCTAssertTrue(s.pinnedLeft.isEmpty, "navigation wrongly pinned column 0")
        XCTAssertEqual(s.scrolling, [0, 1, 2, 3])
    }

    func testFocusAtIndexSlidesThatColumnToTheSpanStart() {
        // The app-switcher path: focusing column n by index (not by stepping)
        // must put that column at the span start with its neighbours chained.
        var s = state([0.5, 0.5, 0.5])
        try? s.focus(index: 2)
        let f = StripLayout.frames(state: s, canvas: canvas, gaps: gap)
        XCTAssertEqual(s.focused, 2)
        XCTAssertEqual(f[2].minX, 10, accuracy: 0.001)
        XCTAssertLessThan(f[1].maxX, 10, "column 1 should sit left of the focused one")
    }

    func testPinnedLeftSitsFlushAndDoesNotMoveWithFocus() {
        var s = state([0.25, 0.5, 0.5, 0.5])
        try? s.pin(.left, at: 0)
        let before = StripLayout.frames(state: s, canvas: canvas, gaps: gap)
        s.focused = 2
        let after = StripLayout.frames(state: s, canvas: canvas, gaps: gap)
        XCTAssertEqual(before[0], after[0])
        XCTAssertEqual(before[0].minX, 10)
        XCTAssertEqual(before[0].width, 245) // 980 * 0.25
    }

    func testPinnedRightSitsFlushAtRightEdge() {
        var s = state([0.5, 0.5, 0.25])
        s.focused = 2
        try? s.pin(.right, at: 2)
        let f = StripLayout.frames(state: s, canvas: canvas, gaps: gap)
        XCTAssertEqual(f[2].maxX, 990)
        XCTAssertEqual(f[2].width, 245)
    }

    func testScrollingColumnsNeverCrossAPinnedColumn() {
        var s = state([0.25, 1.0, 1.0, 1.0])
        try? s.pin(.left, at: 0)          // column 0 pinned left
        s.pinnedLeft = [0]
        s.focused = 1
        s.columns[2].widthRatio = 1.0
        let f = StripLayout.frames(state: s, canvas: canvas, gaps: gap)
        XCTAssertEqual(f[0].minX, 10)
        let spanStart: CGFloat = 10 + 245 + 10
        XCTAssertGreaterThanOrEqual(f[1].minX, spanStart)
        // A full width column starting at the span edge fills it: it fits.
        XCTAssertGreaterThan(f[1].width, 0)
    }

    func testFocusWrapsFromFirstToLast() {
        var s = state([0.5, 0.5, 0.5])
        s.focused = 0
        try? s.focusNext(.right)     // park at left edge, step into the strip
        s.focused = s.scrolling.first!
        try? s.focusNext(.left)
        XCTAssertEqual(s.focused, s.scrolling.last)
    }

    func testFocusWrapsFromLastToFirst() {
        var s = state([0.5, 0.5, 0.5])
        s.focused = 2
        try? s.focusNext(.left)      // park at right edge first
        s.focused = s.scrolling.last!
        try? s.focusNext(.right)
        XCTAssertEqual(s.focused, s.scrolling.first)
    }

    func testPinThenUnpinRestoresScrolling() {
        var s = state([0.5, 0.5])
        try? s.pin(.left, at: 0)
        XCTAssertTrue(s.isPinned(0))
        s.unpin(0)
        XCTAssertFalse(s.isPinned(0))
        XCTAssertEqual(s.scrolling, [0, 1])
    }

    func testMoveFocusedRefusesPinnedColumn() {
        var s = state([0.5, 0.5])
        try? s.pin(.left, at: 0)
        s.focused = 0
        XCTAssertThrowsError(try s.moveFocused(.right))
    }

    func testMoveFocusedSwapsInsideTheRing() {
        var s = state([0.5, 0.5, 0.5], focused: 1)
        try? s.moveFocused(.right)
        XCTAssertEqual(s.focused, 2)
        XCTAssertEqual(s.columns[1].windowIDs, [])
    }

    func testSwappingRightScrollsOneColumnAtATime() throws {
        let cols = (0..<4).map { ColumnState(windowIDs: [CGWindowID($0)], widthRatio: 0.5) }
        var state = StripState(columns: cols, focused: 0, anchor: 0)
        try state.focusNext(.right)
        state.settleAnchor(span: 1000, gapPerColumn: 0)
        // Focus is at 1: the screen still shows 0 and 1.
        XCTAssertEqual(state.focused, 1)
        XCTAssertEqual(state.anchor, 0)
        try state.focusNext(.right)
        state.settleAnchor(span: 1000, gapPerColumn: 0)
        // Focus is at 2: the screen slides one page left, 1 and 2 are visible.
        XCTAssertEqual(state.focused, 2)
        XCTAssertEqual(state.anchor, 1)
        try state.focusNext(.left)
        state.settleAnchor(span: 1000, gapPerColumn: 0)
        // Stepping back inside the visible pair must not scroll.
        XCTAssertEqual(state.anchor, 1)
        try state.focusNext(.left)
        state.settleAnchor(span: 1000, gapPerColumn: 0)
        // Focus 0 is before the anchor: page back so both 0 and 1 are visible.
        XCTAssertEqual(state.anchor, 0)
    }
}
