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
    public var isVertical: Bool {
        switch self {
        case .verticalScroller, .verticalTile, .verticalGrid, .verticalDeck, .verticalFair: return true
        default: return false
        }
    }
    /// Not in mango: the port's parking. Layouts where only the focused stack window is
    /// visible (the others are parked, where mango leaves them behind it in the scene).
    public var isMonocleLike: Bool { self == .monocle || self == .deck || self == .verticalDeck }
}

public struct Gaps: Equatable, Sendable {
    public var ih: CGFloat
    public var iv: CGFloat
    public var oh: CGFloat
    public var ov: CGFloat
    public init(ih: CGFloat, iv: CGFloat, oh: CGFloat, ov: CGFloat) {
        self.ih = ih; self.iv = iv; self.oh = oh; self.ov = ov
    }
    public static let zero = Gaps(ih: 0, iv: 0, oh: 0, ov: 0)
}

public struct LayoutClient: Equatable, Sendable {
    public var id: ClientID
    public var currentFrame: CGRect
    public var isFullscreen: Bool
    public var isMaximized: Bool
    public var scrollerProportion: CGFloat?
    public var scrollerProportionSingle: CGFloat?
    public var masterInnerPer: CGFloat
    public var stackInnerPer: CGFloat
    public var scrollerStackWeight: CGFloat
    public var masterMfactPer: CGFloat
    public var gridColPer: CGFloat
    public var gridRowPer: CGFloat
    public var gridColIdx: Int
    public var gridRowIdx: Int

    public init(id: ClientID, currentFrame: CGRect, isFullscreen: Bool = false, isMaximized: Bool = false,
                scrollerProportion: CGFloat? = nil, scrollerProportionSingle: CGFloat? = nil,
                masterInnerPer: CGFloat = 0, stackInnerPer: CGFloat = 0, scrollerStackWeight: CGFloat = 0,
                masterMfactPer: CGFloat = 0, gridColPer: CGFloat = 1, gridRowPer: CGFloat = 1,
                gridColIdx: Int = 0, gridRowIdx: Int = 0) {
        self.id = id; self.currentFrame = currentFrame; self.isFullscreen = isFullscreen
        self.isMaximized = isMaximized; self.scrollerProportion = scrollerProportion
        self.scrollerProportionSingle = scrollerProportionSingle
        self.masterInnerPer = masterInnerPer; self.stackInnerPer = stackInnerPer
        self.scrollerStackWeight = scrollerStackWeight
        self.masterMfactPer = masterMfactPer; self.gridColPer = gridColPer; self.gridRowPer = gridRowPer
        self.gridColIdx = gridColIdx; self.gridRowIdx = gridRowIdx
    }
}

public struct PertagSettings: Equatable, Sendable {
    public var nmaster: Int
    public var mfact: CGFloat
    public var scrollerDefaultProportion: CGFloat
    public var scrollerDefaultProportionSingle: CGFloat
    public var scrollerIgnoreProportionSingle: Bool
    public init(nmaster: Int = 1, mfact: CGFloat = 0.55, scrollerDefaultProportion: CGFloat = 0.9,
                scrollerDefaultProportionSingle: CGFloat = 1.0, scrollerIgnoreProportionSingle: Bool = true) {
        self.nmaster = nmaster; self.mfact = mfact
        self.scrollerDefaultProportion = scrollerDefaultProportion
        self.scrollerDefaultProportionSingle = scrollerDefaultProportionSingle
        self.scrollerIgnoreProportionSingle = scrollerIgnoreProportionSingle
    }
}

public struct LayoutInput: Sendable {
    public var workArea: CGRect
    public var monitorFrame: CGRect
    public var gaps: Gaps
    public var enableGaps = true
    public var prevFocusedScroll: (tiled: Bool, proportion: CGFloat)?
    public var startDragWindow = false
    public var clients: [LayoutClient]
    public var focusedID: ClientID?
    public var prevFocusedID: ClientID?
    public var pertag: PertagSettings
    public var config: Config
    public var cursor: CGPoint
    public var mfact: CGFloat {
        if let f = clients.first?.masterMfactPer, f > 0 { return f }
        return pertag.mfact
    }
    func smartGapped(_ single: Bool, ih: Bool = true, iv: Bool = true, oh: Bool = true, ov: Bool = true) -> Gaps {
        guard config.smartgaps && single else { return gaps }
        var g = gaps
        if ih { g.ih = 0 }
        if iv { g.iv = 0 }
        if oh { g.oh = 0 }
        if ov { g.ov = 0 }
        return g
    }
    public var fullscreenInView: Set<ClientID> = []

