import CoreGraphics
import Foundation

// Every move the strip can make, independent of key bindings and of AppKit.
// The strip wraps by design: earlier versions of PaperWM-style managers clamp at
// the ends, which leaves the first press on the right doing nothing.
public enum SelectorError: Error, Equatable, Sendable {
    case empty, outOfRange, noRoom
}

public enum Direction: String, Codable, Sendable {
    case left, right, up, down
}

public struct Span: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct StripState: Codable, Equatable, Sendable {
    public var columns: [ColumnState]
    public var focused: Int
    /// Column flush at the start of the scrolling span. It is not `focused`:
    /// focus can sit on any visible column without the strip scrolling under it,
    /// which is what keeps a two column desktop showing 0 and 1 instead of
    /// recentring on every key press. Nil means "follow focus".
    public var anchor: Int?
    /// Indices parked at the screen edges, left before right, in strip order.
    public var pinnedLeft: [Int]
    public var pinnedRight: [Int]
    /// Window already cut into the screen edges, so layouts cannot shift them.
    public var pinnedSpan: Span?

    public init(
        columns: [ColumnState] = [],
        focused: Int = 0,
        anchor: Int? = nil,
        pinnedLeft: [Int] = [],
        pinnedRight: [Int] = [],
        pinnedSpan: Span? = nil
    ) {
        self.columns = columns
        self.focused = focused
        self.anchor = anchor
        self.pinnedLeft = pinnedLeft
        self.pinnedRight = pinnedRight
        self.pinnedSpan = pinnedSpan
    }

    public var pinnedCount: Int { pinnedLeft.count + pinnedRight.count }

    /// Columns that actually slide: everything not parked at an edge.
    public var scrolling: [Int] {
        (0..<columns.count).filter { !pinnedLeft.contains($0) && !pinnedRight.contains($0) }
    }

    public func isPinned(_ index: Int) -> Bool { pinnedLeft.contains(index) || pinnedRight.contains(index) }

    // MARK: - Selection

    public mutating func focusNext(_ direction: Direction) throws {
        guard !columns.isEmpty else { throw SelectorError.empty }
        let here = try validatedFocus()
        focused = here

        // No parking here: a key press is navigation, not a request to pin. Parking
        // used to pin a column the moment it was visited, which took it out of the
        // ring and gave it the pinned width on the next layout.
        let step = (direction == .right) ? 1 : -1
        let ring = scrolling
        if ring.contains(focused) {
            focused = ring[mod(ring.firstIndex(of: focused)! + step, ring.count)]
        } else if pinnedLeft.contains(focused) {
            let group = pinnedLeft
            let i = group.firstIndex(of: focused)!
            focused = group.count > 1
                ? group[mod(i + step, group.count)]
                : (ring.first ?? focused)
        } else {
            let group = pinnedRight
            let i = group.firstIndex(of: focused)!
            focused = group.count > 1
                ? group[mod(i + step, group.count)]
                : (ring.last ?? focused)
        }
    }

    public mutating func moveFocused(_ direction: Direction) throws {
        guard !columns.isEmpty else { throw SelectorError.empty }
        let here = try validatedFocus()
        // A pinned column has no neighbours to swap with; it has to be unpinned.
        guard !isPinned(here) else { throw SelectorError.noRoom }
        let ring = scrolling
        guard let offset = ring.firstIndex(of: here) else { throw SelectorError.outOfRange }
        let step = (direction == .right) ? 1 : -1
        let target = ring[mod(offset + step, ring.count)]
        columns.swapAt(here, target)
        focused = target
    }

    /// The anchor is the leftmost visible column. It follows focus one step at a
    /// time so the strip pages instead of recentring: focus at 1 shows 0 and 1,
    /// focus at 2 slides the whole strip to 2 and 3, pushing 0 and 1 off the left.
    /// Moving back before the anchor jumps straight to the focused column.
    /// `span` and `gapPerColumn` are unused; the signature stays for callers.
    public mutating func settleAnchor(span: CGFloat, gapPerColumn: CGFloat) {
        let ring = scrolling
        guard let offset = ring.firstIndex(of: focused) else { return }
        let current = anchor.flatMap { ring.firstIndex(of: $0) } ?? offset
        anchor = ring[offset >= current ? max(current, offset - 1) : max(0, offset - 1)]
    }

    public mutating func focus(index: Int) throws {
        guard !columns.isEmpty else { throw SelectorError.empty }
        guard columns.indices.contains(index) else { throw SelectorError.outOfRange }
        _ = try validatedFocus()
        focused = index
    }

    public mutating func pin(_ direction: Direction, at index: Int? = nil) throws {
        guard !columns.isEmpty else { throw SelectorError.empty }
        let here: Int
        if let index {
            here = index
        } else {
            here = try validatedFocus()
        }
        guard columns.indices.contains(here) else { throw SelectorError.outOfRange }
        unpin(here)
        if direction == .left { pinnedLeft.append(here) } else { pinnedRight.append(here) }
        // Pinning the focused column must not leave focus behind: the neighbour
        // that took its place in the ring becomes the focused column.
        if focused == here { focused = scrolling.first ?? here }
    }

    public mutating func unpin(_ index: Int) {
        pinnedLeft.removeAll { $0 == index }
        pinnedRight.removeAll { $0 == index }
    }

    // MARK: - Size

    public mutating func setRatios(_ ratios: [CGFloat]) {
        for (i, j) in scrolling.enumerated() where ratios.indices.contains(i) {
            columns[j].widthRatio = ratios[i]
        }
    }

    // MARK: - Helpers

    func validatedFocus() throws -> Int {
        columns.indices.contains(focused) ? focused : 0
    }

    func mod(_ value: Int, _ divisor: Int) -> Int {
        let r = value % divisor
        return r < 0 ? r + divisor : r
    }
}
