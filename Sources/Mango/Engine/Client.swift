import Foundation
import CoreGraphics

@MainActor
public protocol PlatformWindow: AnyObject {
    var frame: CGRect { get set }
    var parked: Bool { get set }
    var isFloatType: Bool { get }   // not in mango: wlroots' side of client_is_float_type
    var sceneNodeEnabled: Bool { get }   // not in mango: wlroots' c->scene->node.enabled
    var sceneSurfaceEnabled: Bool { get }   // not in mango: wlroots' c->scene_surface->node.enabled
}

@MainActor
public final class Client {
    public let id: ClientID
    public let pid: pid_t
    public let platform: PlatformWindow
    public let bundleId: String
    public let appName: String
    public var title: String
    public weak var mon: Monitor?
    public var tags: UInt32

    public var isfloating = false
    public var isfullscreen = false
    public var isfakefullscreen = false
    public var ismaximizescreen = false
    public var isglobal = false
    public var isunglobal = false
    public var ignoreMinimize = true
    public var isoverlay = false
    public var isInScratchpad = false
    public var oldtags: UInt32 = 0
    public var isminimized = false
    public var isnamedscratchpad = false
    public var iscustomsize = false
    public var iscustompos = false
    public var isopensilent = false
    public var istagsilent = false
    public var isurgent = false
    public var iskilling = false

    // not in mango: the display ID, not the output's name (two displays can share a name).
    public var oldmonname: CGDirectDisplayID?

    package var frame: CGRect {
        get { platform.frame }
        set { platform.frame = newValue }
    }
    package var parked: Bool {
        get { platform.parked }
        set { platform.parked = newValue }
    }
    public var masterMfactPer: CGFloat = 0
    public var gridColPer: CGFloat = 1
    public var gridRowPer: CGFloat = 1
    public var gridColIdx = 0
    public var gridRowIdx = 0
    public var isTabFocus = false
    public var isTabHidden = false
    public weak var tabPrev: Client?
    public var tabNext: Client?
    var tabBarEnabled = false   // not in mango: c->tab_bar->scene->node.enabled
    public var groupPrev: Client?
    public var groupNext: Client?
    public var isGroupFocus = false
    public var groupParked = false
    public var isGroupMember: Bool { groupPrev != nil || groupNext != nil }

    public var noBorder = false
    public var noAnimation = false
    public var noSizeHint = false
    public var noForceCenter = false
    public var noFocus = false
    public var confinePointer = false
    public var animationTypeOpen: AnimationType?
    public var scrollerProportion: Float = 0
    public var scrollerProportionSingle: Float = 0
    public var iscustomScrollerProportion = false
    public var iscustomScrollerProportionSingle = false
    public var masterSizeWeight: CGFloat = 0
    public var stackSizeWeight: CGFloat = 0
    public var masterInnerPer: CGFloat = 0
    public var stackInnerPer: CGFloat = 0
    public var ismaster = false
    public var isleftstack = false
    public var scrollerStackProportion: Float = 0
    public var scrollerOldStackProportion: Float = 0
    package var dropDirection: Int32 = UP
    package var dragToTile = false
    package var dragTileFloatBackupGeom: CGRect = .zero
    package var enableDropAreaDraw = false
    var dropareaEnabled = false   // not in mango: c->droparea's node.enabled (the port draws the area)
    var oldMasterMfactPer: CGFloat = 0
    var oldMasterInnerPer: CGFloat = 0
    var oldStackInnerPer: CGFloat = 0
    var oldScrollerPproportion: Double = 0
    var oldGridColPer: CGFloat = 0
    var oldGridRowPer: CGFloat = 0
    var cursorInUpperHalf = false
    var cursorInLeftHalf = false
    var dragBeginGeom: CGRect = .zero

    public var floatGeom: CGRect
    public var geom: CGRect
    public var pending: CGRect
    public var current: CGRect
    public var animainitGeom: CGRect
    public var bw: CGFloat = 0
    public var dirty = false
    public var configureSerial: UInt32 = 0
    public var isPendingOpenAnimation = true
    public var needOutputFlush = false
    public var animation = MangoAnimation()
    public var isfloatingBeforeScratchpad = false
    public var isClipToHide = false
    public var scratchpadSwitchingMon = false
    public var scratchpadTagin = false
    public var fakeNoBorder = false
    public var tagVisible = false
    public var isSurfaceHidden = false
    public var overviewBackupGeom: CGRect = .zero
    public var overviewBackedUp = false   // not in mango: overview_backup ran (a mango bug, docs/afvigelser.md §6)
    public var overviewBackupBw: CGFloat = 0
    public var overviewIsfloatingbak = false
    public var overviewIsfullscreenbak = false
    public var overviewIsmaximizescreenbak = false
    public var isRestoringFromOv = false
    public var jumpChar: Character?
    public var jumpKeycodes = MultiKeycode()
    package var jumpLabelNode: MangoJumpLabel?

