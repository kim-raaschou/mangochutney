import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

final class FakeApp: WindowWriter {
    struct Write: Equatable {
        var id: CGWindowID
        var frame: CGRect
        var setSize: Bool
    }

    var frames: [CGWindowID: CGRect] = [:]
    var writes: [Write] = []
    var minSize: [CGWindowID: CGSize] = [:]
    var busy = false
    var movesBackTo: [CGWindowID: CGRect] = [:]
    var appliesAfter: TimeInterval = 0
    private var elements: [(AXUIElement, CGWindowID)] = []

    func element(for id: CGWindowID) -> AXUIElement {
        if let e = elements.first(where: { $0.1 == id }) { return e.0 }
        let e = AXUIElementCreateApplication(pid_t(id))
        elements.append((e, id))
        return e
    }

    private func id(of element: AXUIElement) -> CGWindowID? {
        elements.first { CFEqual($0.0, element) }?.1
    }

    func write(_ element: AXUIElement, id: CGWindowID, frame: CGRect, setSize: Bool, animating: Bool,
               written: (@MainActor (CGRect) -> Void)?) {
        writes.append(Write(id: id, frame: frame, setSize: setSize))
        guard !busy else { return }
        var f = frame
        if !setSize, let old = frames[id] { f.size = old.size }
        if let m = minSize[id] {
            f.size.width = max(f.width, m.width)
            f.size.height = max(f.height, m.height)
        }
        if appliesAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + appliesAfter) { [self] in frames[id] = movesBackTo[id] ?? f }
            return
        }
        frames[id] = movesBackTo[id] ?? f
        if let written {
            let applied = frames[id]!
            DispatchQueue.main.async { MainActor.assumeIsolated { written(applied) } }
        }
    }

    func readBack(_ element: AXUIElement, completion: @escaping @MainActor (CGRect?) -> Void) {
        let f = busy ? nil : id(of: element).flatMap { frames[$0] }
        DispatchQueue.main.async { MainActor.assumeIsolated { completion(f) } }
    }

    func raise(_ element: AXUIElement) {}
    func async(_ body: @escaping () -> Void) { body() }
    func restoreAppSettings() {}
}

/// mango's MangoBarDecoration as the tests see it.
@MainActor
final class FakeBar: MangoBarDecoration {
    var enabled = true
    var lastText: String?
    var lastScale = 0.0
    var frame = CGRect.zero
    var data: DecorateStyle
    var updates = 0, raises = 0, destroyed = false
    init(_ data: DecorateStyle) { self.data = data }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func setPosition(_ x: CGFloat, _ y: CGFloat) { frame.origin = CGPoint(x: x, y: y) }
    func raiseToTop() { raises += 1 }
    func update(_ text: String, _ scale: Double) { lastText = text; lastScale = scale; updates += 1 }
    func setSize(_ width: CGFloat, _ height: CGFloat) { frame.size = CGSize(width: width, height: height) }
    func setFocus(_ focused: Bool) {}
    func setCenterSecondaryLine(_ center: Bool) {}
    func applyConfig(_ data: DecorateStyle) { self.data = data }
    func destroy() { destroyed = true }
}

/// mango's MangoJumpLabel as the tests see it.
@MainActor
final class FakeJumpLabel: MangoJumpLabel {
    var enabled = false
    var logicalWidth: CGFloat = 0
    var logicalHeight: CGFloat = 0
    var text: String?
    var position = CGPoint.zero
    var data: DecorateStyle
    var destroyed = false
    init(_ data: DecorateStyle) { self.data = data }
    func setEnabled(_ enabled: Bool) { self.enabled = enabled }
    func setPosition(_ x: CGFloat, _ y: CGFloat) { position = CGPoint(x: x, y: y) }
    func raiseToTop() {}
    func update(_ text: String, _ scale: Double) { self.text = text; logicalWidth = 40; logicalHeight = 40 }
    func applyConfig(_ data: DecorateStyle) { self.data = data }
    func destroy() { destroyed = true }
}

