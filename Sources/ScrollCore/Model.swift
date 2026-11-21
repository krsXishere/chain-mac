import CoreGraphics
import Foundation

public enum ColumnMode: String, Codable, Sendable {
    case tiled, stacked, tabbed
}

public struct ColumnState: Codable, Equatable, Sendable {
    public var id: UUID
    public var windowIDs: [CGWindowID]
    public var widthRatio: CGFloat
    public var mode: ColumnMode

    public init(
        id: UUID = UUID(),
        windowIDs: [CGWindowID],
        widthRatio: CGFloat,
        mode: ColumnMode = .tiled
    ) {
        self.id = id
        self.windowIDs = windowIDs
        self.widthRatio = widthRatio
        self.mode = mode
    }
}

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var displayUUID: String
    public var spaceID: UInt64
    public var columns: [ColumnState]
    public var focusedColumn: Int
    public var virtualOrigin: CGFloat

    public init(
        displayUUID: String,
        spaceID: UInt64,
        columns: [ColumnState] = [],
        focusedColumn: Int = 0,
        virtualOrigin: CGFloat = 0
    ) {
        self.displayUUID = displayUUID
        self.spaceID = spaceID
        self.columns = columns
        self.focusedColumn = focusedColumn
        self.virtualOrigin = virtualOrigin
    }
}

public struct Gaps: Equatable, Sendable {
    public var top: CGFloat
    public var bottom: CGFloat
    public var left: CGFloat
    public var right: CGFloat

    public init(top: CGFloat = 8, bottom: CGFloat = 8, left: CGFloat = 8, right: CGFloat = 8) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}
