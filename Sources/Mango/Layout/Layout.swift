import Foundation
import CoreGraphics

public enum LayoutKind: Int, CaseIterable, Sendable {
    case tile, scroller, grid, monocle, deck, centerTile, rightTile,
         verticalScroller, verticalTile, verticalGrid, verticalDeck, dwindle, fair, verticalFair

    public var name: String {
        switch self {
        case .tile: return "tile"
        case .scroller: return "scroller"
        case .grid: return "grid"
        case .monocle: return "monocle"
        case .deck: return "deck"
        case .centerTile: return "center_tile"
        case .rightTile: return "right_tile"
        case .verticalScroller: return "vertical_scroller"
        case .verticalTile: return "vertical_tile"
        case .verticalGrid: return "vertical_grid"
        case .verticalDeck: return "vertical_deck"
        case .dwindle: return "dwindle"
        case .fair: return "fair"
        case .verticalFair: return "vertical_fair"
        }
    }

    public var symbol: String {
        switch self {
        case .tile: return "T"
        case .scroller: return "S"
        case .grid: return "G"
        case .monocle: return "M"
        case .deck: return "K"
        case .centerTile: return "CT"
        case .rightTile: return "RT"
        case .verticalScroller: return "VS"
        case .verticalTile: return "VT"
        case .verticalGrid: return "VG"
        case .verticalDeck: return "VK"
        case .dwindle: return "DW"
        case .fair: return "F"
        case .verticalFair: return "VF"
        }
    }

    public init?(name: String) {
        guard let k = LayoutKind.allCases.first(where: { $0.name == name }) else { return nil }
        self = k
    }

    public var isScroller: Bool { self == .scroller || self == .verticalScroller }
    /// Not in mango: the port's parking. Layouts where only the focused stack window is
    /// visible (the others are parked, where mango leaves them behind it in the scene).
    public var isMonocleLike: Bool { self == .monocle || self == .deck || self == .verticalDeck }
}