@MainActor
final class FakeWindowSystem: MacWindowSystem {
    var fakePointer = CGPoint(x: 1, y: 1)
    var fakeModifiers: Modifiers = []
    var quits = 0
    var asked = 0
    var closed: [ClientID] = []
    override func clientSendClose(_ c: Client) { closed.append(c.id) }
    override var pointer: CGPoint { fakePointer }
    override func keyboardHardModifiers() -> Modifiers { fakeModifiers }
    override var mouseButtons: Int { 0 }
    override func startInput() {}
    override func watchGestures(_ on: Bool) {}
    var fakeCanCapture = false
    override var canCapture: Bool { fakeCanCapture }
    override func quit() { quits += 1 }
    override func askToCapture() { asked += 1 }
    var focused: [(id: ClientID, raise: Bool)] = []
    var warps: [CGPoint] = []
    override func sendNativeFocus(_ c: Client, raise: Bool) { focused.append((c.id, raise)) }
    var raised: [ClientID] = []
    override func sendNativeRaise(_ c: Client) { raised.append(c.id) }
    override func warp(to p: CGPoint) { warps.append(p); fakePointer = p }
    var borderSpecs: [BorderSpec] = []
    override func drawBorders(_ specs: [BorderSpec]) { borderSpecs = specs }
    var tabStrips: [TabStrip] = [], groupStrips: [TabStrip] = []
    override func drawTabBars(_ strips: [TabStrip], style: TabStripStyle) { tabStrips = strips; tabBarsChanged() }
    override func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle) { groupStrips = strips }
    var overviewCards: [OverviewCard]?, switcherTiles: [SwitcherTile]?
    var specialDimAlpha: Double?, shownDropArea: CGRect?, nagArgv: [String]?, nagInput = "", cursorHidden = false
    override func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) { overviewCards = cards }
    override func updateOverview(_ cards: [OverviewCard], on m: Monitor) { overviewCards = cards }
    override func captureOverviewCards(on m: Monitor, scale: CGFloat) {}
    override func closeOverview(on m: Monitor) { overviewCards = nil }
    override func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat) { switcherTiles = tiles }
    override func switcherApplyHighlight(_ tiles: [SwitcherTile]) { switcherTiles = tiles }
    override func closeSwitcherPanel() { switcherTiles = nil }
    var bars: [FakeBar] = []
    override func mangoBarDecorationCreate(_ m: Monitor, _ data: DecorateStyle, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? {
        let bar = FakeBar(data)
        bars.append(bar)
        return bar
    }
    var jumpLabels: [ClientID: FakeJumpLabel] = [:]
    override func mangoJumpLabelNodeCreate(_ c: Client, _ data: DecorateStyle) -> MangoJumpLabel? {
        let label = FakeJumpLabel(data)
        jumpLabels[c.id] = label
        return label
    }
    /// A fixed keymap: a letter's key code is its place in the alphabet.
    override func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode {
        guard let a = keysym.lowercased().first?.asciiValue, a >= 97, a <= 122 else { return MultiKeycode() }
        return MultiKeycode(keycode1: UInt16(a - 97))
    }
    override func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>) { specialDimAlpha = alpha }
    override func showDropArea(_ area: CGRect?, color: RGBA) { shownDropArea = area }
    override func nagSpawn(_ argv: [String], input: String) { nagArgv = argv; nagInput = input }
    override func nagKill() { nagArgv = nil }
    var fitNotification: (title: String, body: String, fit: Bool)?
    override func postFitNotification(title: String, body: String, fit: Bool) { fitNotification = (title, body, fit) }
    override func removeFitNotification() { fitNotification = nil }
    var axFullscreen: (ClientID) -> Bool? = { _ in false }
    override func fullscreenNow(_ c: Client) -> Bool? { axFullscreen(c.id) }
    var onScreen: (CGWindowID) -> Bool = { _ in true }
    override func windowOnScreen(_ id: CGWindowID) -> Bool { onScreen(id) }
    var anchored = 0
    override func focusSpaceAnchor(_ m: Monitor) { anchored += 1 }
    /// The fullscreen written to each window, and whether the app takes it.
    var fullscreenWrites: [(ClientID, Bool)] = []
    var takesFullscreen: (ClientID) -> Bool = { _ in true }
    override func setNativeFullscreen(_ c: Client, _ fullscreen: Bool, _ done: @escaping @MainActor (Bool) -> Void) {
        fullscreenWrites.append((c.id, fullscreen))
        done(takesFullscreen(c.id))
    }
    var focusAsked: [ClientID] = []
    /// The app answers which window has the keys: this one.
    override func askFocus(_ c: Client) { focusAsked.append(c.id); windowFocused(id: c.id) }
    override func setCursorHidden(_ hidden: Bool) { cursorHidden = hidden }
    var cursorName: String??
    override func setCursor(_ name: String?) { cursorName = .some(name) }
    var surfaceOverride: ClientID?
    override func surfaceAt(_ p: CGPoint) -> ClientID? {
        surfaceOverride ?? server.clientsAll.first { !$0.parked && $0.frame.contains(p) }?.id
    }
    var keyboardOptions: String?
    override func setKeyboardOptions(_ options: String) { keyboardOptions = options }
    var fakeInputDevices: [InputDevice] = []
    override var inputDevices: [InputDevice] { fakeInputDevices }
    var spawned: [String] = [], shelled: [String] = []
    override func spawn(_ command: String) { spawned.append(command) }
    override func spawnShell(_ command: String) { spawned.append(command); shelled.append(command) }
}