    public init(workArea: CGRect, monitorFrame: CGRect, gaps: Gaps, clients: [LayoutClient],
                focusedID: ClientID?, prevFocusedID: ClientID?, pertag: PertagSettings,
                config: Config, cursor: CGPoint = .zero) {
        self.workArea = workArea; self.monitorFrame = monitorFrame; self.gaps = gaps
        self.clients = clients; self.focusedID = focusedID; self.prevFocusedID = prevFocusedID
        self.pertag = pertag; self.config = config; self.cursor = cursor
    }
}

public struct GridPlace: Equatable, Sendable {
    public var colPer: CGFloat, rowPer: CGFloat
    public var colIdx: Int, rowIdx: Int
    public init(colPer: CGFloat, rowPer: CGFloat, colIdx: Int, rowIdx: Int) {
        self.colPer = colPer; self.rowPer = rowPer; self.colIdx = colIdx; self.rowIdx = rowIdx
    }
}

public struct LayoutResult: Equatable, Sendable {
    public var frames: [ClientID: CGRect]
    /// Not in mango: the port's parking. Clients that should be hidden (monocle/deck
    /// non-focused stack, scroller columns fully off-screen), where mango's scene clips
    /// them. They still have a frame in `frames`.
    public var hidden: Set<ClientID>
    public var gridPlaces: [ClientID: GridPlace] = [:]
    public init(frames: [ClientID: CGRect] = [:], hidden: Set<ClientID> = []) {
        self.frames = frames; self.hidden = hidden
    }
}

public final class TagLayoutState {
    public var scrollerState = ScrollerState()
    public var dwindleRoot = DwindleTree()
    public init() {}
}

package extension LayoutInput {
    /// Not in mango: guards layouts against non-finite numbers.
    func sanitized() -> LayoutInput {
        func finite(_ v: CGFloat) -> Bool { v.isFinite && abs(v) < 1e6 }
        func ok(_ c: LayoutClient) -> Bool {
            finite(c.masterInnerPer) && finite(c.stackInnerPer) && finite(c.scrollerStackWeight)
                && (c.scrollerProportion.map(finite) ?? true)
                && (c.scrollerProportionSingle.map(finite) ?? true)
                && finite(c.currentFrame.minX) && finite(c.currentFrame.minY)
                && finite(c.currentFrame.width) && finite(c.currentFrame.height)
        }
        let pertagOK = finite(pertag.mfact) && finite(pertag.scrollerDefaultProportion)
            && finite(pertag.scrollerDefaultProportionSingle)
        if pertagOK && clients.allSatisfy(ok) { return self }

        var out = self
        if !finite(pertag.mfact) { out.pertag.mfact = 0.55 }
        if !finite(pertag.scrollerDefaultProportion) { out.pertag.scrollerDefaultProportion = 0.9 }
        if !finite(pertag.scrollerDefaultProportionSingle) { out.pertag.scrollerDefaultProportionSingle = 1 }
        out.clients = clients.map { c in
            var c = c
            if !finite(c.masterInnerPer) { c.masterInnerPer = 0 }
            if !finite(c.stackInnerPer) { c.stackInnerPer = 0 }
            if !finite(c.scrollerStackWeight) { c.scrollerStackWeight = 0 }
            if let p = c.scrollerProportion, !finite(p) { c.scrollerProportion = nil }
            if let p = c.scrollerProportionSingle, !finite(p) { c.scrollerProportionSingle = nil }
            let f = c.currentFrame
            if !(finite(f.minX) && finite(f.minY) && finite(f.width) && finite(f.height)) { c.currentFrame = .zero }
            return c
        }
        return out
    }
}

public enum LayoutEngine {
    public static func arrange(_ kind: LayoutKind, input rawInput: LayoutInput, state: TagLayoutState) -> LayoutResult {
        let input = rawInput.sanitized()
        switch kind {
        case .tile: return TileLayouts.tile(input)
        case .rightTile: return TileLayouts.rightTile(input)
        case .centerTile: return TileLayouts.centerTile(input)
        case .verticalTile: return TileLayouts.verticalTile(input)
        case .deck: return TileLayouts.deck(input)
        case .verticalDeck: return TileLayouts.verticalDeck(input)
        case .monocle: return TileLayouts.monocle(input)
        case .grid: return GridLayouts.grid(input)
        case .verticalGrid: return GridLayouts.verticalGrid(input)
        case .fair: return GridLayouts.fair(input)
        case .verticalFair: return GridLayouts.verticalFair(input)
        case .dwindle:
            var tiled = input
            tiled.clients = input.clients.filter { !$0.isFullscreen && !$0.isMaximized }
            return state.dwindleRoot.dwindleCore(tiled)
        case .scroller: return state.scrollerState.arrange(input, vertical: false)
        case .verticalScroller: return state.scrollerState.arrange(input, vertical: true)
        }
    }
}
