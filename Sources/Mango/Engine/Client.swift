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
    public var scrollerProportion: CGFloat?
    public var scrollerProportionSingle: CGFloat?
    public var iscustomScrollerProportion = false
    public var iscustomScrollerProportionSingle = false
    public var masterSizeWeight: CGFloat = 0
    public var stackSizeWeight: CGFloat = 0
    public var masterInnerPer: CGFloat = 0
    public var stackInnerPer: CGFloat = 0
    public var ismaster = false
    public var isleftstack = false
/// Not in mango: scroller_stack_weight on the window; the port's scroller state holds only the columns.
    public var scrollerStackWeight: CGFloat = 0
    var oldMasterMfactPer: CGFloat = 0
    var oldMasterInnerPer: CGFloat = 0
    var oldStackInnerPer: CGFloat = 0
    var oldScrollerPproportion: CGFloat = 0
    var scrollerOldStackProportion: CGFloat = 0
    var oldGridColPer: CGFloat = 0
    var oldGridRowPer: CGFloat = 0
    var cursorInUpperHalf = false
    var cursorInLeftHalf = false
    var dragBeginGeom: CGRect = .zero

/// Not in mango: without the border (mango's box includes it).
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
    public var overviewBackupGeom: CGRect?
    public var overviewBackupBw: CGFloat = 0
    public var overviewIsfloatingbak = false
    public var overviewIsfullscreenbak = false
    public var overviewIsmaximizescreenbak = false
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
    public var dwindleRoot = PertagSlots<DwindleTree>(DwindleTree())
    public var configLtidxs = PertagSlots<LayoutKind>(.tile)
    public var ltidxs = PertagSlots<LayoutKind>(.tile)
    public var scrollerState = PertagSlots<ScrollerState>(ScrollerState())
}

