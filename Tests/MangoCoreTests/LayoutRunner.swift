import CoreGraphics
@testable import Mango

// The tests' description of a layout run: a monitor, its gaps and pertag settings, the tiled
// windows in list order with what mango's layouts read of them, the focus and the one before it.
// LayoutRunner runs mango's layout function (the layouts[] table, through arrange) on a rig.

struct Gaps: Equatable {
    var ih: CGFloat, iv: CGFloat, oh: CGFloat, ov: CGFloat
    static let zero = Gaps(ih: 0, iv: 0, oh: 0, ov: 0)
}

struct LayoutClient {
    var id: ClientID
    var currentFrame: CGRect
    var isfullscreen = false
    var isMaximized = false
    var scrollerProportion: CGFloat?
    var scrollerProportionSingle: CGFloat?
    var masterInnerPer: CGFloat = 0
    var stackInnerPer: CGFloat = 0
    var scrollerStackWeight: CGFloat = 0
    var masterMfactPer: CGFloat = 0
    var gridColPer: CGFloat = 1
    var gridRowPer: CGFloat = 1
    var gridColIdx = 0
    var gridRowIdx = 0
}

struct PertagSettings {
    var nmaster = 1
    var mfact: CGFloat = 0.55
    var scrollerDefaultProportion: CGFloat = 0.9
    var scrollerDefaultProportionSingle: CGFloat = 1.0
    var scrollerIgnoreProportionSingle = true
}

struct LayoutInput {
    var workArea: CGRect
    var monitorFrame: CGRect
    var gaps: Gaps
    var enableGaps = true
    var startDragWindow = false
    var clients: [LayoutClient]
    var focusedID: ClientID?
    var prevFocusedID: ClientID?
    var pertag: PertagSettings
    var config: Config
    var cursor: CGPoint = .zero
}

struct LayoutResult {
    var frames: [ClientID: CGRect] = [:]
}

@MainActor
final class LayoutRunner {
    let kind: LayoutKind
    let rig = EngineRig()
    private var screen: CGRect?

    init(_ kind: LayoutKind) { self.kind = kind }

    var server: MangoServer { rig.server }
    var monitor: Monitor { rig.monitor }

    func arrange(_ input: LayoutInput) -> LayoutResult {
        if screen != input.monitorFrame {
            screen = input.monitorFrame
            server.rebuildMonitors(screens: [Screen(displayID: 1, name: "layout", frame: input.monitorFrame,
                                                    workArea: input.workArea, scale: 1, isMain: true)])
        }
        var cfg = input.config
        cfg.animations = false
        cfg.tabBarHeight = 0   // the layouts' boxes, without the port's tab bar
        server.config = cfg
        server.enableGaps = input.enableGaps
        server.startDragWindow = input.startDragWindow
        (server.system as! FakeWindowSystem).fakePointer = input.cursor
        let m = monitor, tag = getMonCurtag(m)
        m.gappih = Int32(input.gaps.ih); m.gappiv = Int32(input.gaps.iv)
        m.gappoh = Int32(input.gaps.oh); m.gappov = Int32(input.gaps.ov)
        m.pertag.ltidxs[tag] = kind
        m.pertag.nmasters[tag] = Int32(input.pertag.nmaster)
        m.pertag.mfacts[tag] = Float(input.pertag.mfact)
        m.pertag.scrollerDefaultProportion[tag] = Float(input.pertag.scrollerDefaultProportion)
        m.pertag.scrollerDefaultProportionSingle[tag] = Float(input.pertag.scrollerDefaultProportionSingle)
        m.pertag.scrollerIgnoreProportionSingle[tag] = input.pertag.scrollerIgnoreProportionSingle

        var order: [Client] = []
        for lc in input.clients {
            let c = server.clientByIdAll(lc.id) ?? rig.window(lc.id)
            c.tags = 1
            c.geom = lc.currentFrame
            c.isfullscreen = lc.isfullscreen
            c.ismaximizescreen = lc.isMaximized
            c.scrollerProportion = Float(lc.scrollerProportion ?? input.pertag.scrollerDefaultProportion)
            c.scrollerProportionSingle = Float(lc.scrollerProportionSingle ?? 0)
            c.masterInnerPer = lc.masterInnerPer
            c.stackInnerPer = lc.stackInnerPer
            c.scrollerStackProportion = Float(lc.scrollerStackWeight)
            c.masterMfactPer = lc.masterMfactPer > 0 ? lc.masterMfactPer : input.pertag.mfact
            c.gridColPer = Float(lc.gridColPer); c.gridRowPer = Float(lc.gridRowPer)
            c.gridColIdx = Int32(lc.gridColIdx); c.gridRowIdx = Int32(lc.gridRowIdx)
            order.append(c)
        }
        let ids = Set(input.clients.map(\.id))
        for c in server.clientsAll where !ids.contains(c.id) { c.tags = 2 }
        server.clients = order + server.clients.filter { !ids.contains($0.id) }
        if let f = input.focusedID {
            if let c = server.clientByIdAll(f) {
                server.focusStack.removeAll { $0 === c }
                server.focusStack.insert(c, at: 0)
            }
        }
        m.sel = input.focusedID.flatMap { server.clientByIdAll($0) }
        m.prevsel = input.prevFocusedID.flatMap { server.clientByIdAll($0) }
        rig.arrange()
        var out = LayoutResult()
        for lc in input.clients { out.frames[lc.id] = server.clientByIdAll(lc.id)!.geom }
        return out
    }
}

@MainActor
func runLayout(_ kind: LayoutKind, _ input: LayoutInput) -> LayoutResult {
    LayoutRunner(kind).arrange(input)
}

// OverviewRunner runs mango's overview_scale and overview_scale_tab (layout/overview.c) on a rig: the
// clients in list order with their overview_backup_geom sizes, the cards as client_tile_resize puts them.
@MainActor
final class OverviewRunner {
    let rig = EngineRig()
    private var screen: CGRect?

    func cards(_ clients: [(id: ClientID, size: CGSize)], workArea: CGRect, gapInner: CGFloat, gapOuter: CGFloat,
               tab: Bool = false, focused: ClientID? = nil, centerRatio: CGFloat = 0.5) -> [ClientID: CGRect] {
        let server = rig.server
        if screen != workArea {
            screen = workArea
            server.rebuildMonitors(screens: [Screen(displayID: 1, name: "overview", frame: workArea,
                                                    workArea: workArea, scale: 1, isMain: true)])
        }
        server.config.overviewgappi = Int(gapInner)
        server.config.overviewgappo = Int(gapOuter)
        server.config.overcircleCenterRatio = Float(centerRatio)
        server.config.titleMessageBarHeight = 0
        let m = rig.monitor
        var order: [Client] = []
        for item in clients {
            let c = server.clientByIdAll(item.id) ?? rig.window(item.id)
            c.tags = 1
            c.overviewBackupGeom = CGRect(origin: .zero, size: item.size)
            order.append(c)
        }
        let ids = Set(clients.map(\.id))
        for c in server.clientsAll where !ids.contains(c.id) { c.tags = 2 }
        server.clients = order + server.clients.filter { !ids.contains($0.id) }
        m.sel = focused.flatMap { server.clientByIdAll($0) }
        m.isoverview = true
        m.ovThumbnails = true   // the cards only; the windows stay
        m.ovCards = [:]
        if tab { server.overviewScaleTab(m) } else { server.overviewScale(m) }
        let cards = m.ovCards
        m.isoverview = false
        m.ovThumbnails = false
        m.ovCards = [:]
        return cards
    }
}
