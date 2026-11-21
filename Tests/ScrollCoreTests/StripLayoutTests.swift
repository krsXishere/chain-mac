import XCTest
@testable import ScrollCore

final class StripLayoutTests: XCTestCase {
    let canvas = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let gap = Gaps(top: 10, bottom: 10, left: 10, right: 10)
    let none = Gaps(top: 0, bottom: 0, left: 0, right: 0)

    func testFocusedColumnSitsAtCanvasOrigin() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        let f = StripLayout.frames(columns: cols, focused: 0, canvas: canvas, gaps: none)
        XCTAssertEqual(f[0].minX, 0)
        XCTAssertEqual(f[0].width, 500)
        XCTAssertEqual(f[0].height, 800)
    }

    func testNeighboursOverflowToTheRight() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        let f = StripLayout.frames(columns: cols, focused: 0, canvas: canvas, gaps: none)
        XCTAssertEqual(f[1].minX, 500)
        XCTAssertEqual(f[1].maxX, 1000)
    }

    func testGapNarrowsColumnsAndAddsOneGap() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        let f = StripLayout.frames(columns: cols, focused: 0, canvas: canvas, gaps: gap)
        XCTAssertEqual(f[0].width, 480)
        XCTAssertEqual(f[1].minX, 500)
        XCTAssertEqual(f[1].maxX, 980)
    }

    func testColumnsLeftOfFocusExtendOffScreen() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        let f = StripLayout.frames(columns: cols, focused: 1, canvas: canvas, gaps: none)
        XCTAssertEqual(f[1].minX, 0)
        XCTAssertEqual(f[0].maxX, 0)
    }

    func testScrollOffsetBringsFocusedColumnToOrigin() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        let f = StripLayout.frames(columns: cols, focused: 1, canvas: canvas, gaps: none)
        let offset = StripLayout.scrollOffset(columnFrame: f[1], canvas: canvas)
        XCTAssertEqual(f[1].minX + offset, canvas.minX)
    }

    func testOutOfRangeFocusFallsBackToFirstColumn() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 1)]
        let f = StripLayout.frames(columns: cols, focused: 9, canvas: canvas, gaps: gap)
        XCTAssertEqual(f[0].minX, 10)
    }

    func testColumnsPastTheEdgeKeepTheirPositionOffScreen() {
        // The strip continues past the display instead of being clipped, which is
        // what lets 50% columns sit half off screen while the focused one is on it.
        let half = ColumnState(windowIDs: [], widthRatio: 0.5)
        let f = StripLayout.frames(columns: [half, half, half], focused: 0, canvas: canvas, gaps: gap)
        XCTAssertGreaterThanOrEqual(f[2].minX + f[2].width - 0.5, canvas.maxX)
        XCTAssertEqual(f[2].width, f[0].width, accuracy: 0.001)
    }

    func testEveryColumnGetsANonZeroFrame() {
        let half = ColumnState(windowIDs: [], widthRatio: 0.5)
        let f = StripLayout.frames(columns: [half, half, half, half], focused: 1, canvas: canvas, gaps: gap)
        for frame in f {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
        }
    }

    func testFullStripNeverOverhangsCanvas() {
        let third = ColumnState(windowIDs: [], widthRatio: 1.0 / 3.0)
        let f = StripLayout.frames(columns: [third, third, third], focused: 0, canvas: canvas, gaps: gap)
        XCTAssertLessThanOrEqual(f[2].maxX, canvas.maxX, "strip overhangs right edge")
        XCTAssertEqual(f[1].minX - f[0].maxX, gap.right, accuracy: 0.001)
        XCTAssertEqual(f[2].minX - f[1].maxX, gap.right, accuracy: 0.001)
    }

    func testWiderColumnPushesNeighbourAsideInsteadOfOverlapping() {
        // A 100%-wide focused column pushes the rest off the span: no overlap.
        let full = ColumnState(windowIDs: [], widthRatio: 1)
        let third = ColumnState(windowIDs: [], widthRatio: 1.0 / 3.0)
        let f = StripLayout.frames(columns: [full, third], focused: 0, canvas: canvas, gaps: none)
        XCTAssertEqual(f[0].width, 1000, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(f[1].minX, f[0].maxX, "column 2 overlaps column 1")
        XCTAssertEqual(f[1].minX, 1000, accuracy: 0.001)
    }

    func testOverflowingColumnPushesLaterColumnsRight() {
        // Free Download Manager refuses to shrink past its minimum, so the column
        // after it must start at the real right edge, not the requested one.
        let half = ColumnState(windowIDs: [], widthRatio: 0.5)
        let f = StripLayout.frames(
            columns: [half, half, half],
            focused: 0,
            canvas: canvas,
            gaps: none,
            overflow: [0: 120]
        )
        XCTAssertEqual(f[0].width, 500, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(f[1].minX, 620 - 0.001, "overlap with the wide column")
    }

    func testOverflowLeftOfFocusPushesEarlierColumnsLeft() {
        let half = ColumnState(windowIDs: [], widthRatio: 0.5)
        let f = StripLayout.frames(
            columns: [half, half, half],
            focused: 1,
            canvas: canvas,
            gaps: none,
            overflow: [1: 120]
        )
        XCTAssertEqual(f[1].minX, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(f[0].maxX, 0.001, "column 0 sits under the wide column")
    }

    func testChainFromFocusHasNoOverlapAndKeepsTheGap() {
        let q = ColumnState(windowIDs: [], widthRatio: 0.25)
        let cols = [q, q, q, q]
        let f = StripLayout.frames(columns: cols, focused: 2, canvas: canvas, gaps: gap)
        for i in 0..<3 {
            XCTAssertLessThanOrEqual(f[i].maxX, f[i + 1].minX + 0.001, "overlap at \(i)")
            XCTAssertEqual(f[i + 1].minX - f[i].maxX, gap.right, accuracy: 0.001)
        }
        XCTAssertEqual(f[2].minX, 10, accuracy: 0.001, "focused column not at span start")
    }
    func testOffscreenColumnsStackInsteadOfPilingUp() {
        let w: CGFloat = 500
        let frames = [
            CGRect(x: -1500, y: 0, width: w, height: 800),
            CGRect(x: -1000, y: 0, width: w, height: 800),
            CGRect(x: 0, y: 0, width: w, height: 800),
            CGRect(x: 500, y: 0, width: w, height: 800),
            CGRect(x: 1000, y: 0, width: w, height: 800),
            CGRect(x: 1500, y: 0, width: w, height: 800),
        ]
        let out = StripLayout.stacked(frames: frames, canvas: canvas, peek: 24)
        // Farther left means deeper in the pile: the nearest one peeks least.
        XCTAssertEqual(out[0].minX, -500 + 24)
        XCTAssertEqual(out[1].minX, -500 + 48)
        XCTAssertEqual(out[2].minX, 0)
        XCTAssertEqual(out[3].minX, 500)
        XCTAssertEqual(out[4].minX, 1000 - 24)
        XCTAssertEqual(out[5].minX, 1000 - 48)
    }

    func testStackLeavesVisibleColumnsAlone() {
        let frames = [CGRect(x: 10, y: 0, width: 400, height: 800)]
        let out = StripLayout.stacked(frames: frames, canvas: canvas, peek: 24)
        XCTAssertEqual(out[0].minX, 10)
    }
    func testCenteredColumnSitsInMiddleOfSpan() {
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.3),
                    ColumnState(windowIDs: [2], widthRatio: 0.3),
                    ColumnState(windowIDs: [3], widthRatio: 0.3)]
        let flush = StripLayout.frames(columns: cols, focused: 1, canvas: canvas, gaps: none)
        let centred = StripLayout.frames(columns: cols, focused: 1, canvas: canvas, gaps: none, center: true)
        XCTAssertEqual(flush[1].minX, 0)
        // Three 0.3 columns in a 1000pt span: 300 wide, so the middle one starts at 350.
        XCTAssertEqual(centred[1].minX, 350)
        XCTAssertEqual(centred[1].width, 300)
    }
    func testAnchorKeepsStripStillWhenFocusMovesInsideIt() {
        // Two half-width columns fill the span. Focus on the right one must not
        // scroll: the desktop still shows both, just highlighted differently.
        let cols = [ColumnState(windowIDs: [1], widthRatio: 0.5),
                    ColumnState(windowIDs: [2], widthRatio: 0.5)]
        var state = StripState(columns: cols, focused: 1)
        state.anchor = 0
        let f = StripLayout.frames(state: state, canvas: canvas, gaps: none)
        XCTAssertEqual(f[0].minX, 0)
        XCTAssertEqual(f[1].minX, 500)
    }

    func testAnchorFollowsFocusWhenFocusDoesNotFit() {
        let cols = (0..<3).map { ColumnState(windowIDs: [CGWindowID($0)], widthRatio: 0.5) }
        var state = StripState(columns: cols, focused: 2)
        state.anchor = 2
        let f = StripLayout.frames(state: state, canvas: canvas, gaps: none)
        XCTAssertEqual(f[2].minX, 0)
        XCTAssertEqual(f[1].minX, -500)
    }
}