@MainActor
final class EngineRig {
    let server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/mango.conf"))
    let app = FakeApp()
    let screen = Screen(displayID: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                        workArea: CGRect(x: 0, y: 37, width: 1728, height: 1080), scale: 2, isMain: true)

    init() {
        keepConfigErrorsInTests()
        server.config.animations = false
        server.renderBorder = false
        server.rebuildMonitors(screens: [screen])
        let app = app
        server.system = FakeWindowSystem(server)
        server.mac.frameClock.manual = true
        server.mac.memory.layoutURL = nil
        server.mac.writerOverride = { _ in app }
        server.mac.windowServerOverride = { [app] id in app.frames[id] }
        server.mac.stackingOverride = { [] }
        server.started = true
        server.registerPortExtensions()
    }

    var monitor: Monitor { server.monitors[0] }

    @discardableResult
    func window(_ id: CGWindowID, tags: UInt32 = 1, floating: Bool = false,
                frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) -> Client {
        let w = DiscoveredWindow(id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test",
                                 title: "t\(id)", subrole: "AXStandardWindow", isDialog: false, frame: frame, isminimized: false, isfullscreen: false, isAppHidden: false)
        let c = Client(window: w, monitor: monitor, tags: tags)
        c.isfloating = floating
        c.isPendingOpenAnimation = false
        app.frames[id] = frame
        server.clients.append(c)
        server.focusStack.insert(id, at: 0)
        return c
    }

    @discardableResult
    func map(_ id: CGWindowID, frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) -> Client {
        app.frames[id] = frame
        server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: app.element(for: id), bundleId: "test", appName: "Test", title: "t\(id)",
            subrole: "AXStandardWindow", isDialog: false, frame: frame, isminimized: false,
            isfullscreen: false, isAppHidden: false))
        return server.clientByIdAll(id)!
    }

    /// The run loop for `seconds`, with an output frame every 16 ms (the tests' display link).
    func settle(_ seconds: TimeInterval = 0.05) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.016)))
            server.mac.frameClock.fire()
        } while Date() < end
    }
}


extension MangoServer {
    /// Any monitor in overview.
    var anyOverview: Bool { monitors.contains { $0.isoverview } }
}
