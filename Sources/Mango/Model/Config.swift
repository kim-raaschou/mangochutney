import Foundation
import CoreGraphics

public struct Config: Sendable {
    public init() {}

    public var animations = true
    public var animationTypeOpen: AnimationType = .slide
    public var animationTypeClose: AnimationType = .slide
    public var animationFadeIn = true
    public var animationFadeOut = true
    public var tagAnimationDirection = 1
    public var zoomInitialRatio = 0.4
    public var zoomEndRatio = 0.8
    public var fadeinBeginOpacity = 0.5
    public var fadeoutBeginOpacity = 0.5
    public var animationDurationMove = 500
    public var animationDurationOpen = 400
    public var animationDurationTag = 300
    public var animationDurationClose = 300
    public var animationDurationFocus = 0
    public var animationCurveMove = BezierCurve.mangoDefault
    public var animationCurveOpen = BezierCurve.mangoDefault
    public var animationCurveTag = BezierCurve.mangoDefault
    public var animationCurveClose = BezierCurve.mangoDefault
    public var animationCurveFocus = BezierCurve.mangoDefault

    public var scrollerStructs = 20
    public var scrollerDefaultProportion = 0.9
    public var scrollerDefaultProportionSingle = 1.0
    public var scrollerIgnoreProportionSingle = true
    public var scrollerFocusCenter = false
    public var scrollerPreferCenter = false
    public var scrollerPreferOverspread = true
    public var edgeScrollerPointerFocus = true
    public var edgeScrollerFocusAllowSpeed = 0.0
    public var scrollerProportionPreset: [Double] = []

    public var newIsMaster = true
    public var defaultMfact = 0.55
    public var defaultNmaster = 1
    public var centerMasterOverspread = false
    public var centerWhenSingleStack = true
    public var tagNum = 9
    public var tagGather = false
    public var tagCarousel = false
    public var viewCurrentToBack = false
    public var circleLayout: [String] = []
    public var dwindleVsplit = 1
    public var dwindleHsplit = 1
    public var dwindlePreserveSplit = false
    public var dwindleSmartSplit = false
    public var dwindleSmartResize = false
    public var dwindleManualSplit = false
    public var dwindleDropSimpleSplit = true
    public var dwindleSplitRatio = 0.5
    public var monocleTabMode = true
    public var monocleNoBorder = false
    public var monocleNoGap = false
    public var monocleNoRadius = false
    public var specialTagCrossMonitor = false
    public var deckTabMode = true
    public var tabBarHeight = 33
    public var groupBarHeight = 33
    public var alwaysShowGroupBar = false
    public var groupBarCloseButtonEnable = false
    public var groupBarButtonSize = 16
    public var groupBarButtonMargin = 4
    public var groupBarButtonColor = parseColor("0xad401fff")!
    public var monocleRightButtonClose = false
    public var titleMessageBarHeight = 52
    public var titleMessageBarGap = 20
    public var titleMessageBardata = DecorateStyle()
    public var tabbardata = DecorateStyle()
    public var groupbardata = DecorateStyle()
    public var jumplabeldata = DecorateStyle()

    public var gappih = 5
    public var gappiv = 5
    public var gappoh = 10
    public var gappov = 10
    public var smartgaps = false
    public var borderpx = 4
    public var borderRadius = 0
    public var noBorderWhenSingle = false
    public var noRadiusWhenSingle = false
    public var focusedOpacity = 1.0
    public var unfocusedOpacity = 1.0
    public var rootcolor = parseColor("0x323232ff")!
    public var bordercolor = parseColor("0x444444ff")!
    public var focuscolor = parseColor("0xc66b25ff")!
    public var urgentcolor = parseColor("0xad401fff")!
    public var maximizescreencolor = parseColor("0x89aa61ff")!
    public var scratchpadcolor = parseColor("0x516c93ff")!
    public var globalcolor = parseColor("0xb153a7ff")!
    public var overlaycolor = parseColor("0x14a57cff")!
    public var dropcolor = RGBA(r: 0xd5 / 255.0, g: 0x89 / 255.0, b: 0x9d / 255.0, a: 0.5)
    public var splitcolor = parseColor("0xeb441eff")!
    public var scratchpadWidthRatio = 0.8
    public var scratchpadHeightRatio = 0.9
    public var specialDim = 0.5
    public var specialGappih = 10
    public var specialGappiv = 10
    public var specialGappoh = 20
    public var specialGappov = 20

    public var hotareaSize = 10
    public var hotareaCorner = 2
    public var enableHotarea = false
    public var hotareaDisableOnFullscreen = true
    public var overviewgappi = 5
    public var overviewgappo = 30
    public var overcircleCenterRatio = 0.5
    public var jumpLabels = "HJKLASDFGQWERTYUIOPZXCVBNM"

