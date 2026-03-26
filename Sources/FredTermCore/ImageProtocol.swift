/// Image reference stored in the terminal grid.
/// Supports both Sixel and Kitty image protocols.
public struct TerminalImage: Sendable {
    public var id: UInt32
    public var width: Int
    public var height: Int
    public var data: ImageData
    public var placement: ImagePlacement

    public init(id: UInt32, width: Int, height: Int, data: ImageData, placement: ImagePlacement) {
        self.id = id
        self.width = width
        self.height = height
        self.data = data
        self.placement = placement
    }
}

/// Image data payload.
public enum ImageData: Sendable {
    case rgba(Data)
    case png(Data)
}

/// How an image is placed in the terminal grid.
public struct ImagePlacement: Sendable {
    public var col: Int
    public var row: Int
    public var cellWidth: Int
    public var cellHeight: Int
    public var zIndex: Int32
    public var placementId: UInt32?

    public init(col: Int = 0, row: Int = 0, cellWidth: Int = 1, cellHeight: Int = 1,
                zIndex: Int32 = 0, placementId: UInt32? = nil) {
        self.col = col
        self.row = row
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.zIndex = zIndex
        self.placementId = placementId
    }
}

import Foundation