@MainActor
public final class Monitor {
    public var screen: Screen
    public var seltags = 0
    public var tagset: [UInt32] = [1, 1]
    var lastResizeTime: UInt32 = 0   // not in mango: last_resize_frame, as the time of that frame

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

@MainActor public func isSpecialActive(_ m: Monitor?) -> Bool {
    guard let m else { return false }
    return !m.isoverview && (m.tagset[m.seltags] & TagMask.special) != 0
}

@MainActor public func getMonCurtag(_ m: Monitor?) -> UInt32 {
    guard let m else { return 0 }
    // special workspace uses slot 0; all-tags is an ordinary multi-tag view
    // and follows its first tag
    if isSpecialActive(m) { return 0 }
    return m.pertag.curtag != 0 ? m.pertag.curtag : 1
}

package extension MangoServer {
    // Reset a pertag slot to defaults.
    func tagSlotSetDefaults(_ m: Monitor, _ tag: UInt32) {
        m.pertag.nmasters[tag] = Int32(config.defaultNmaster)
        m.pertag.mfacts[tag] = Float(config.defaultMfact)
        m.pertag.configLtidxs[tag] = .tile
        m.pertag.scrollerDefaultProportion[tag] = Float(config.scrollerDefaultProportion)
        m.pertag.scrollerDefaultProportionSingle[tag] = Float(config.scrollerDefaultProportionSingle)
        m.pertag.scrollerIgnoreProportionSingle[tag] = config.scrollerIgnoreProportionSingle
    }

    // Apply one tag rule to a slot (caller checks coverage).
    func tagRuleApplyToSlot(_ m: Monitor, _ tr: ConfigTagRule, _ tag: UInt32) {
        for layout in LayoutKind.allCases {
            if let ln = tr.layoutName, layout.name == ln { m.pertag.configLtidxs[tag] = layout }
        }

        m.pertag.noHide[tag] = tr.noHide
        if let v = tr.masterCount, v >= 1 { m.pertag.nmasters[tag] = Int32(v) }
        if let v = tr.masterFactor, v > 0 { m.pertag.mfacts[tag] = Float(v) }
        m.pertag.noRenderBorder[tag] = tr.noRenderBorder
        m.pertag.openAsFloating[tag] = tr.openAsFloating
        if tr.scrollerDefaultProportion > 0 {
            m.pertag.scrollerDefaultProportion[tag] = Float(tr.scrollerDefaultProportion)
        }
        if tr.scrollerDefaultProportionSingle > 0 {
            m.pertag.scrollerDefaultProportionSingle[tag] = Float(tr.scrollerDefaultProportionSingle)
        }
        if let v = tr.scrollerIgnoreProportionSingle { m.pertag.scrollerIgnoreProportionSingle[tag] = v }
    }

    func parseTagrule(_ m: Monitor) {
        let prevConfigLtidxs = m.pertag.configLtidxs

        // Set defaults for every tag.
        for i in 0...UInt32(config.tagNum) { tagSlotSetDefaults(m, i) }

        for tr in config.tagRules {
            if tr.tagRuleMatchesMonitor(m.screen) && (tr.id == nil || tr.id! <= config.tagNum) {
                let tagIdStart = tr.id ?? 0
                let tagIdEnd = tr.id ?? config.tagNum

                for ti in tagIdStart...tagIdEnd { tagRuleApplyToSlot(m, tr, UInt32(ti)) }
            }
        }

        for i in 0...config.tagNum where prevConfigLtidxs[i] != m.pertag.configLtidxs[i] {
            m.pertag.ltidxs[i] = m.pertag.configLtidxs[i]
        }

        for i in 1...UInt32(config.tagNum) {
            for c in clientsAll where (c.tags & (1 << (i - 1)) & TAGMASK) != 0 && ISTILED(c) {
                // not in mango: this monitor's windows only; mango's gives every window the last monitor's mfact (a mango bug, docs/afvigelser.md §6).
                guard c.mon === m else { continue }
                if m.pertag.mfacts[i] > 0 { c.masterMfactPer = CGFloat(m.pertag.mfacts[i]) }
            }
        }
    }

    func tagGatherResetSlot(_ m: Monitor, _ tag: UInt32) {
        tagSlotSetDefaults(m, tag)
        m.pertag.noHide[tag] = false
        m.pertag.noRenderBorder[tag] = false
        m.pertag.openAsFloating[tag] = false
        m.pertag.dwindleRoot[tag] = DwindleTree()
        m.pertag.scrollerState[tag] = ScrollerState()

        for tr in config.tagRules {
            if tr.tagRuleMatchesMonitor(m.screen) && (tr.id == nil || tr.id == Int(tag)) {
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

    func updateGlobalVar() {
        tagmask = (UInt32(1) << UInt32(config.tagNum)) - 1
    }
}

@MainActor public func ISTILED(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isfloating && !a.isminimized && !a.iskilling && !a.ismaximizescreen && !a.isfullscreen && !a.isunglobal
}

@MainActor public func ISNORMAL(_ a: Client?) -> Bool {
    guard let a else { return false }
    return !a.isminimized && !a.iskilling && !a.isunglobal
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
    // not in mango: groupParked stands for client_park's c->mon = NULL
    return c.mon === m && !c.groupParked && !c.isminimized
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
    func getTagsFirstTagNum(_ sourceTags: UInt32) -> UInt32 {
        var i: UInt32 = 0, tag: UInt32 = 0

        if sourceTags == 0 { return 0 }

        if sourceTags & TAG0_MASK != 0 { return 0 }

        while tag & 1 == 0 && sourceTags != 0 && i < UInt32(config.tagNum) {
            tag = sourceTags >> i
            i += 1
        }

        if i == 1 {
            return 1
        } else if i >= UInt32(config.tagNum) {
            return UInt32(config.tagNum)
        } else {
            return i
        }
    }

    func getClientTagIdx(_ c: Client?) -> UInt32 {
        guard let c, c.tags & TAG0_MASK == 0 else { return 0 }
        return getTagsFirstTagNum(c.tags)
    }
}