    public var focusOnActivate = true
    public var sloppyfocus = true
    public var warpcursor = true
    public var focusCrossMonitor = false
    public var focusdirOnlyZoneOverlap = true
    public var focusCrossTag = false
    public var exchangeCrossMonitor = false
    public var scratchpadCrossMonitor = false
    public var singleScratchpad = true
    public var cursorHideTimeout = 0
    public var cursorHideOnKeypress = false
    public var dragCorner = 3
    public var dragWarpCursor = true
    public var enableBorderResize = true
    public var borderResizeSize = 10
    public var enableFloatingSnap = false
    public var snapDistance = 30
    public var floatFullToTop = false
    public var dragTileToTile = true
    public var dragTileSmall = true
    public var axisBindApplyTimeout = 100
    public var autoReloadConfig = true
    public var logLevel: WlrLogImportance = .error
    public var swipeMinThreshold = 1
    public var gestureLive = true
    public var gestureSwipeDistance = 300
    public var gestureSwipeCancelRatio = 0.5
    public var gestureSwipeMinSpeedToForce = 10.0
/// Not in mango: on macOS only the options that move keys are done.
    public var xkbRulesOptions = ""

    /// The boundary, not in mango: the values of the port's own keys, as its setters store
    /// them (ConfigPort); the port reads them as fields of its own (Port/Extensions/PortConfig.swift).
    package var port: [String: String] = [:]

    public var envVars: [(String, String)] = []
    public var exec: [String] = []
    public var execOnce: [String] = []

    public var keyBindings: [KeyBinding] = []
    public var mouseBindings: [MouseBinding] = []
    public var axisBindings: [AxisBinding] = []
    public var gestureBindings: [GestureBinding] = []
    public var windowRules: [WindowRule] = []
    public var tagRules: [TagRule] = []
    public var keymode = "default"

    public mutating func overrideConfig() {
        func c<T: Comparable>(_ v: inout T, _ lo: T, _ hi: T) { v = min(max(v, lo), hi) }
        c(&zoomInitialRatio, 0.1, 1); c(&zoomEndRatio, 0.1, 1)
        c(&fadeinBeginOpacity, 0, 1); c(&fadeoutBeginOpacity, 0, 1)
        c(&animationDurationMove, 0, 50000); c(&animationDurationOpen, 0, 50000)
        c(&animationDurationTag, 0, 50000); c(&animationDurationClose, 0, 50000)
        c(&animationDurationFocus, 0, 50000)
        c(&scrollerStructs, 0, 1000)
        c(&scrollerDefaultProportion, 0.1, 1); c(&scrollerDefaultProportionSingle, 0.1, 1)
        c(&edgeScrollerFocusAllowSpeed, 0, 1000)
        scrollerProportionPreset = scrollerProportionPreset.map { min(max($0, 0.1), 1) }
        c(&defaultMfact, 0.1, 0.9); c(&defaultNmaster, 1, 1000)
        c(&tagNum, 1, 31)
        c(&dwindleVsplit, 0, 2); c(&dwindleHsplit, 0, 2)
        c(&dwindleSplitRatio, 0.05, 0.95)
        c(&gappih, 0, 1000); c(&gappiv, 0, 1000)
        c(&gappoh, 0, 1000); c(&gappov, 0, 1000)
        c(&borderpx, 0, 200); c(&borderRadius, 0, 100)
        c(&focusedOpacity, 0, 1); c(&unfocusedOpacity, 0, 1)
        c(&hotareaCorner, 0, 3)
        c(&overcircleCenterRatio, 0.1, 0.9)
        c(&hotareaSize, 1, 1000)
        c(&overviewgappi, 0, 1000); c(&overviewgappo, 0, 1000)
        c(&dragCorner, 0, 4)
        c(&borderResizeSize, 0, 50)
        c(&snapDistance, 0, 99999)
        c(&cursorHideTimeout, 0, 36000)
        c(&axisBindApplyTimeout, 0, 1000)
        c(&swipeMinThreshold, 1, 1000)
        c(&gestureSwipeDistance, 32, 4096)
        c(&gestureSwipeCancelRatio, 0.05, 0.95)
        gestureSwipeMinSpeedToForce = max(0, gestureSwipeMinSpeedToForce)
        c(&scratchpadWidthRatio, 0.1, 1); c(&scratchpadHeightRatio, 0.1, 1)
        c(&specialDim, 0, 1)
        c(&tabBarHeight, 0, 500); c(&groupBarHeight, 0, 500)
        c(&titleMessageBarHeight, 0, 500); c(&titleMessageBarGap, 0, 500)
        c(&groupBarButtonSize, 4, 64); c(&groupBarButtonMargin, 0, 50)
        c(&specialGappih, 0, 1000); c(&specialGappiv, 0, 1000)
        c(&specialGappoh, 0, 1000); c(&specialGappov, 0, 1000)
    }
}

public enum AnimationType: String, Sendable {
    case slide, zoom, fade, none
}

public func animationTypeFromString(_ value: String) -> AnimationType {
    AnimationType(rawValue: value) ?? .slide
}