    package init(id: ClientID, pid: pid_t, platform: PlatformWindow, bundleId: String, appName: String, title: String,
         monitor: Monitor, tags: UInt32, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.platform = platform
        self.bundleId = bundleId
        self.appName = appName
        self.title = title
        self.mon = monitor
        self.tags = tags
        floatGeom = frame
        // not in mango: the window's frame as the port finds it; handle_client_map's border comes with the first resize
        geom = frame
        pending = frame
        current = frame
        animainitGeom = frame
        animation.current = frame
        animation.initial = frame
    }


    public var appid: String { bundleId.isEmpty ? appName : bundleId }

    public func isVisible(on m: Monitor) -> Bool {
        guard mon === m, !groupParked, !isminimized else { return false }
        if isglobal || isunglobal { return true }
        return tags & m.tagset[m.seltags] != 0
    }
}

/// not in mango: C's fixed per-tag arrays (PERTAG_SLOTS), indexed by mango's uint32_t tag.
public struct PertagSlots<Element>: Sequence {
    var a: [Element]
    init(_ value: @autoclosure () -> Element) { a = (0..<Int(PERTAG_SLOTS)).map { _ in value() } }
    public subscript(i: UInt32) -> Element {
        get { a[Int(i)] }
        set { a[Int(i)] = newValue }
    }
    public subscript(i: Int) -> Element {
        get { a[i] }
        set { a[i] = newValue }
    }
    public func makeIterator() -> IndexingIterator<[Element]> { a.makeIterator() }
}

public let tag_num_MAX: UInt32 = 31
public let PERTAG_SLOTS: UInt32 = tag_num_MAX + 1

@MainActor
public final class Pertag {
    public var curtag: UInt32 = 0, prevtag: UInt32 = 0
    public var nmasters = PertagSlots<Int32>(0)
    public var mfacts = PertagSlots<Float>(0)
    public var noHide = PertagSlots<Bool>(false)
    public var noRenderBorder = PertagSlots<Bool>(false)
    public var openAsFloating = PertagSlots<Bool>(false)
    public var scrollerDefaultProportion = PertagSlots<Float>(0)
    public var scrollerDefaultProportionSingle = PertagSlots<Float>(0)
    public var scrollerIgnoreProportionSingle = PertagSlots<Bool>(false)
    package var dwindleRoot = PertagSlots<DwindleNode?>(nil)
    public var configLtidxs = PertagSlots<LayoutKind>(.tile)
    public var ltidxs = PertagSlots<LayoutKind>(.tile)
    package var scrollerState = PertagSlots<TagScrollerState?>(nil)
}

@MainActor
public final class Monitor {
    public var screen: Screen
    public var m: CGRect      /* monitor area, layout-relative */
    public var w: CGRect      /* window area, layout-relative */
    public var seltags = 0
    public var tagset: [UInt32] = [1, 1]
    var frameSerial: UInt32 = 1
    var lastResizeFrame: UInt32 = 0

    public var gappih: Int32 /* horizontal gap between windows */
    public var gappiv: Int32 /* vertical gap between windows */
    public var gappoh: Int32 /* horizontal outer gaps */
    public var gappov: Int32 /* vertical outer gaps */
    // special workspace gaps, per monitor
    public var specialGappih: Int32
    public var specialGappiv: Int32
    public var specialGappoh: Int32
    public var specialGappov: Int32
    public let pertag = Pertag()
    public var ovbkCurrentTagset: UInt32 = 0
    public var ovbkPrevTagset: UInt32 = 0
    public var sel: ClientID?
    public var prevsel: ClientID?
    public var isoverview = false
    public var isJumpMode = false
    public var isInHotarea = false
    public var ovNormalMode = false /* Uses the normal grid layout when entering via the
                                       hot area. */
    public var ovTabLayout = false  /* Uses the centered tab layout when entering via
                                       overcircle. */
    public var specialEmptyView = false // user intentionally opened the empty special view
    public var visibleClients: Int32 = 0
    public var visibleTilingClients: Int32 = 0
    public var visibleScrollTilingClients: Int32 = 0
    public var visibleFakeTilingClients: Int32 = 0
    public var hideClients: UInt32 = 0
    package var titleMessageBar: MangoBarDecoration?
    public var carouselAnimDir = 0
    // not in mango: the cards, where client_tile_resize puts the clients in overview (the port's windows stay under its pictures)
    package var ovCards: [ClientID: CGRect] = [:]
    // not in mango: the port shows pictures of the windows (screen capture granted)
    package var ovThumbnails = false

    // not in mango: the layout of the tag in view, m->pertag->ltidxs[get_mon_curtag(m)]
    public var layout: LayoutKind { pertag.ltidxs[getMonCurtag(self)] }

