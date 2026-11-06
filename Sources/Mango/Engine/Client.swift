import Foundation
import CoreGraphics

@MainActor
public protocol PlatformWindow: AnyObject {
    var frame: CGRect { get set }
    var parked: Bool { get set }
    var isFloatType: Bool { get }   // not in mango: wlroots' side of client_is_float_type
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

    public var isFloating = false
    public var isFullscreen = false
    public var isFakeFullscreen = false
    public var isMaximizeScreen = false
    public var isGlobal = false
    public var isUnglobal = false
    public var ignoreMinimize = true
    public var isOverlay = false
    public var isInScratchpad = false
    public var oldTags: UInt32 = 0
    public var isMinimized = false
    public var scratchpadShown: Bool { isInScratchpad && !isMinimized }
    public var isNamedScratchpad = false
    public var isCustomSize = false
    public var isCustomPos = false
    public var isOpenSilent = false
    public var isTagSilent = false
    public var isUrgent = false

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
    public var noForceCenter = false
    public var noFocus = false
    public var confinePointer = false
    public var animationTypeOpen: AnimationType?
    public var scrollerProportion: CGFloat?
    public var scrollerProportionSingle: CGFloat?
    public var isCustomScrollerProportion = false
    public var isCustomScrollerProportionSingle = false
    public var masterSizeWeight: CGFloat = 0
    public var stackSizeWeight: CGFloat = 0
    public var masterInnerPer: CGFloat = 0
    public var stackInnerPer: CGFloat = 0
    public var isMaster = false
    public var isLeftStack = false
/// Not in mango: scroller_stack_weight on the window; the port's scroller state holds only the columns.
    public var scrollerStackWeight: CGFloat = 0
    var oldMasterMfactPer: CGFloat = 0
    var oldMasterInnerPer: CGFloat = 0
    var oldStackInnerPer: CGFloat = 0
    var oldScrollerProportion: CGFloat = 0
    var scrollerOldStackProportion: CGFloat = 0
    var oldGridColPer: CGFloat = 0
    var oldGridRowPer: CGFloat = 0
    var cursorInUpperHalf = false
    var cursorInLeftHalf = false
    var dragBeginGeom: CGRect = .zero

/// Not in mango: without the border (mango's box includes it).
    public var floatGeom: CGRect
/// Not in mango: without the border (mango's box includes it).
    public var geom: CGRect?
    public var isNew = true
    public var overining = false
    public var tagouting = false
    public var scratchpadTagin = false
    public var overviewBackupGeom: CGRect?
    public var overviewIsFloatingBak = false
    public var overviewIsFullscreenBak = false
    public var overviewIsMaximizeScreenBak = false

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
    }


    public var appid: String { bundleId.isEmpty ? appName : bundleId }

    public func isVisible(on m: Monitor) -> Bool {
        guard mon === m, !groupParked, !isMinimized else { return false }
        if isGlobal || isUnglobal { return true }
        return tags & m.tagset[m.seltags] != 0
    }
}

@MainActor
public final class Pertag {
    public var layout: LayoutKind
    public var settings: PertagSettings
    public let state = TagLayoutState()
    public var noRenderBorder = false
    public var openAsFloating = false
    public var noHide = false
    public var configLayout: LayoutKind = .tile

    init(layout: LayoutKind, settings: PertagSettings) {
        self.layout = layout
        self.settings = settings
    }
}

@MainActor
public final class Monitor {
    public var screen: Screen
    public var tagset: [UInt32] = [1, 1]
    public var seltags = 0
    public var pertag: [Pertag] = []
    public var sel: ClientID?
    var lastResizeTime: UInt32 = 0   // not in mango: last_resize_frame, as the time of that frame
    public var prevsel: ClientID?
    public var gaps: Gaps
    public var specialGaps: Gaps
    public var curtag = 1
    public var prevTag = 1
    public var carouselAnimDir = 0
    public var isInHotarea = false
    public var specialEmptyView = false
    public var ovbkCurrentTagset: UInt32 = 0
    public var ovbkPrevTagset: UInt32 = 0

    public var getMonCurtag: Int {
        // special workspace uses slot 0; all-tags is an ordinary multi-tag view
        // and follows its first tag
        // not in mango: no isoverview test; the overview's tagset never holds the special tag.
        if tagset[seltags] & TagMask.special != 0 { return 0 }
        return curtag != 0 ? curtag : 1
    }

    public var current: Pertag { pertag[getMonCurtag] }
    public var layout: LayoutKind { current.layout }

    init(screen: Screen, config: Config) {
        self.screen = screen
        gaps = Gaps(ih: CGFloat(config.gappih), iv: CGFloat(config.gappiv),
                    oh: CGFloat(config.gappoh), ov: CGFloat(config.gappov))
        specialGaps = Gaps(ih: CGFloat(config.specialGappih), iv: CGFloat(config.specialGappiv),
                           oh: CGFloat(config.specialGappoh), ov: CGFloat(config.specialGappov))
        pertag = (0...31).map { _ in
            Pertag(layout: .tile, settings: PertagSettings(
                nmaster: config.defaultNmaster,
                mfact: CGFloat(config.defaultMfact),
                scrollerDefaultProportion: CGFloat(config.scrollerDefaultProportion),
                scrollerDefaultProportionSingle: CGFloat(config.scrollerDefaultProportionSingle),
                scrollerIgnoreProportionSingle: config.scrollerIgnoreProportionSingle))
        }
        parseTagrule(config: config, clients: [])
    }

    func tagGatherResetSlot(_ tag: Int, config: Config) {
        let p = Pertag(layout: .tile, settings: PertagSettings(
            nmaster: config.defaultNmaster,
            mfact: CGFloat(config.defaultMfact),
            scrollerDefaultProportion: CGFloat(config.scrollerDefaultProportion),
            scrollerDefaultProportionSingle: CGFloat(config.scrollerDefaultProportionSingle),
            scrollerIgnoreProportionSingle: config.scrollerIgnoreProportionSingle))
        var ruleLayout: LayoutKind?
        for r in config.tagRules {
            if let id = r.id, id != tag { continue }
            guard r.tagRuleMatchesMonitor(screen) else { continue }
            if let ln = r.layoutName, let k = LayoutKind(name: ln) { ruleLayout = k }
            if let v = r.masterCount { p.settings.nmaster = v }
            if let v = r.masterFactor { p.settings.mfact = CGFloat(v) }
            if let v = r.scrollerDefaultProportion { p.settings.scrollerDefaultProportion = CGFloat(v) }
            if let v = r.scrollerDefaultProportionSingle { p.settings.scrollerDefaultProportionSingle = CGFloat(v) }
            if let v = r.scrollerIgnoreProportionSingle { p.settings.scrollerIgnoreProportionSingle = v }
            if let v = r.noRenderBorder { p.noRenderBorder = v }
            if let v = r.openAsFloating { p.openAsFloating = v }
            if let v = r.noHide { p.noHide = v }
        }
        p.configLayout = ruleLayout ?? .tile
        p.layout = p.configLayout
        pertag[tag] = p
    }

    func tagGatherMovePertag(dst: Int, src: Int, config: Config) {
        pertag[dst] = pertag[src]
        tagGatherResetSlot(src, config: config)
    }

    func parseTagrule(config: Config, clients: [Client]) {
        for (i, p) in pertag.enumerated() {
            p.settings.nmaster = config.defaultNmaster
            p.settings.mfact = CGFloat(config.defaultMfact)
            p.settings.scrollerDefaultProportion = CGFloat(config.scrollerDefaultProportion)
            p.settings.scrollerDefaultProportionSingle = CGFloat(config.scrollerDefaultProportionSingle)
            p.settings.scrollerIgnoreProportionSingle = config.scrollerIgnoreProportionSingle
            var ruleLayout: LayoutKind?
            for r in config.tagRules {
                if let id = r.id, id != i { continue }
                guard r.tagRuleMatchesMonitor(screen) else { continue }
                if let ln = r.layoutName, let k = LayoutKind(name: ln) { ruleLayout = k }
                if let v = r.masterCount { p.settings.nmaster = v }
                if let v = r.masterFactor { p.settings.mfact = CGFloat(v) }
                if let v = r.scrollerDefaultProportion { p.settings.scrollerDefaultProportion = CGFloat(v) }
                if let v = r.scrollerDefaultProportionSingle { p.settings.scrollerDefaultProportionSingle = CGFloat(v) }
                if let v = r.scrollerIgnoreProportionSingle { p.settings.scrollerIgnoreProportionSingle = v }
                if let v = r.noRenderBorder { p.noRenderBorder = v }
                if let v = r.openAsFloating { p.openAsFloating = v }
                if let v = r.noHide { p.noHide = v }
            }
            let prevConfigLayout = p.configLayout
            p.configLayout = ruleLayout ?? .tile
            if prevConfigLayout != p.configLayout { p.layout = p.configLayout }
        }
        let tagmask = TagMask.mask(forTagNum: config.tagNum)
        for i in 1...max(1, min(config.tagNum, pertag.count - 1)) {
            for c in clients where c.tags & (1 << UInt32(i - 1)) & tagmask != 0
                && !c.isFloating && !c.isMinimized && !c.isMaximizeScreen && !c.isFullscreen && !c.isUnglobal {
                // not in mango: this monitor's windows only; mango's gives every window the last monitor's mfact (a mango bug, docs/afvigelser.md §6).
                guard c.mon === self else { continue }
                if pertag[i].settings.mfact > 0 { c.masterMfactPer = pertag[i].settings.mfact }
            }
        }
    }
}