    init(screen: Screen, config: Config) {
        self.screen = screen
        m = screen.frame
        w = screen.workArea
        gappih = Int32(config.gappih)
        gappiv = Int32(config.gappiv)
        gappoh = Int32(config.gappoh)
        gappov = Int32(config.gappov)
        specialGappih = Int32(config.specialGappih)
        specialGappiv = Int32(config.specialGappiv)
        specialGappoh = Int32(config.specialGappoh)
        specialGappov = Int32(config.specialGappov)
        pertag.curtag = 1
        pertag.prevtag = 1
        for i in 0...config.tagNum {
            pertag.nmasters[i] = Int32(config.defaultNmaster)
            pertag.mfacts[i] = Float(config.defaultMfact)
            pertag.ltidxs[i] = .tile
        }
    }
}

package extension MangoServer {
    func tagGatherResetSlot(_ m: Monitor, _ tag: UInt32) {
        tagSlotSetDefaults(m, tag)
        m.pertag.noHide[tag] = false
        m.pertag.noRenderBorder[tag] = false
        m.pertag.openAsFloating[tag] = false
        m.pertag.dwindleRoot[tag] = nil
        m.pertag.scrollerState[tag] = nil

        for tr in config.tagRules {
            if tagRuleMatchesMonitor(tr, m) && (tr.id == nil || tr.id == Int(tag)) {
                tagRuleApplyToSlot(m, tr, tag)
            }
        }
        m.pertag.ltidxs[tag] = m.pertag.configLtidxs[tag]
    }

    // move pertag state from src to dst, then reset src.
    func tagGatherMovePertag(_ m: Monitor, _ dst: UInt32, _ src: UInt32) {
        m.pertag.nmasters[dst] = m.pertag.nmasters[src]
        m.pertag.mfacts[dst] = m.pertag.mfacts[src]
        m.pertag.noHide[dst] = m.pertag.noHide[src]
        m.pertag.noRenderBorder[dst] = m.pertag.noRenderBorder[src]
        m.pertag.openAsFloating[dst] = m.pertag.openAsFloating[src]
        m.pertag.scrollerDefaultProportion[dst] = m.pertag.scrollerDefaultProportion[src]
        m.pertag.scrollerDefaultProportionSingle[dst] = m.pertag.scrollerDefaultProportionSingle[src]
        m.pertag.scrollerIgnoreProportionSingle[dst] = m.pertag.scrollerIgnoreProportionSingle[src]
        m.pertag.dwindleRoot[dst] = m.pertag.dwindleRoot[src]
        m.pertag.configLtidxs[dst] = m.pertag.configLtidxs[src]
        m.pertag.ltidxs[dst] = m.pertag.ltidxs[src]
        m.pertag.scrollerState[dst] = m.pertag.scrollerState[src]
        tagGatherResetSlot(m, src)
    }
}

public let TAG0_MASK: UInt32 = 1 << 31

extension MangoServer {
    var TAGMASK: UInt32 { tagmask }
}

@MainActor public func ISTILED(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isfloating && !a.isminimized && !a.iskilling && !a.ismaximizescreen && !a.isfullscreen && !a.isunglobal
}

@MainActor public func ISNORMAL(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isminimized && !a.iskilling && !a.isunglobal
}

/// mango INSIDEMON (manage/monitor.h).
@MainActor func INSIDEMON(_ a: Client) -> Bool {
    guard let m = a.mon else { return false }
    let g = a.geom, mm = m.m
    return g.minX >= mm.minX && g.minY >= mm.minY && g.minX + g.width <= mm.minX + mm.width
        && g.minY + g.height <= mm.minY + mm.height
}

/// mango GEOMINSIDEMON (manage/monitor.h).
@MainActor func GEOMINSIDEMON(_ a: CGRect, _ m: Monitor) -> Bool {
    let mm = m.m
    return a.minX >= mm.minX && a.minY >= mm.minY && a.minX + a.width <= mm.minX + mm.width
        && a.minY + a.height <= mm.minY + mm.height
}

@MainActor public func ISSCROLLTILED(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isfloating && !a.isminimized && !a.iskilling && !a.isunglobal
}

@MainActor public func ISFAKETILED(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isfloating && !a.isminimized && !a.iskilling && !a.isunglobal
}

@MainActor public func VISIBLEON(_ c: Client?, _ m: Monitor?) -> Bool {
    guard let c, let m else { return false }
    return c.mon === m && !c.isminimized
        && ((c.tags & m.tagset[m.seltags]) != 0 || c.isglobal || c.isunglobal)
}

@MainActor public func TAGMATCH(_ c: Client?, _ m: Monitor?) -> Bool {
    guard let c, let m else { return false }
    return c.mon === m && !c.isminimized && (c.tags & m.tagset[m.seltags]) != 0
}

@MainActor public func SCRATCHPAD_SHOWN(_ c: Client?) -> Bool {
    guard let c else { return false }
    return c.isInScratchpad && !c.isminimized
}

@MainActor public func ISFULLSCREEN(_ a: Client) -> Bool {
    a.isfullscreen || a.ismaximizescreen || a.overviewIsmaximizescreenbak || a.overviewIsfullscreenbak
}

package extension MangoServer {

}
