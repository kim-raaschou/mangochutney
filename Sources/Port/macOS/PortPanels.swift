import AppKit
import Mango

/// The panels the port draws over macOS, its own windows where wlroots has scene nodes: edge plates,
/// the overview, the switcher, the title-message bar and jump labels, the special dim, the drop area,
/// mangonag, the fit notification, the cursor and the scene panels (the workspace overview). The seam
/// between MacWindowSystem and AppKit: AppKitPanels in the app; the tests give their own, which draws
/// nothing and keeps what it was asked.
@MainActor
protocol PortPanels: AnyObject {
    func showEdgePlate(_ c: Client, box: CGRect, monitor: CGRect, border: EdgePlates.Border)
    func setEdgePlateBorder(_ id: ClientID, _ border: EdgePlates.Border)
    func hideEdgePlate(_ id: ClientID)
    func hideAllEdgePlates()

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook)
    func updateOverview(_ cards: [OverviewCard], on m: Monitor)
    func captureOverviewCards(on m: Monitor, scale: CGFloat)
    func closeOverview(on m: Monitor)
    /// Whether an overview panel is up.
    var overviewShown: Bool { get }

    func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat)
    func switcherApplyHighlight(_ tiles: [SwitcherTilePicture])
    func closeSwitcher()

    func barDecoration(_ m: Monitor, _ data: DecorateDrawData, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration?
    func jumpLabel(_ c: Client, _ data: DecorateDrawData) -> MangoJumpLabel?

    /// The special workspace's dim over a monitor, under the window `below` (nil alpha: none).
    func showSpecialDim(on m: Monitor, alpha: Float?, below: CGWindowID?)
    func showDropArea(_ area: CGRect?, color: RGBA)

    func nagSpawn(_ argv: [String], input: String, selected: CGDirectDisplayID?, macOS: Bool)
    func nagKill()

    func postFitNotification(title: String, body: String, fit: Bool)
    func removeFitNotification()

    func setCursorHidden(_ hidden: Bool)
    func setCursor(_ name: String?)

    /// A panel that draws a scene tree on a monitor (the workspace overview).
    func scenePanel(frame: CGRect, look: SceneDrawing.Look,
                    capture: @escaping ([ClientID], @escaping (ClientID, CGImage, CGSize) -> Void) -> Void,
                    icon: @escaping (ClientID) -> NSImage?,
                    layoutIcon: @escaping (LayoutKind) -> CGImage?,
                    windowSizes: @escaping (ClientID) -> SceneDrawing.WindowSize?) -> any ScenePanelDrawing
}

/// A scene panel as MacWindowSystem uses it: ScenePanel in the app.
@MainActor
protocol ScenePanelDrawing: AnyObject {
    /// The tree as the frame left it; the badges stay as they were for nil.
    func draw(_ tree: WlrSceneTree, badges: [SceneDrawing.Badge]?)
    func close()
    func covers(_ p: CGPoint) -> Bool
    func scenePoint(_ p: CGPoint) -> CGPoint
    var badgeHits: [(box: CGRect, tag: UInt32)] { get }
    /// The windows shown live (their size changes); the others keep their picture.
    func stream(_ ids: Set<ClientID>)
}

extension ScenePanel: ScenePanelDrawing {}

/// The panels drawn with AppKit.
@MainActor
final class AppKitPanels: PortPanels {
    private unowned let mac: MacWindowSystem
    private var overviewOverlays: [ObjectIdentifier: OverviewOverlay] = [:]
    private var switcherPanel: SwitcherPanel?
    private var specialDims: [CGDirectDisplayID: SpecialDimView] = [:]
    private var dropArea: DropAreaView?
    private let nagDisplay = Nag()
    private lazy var edgePlates: EdgePlates = {
        let plates = EdgePlates()
        plates.onClick = { [weak self] id in
            guard let self, let c = self.mac.server.clientByWindowID(id) else { return }
            self.mac.server.clientFocus(c, true)
        }
        return plates
    }()

    init(_ mac: MacWindowSystem) { self.mac = mac }

    func showEdgePlate(_ c: Client, box: CGRect, monitor: CGRect, border: EdgePlates.Border) {
        edgePlates.show(c.windowID, pid: c.pid, box: box, monitor: monitor, border: border)
    }
    func setEdgePlateBorder(_ id: ClientID, _ border: EdgePlates.Border) { edgePlates.setBorder(id, border) }
    func hideEdgePlate(_ id: ClientID) { edgePlates.hide(id) }
    func hideAllEdgePlates() { edgePlates.hideAll() }

    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook) {
        overviewOverlays[ObjectIdentifier(m)]?.close()
        let macOS = mac.server.config.chutneyMacOSAppearance
        let overlay = OverviewOverlay(workArea: m.screen.workArea, top: m.screen.frame.minY, focusColor: look.focusColor, borderColor: look.borderColor,
                                      mango: macOS ? nil : .init(root: look.mango.root, borderWidth: look.mango.borderWidth,
                                                                 cornerRadius: look.mango.cornerRadius))
        overviewOverlays[ObjectIdentifier(m)] = overlay
        overlay.show(cards.map(card))
    }

    func updateOverview(_ cards: [OverviewCard], on m: Monitor) {
        overviewOverlays[ObjectIdentifier(m)]?.update(cards.map(card))
    }

    func captureOverviewCards(on m: Monitor, scale: CGFloat) {
        overviewOverlays[ObjectIdentifier(m)]?.captureCards(scale: scale)
    }

    func closeOverview(on m: Monitor) {
        overviewOverlays.removeValue(forKey: ObjectIdentifier(m))?.close()
    }

    var overviewShown: Bool { !overviewOverlays.isEmpty }

    private func card(_ c: OverviewCard) -> OverviewOverlay.Card {
        .init(id: c.id, frame: c.frame, title: c.title, pid: c.pid, focused: c.focused,
              fullscreen: mac.server.clientByWindowID(c.id).map { mac.nativeFullscreen($0) } ?? false)
    }

    func showSwitcher(panel: CGRect, tiles: [SwitcherTilePicture], look: SwitcherLook, scale: CGFloat) {
        switcherPanel?.close()
        switcherPanel = SwitcherPanel(panel: panel, tiles: tiles.map(Self.tile),
                                      style: .init(focus: look.focus, border: look.border,
                                                   macOS: mac.server.config.chutneyMacOSAppearance),
                                      scale: scale)
    }

    func switcherApplyHighlight(_ tiles: [SwitcherTilePicture]) { switcherPanel?.highlight(tiles.map(Self.tile)) }

    func closeSwitcher() {
        switcherPanel?.close()
        switcherPanel = nil
    }

    static func tile(_ t: SwitcherTilePicture) -> SwitcherPanel.Tile {
        .init(id: t.id, frame: t.frame, size: t.size, pid: t.pid, highlighted: t.highlighted)
    }

    func barDecoration(_ m: Monitor, _ data: DecorateDrawData, _ width: CGFloat, _ height: CGFloat) -> MangoBarDecoration? {
        let bar = TitleMessageBarDecoration(data) { [unowned self] in mac.server.config }
        bar.setSize(width, height)
        return bar
    }

    func jumpLabel(_ c: Client, _ data: DecorateDrawData) -> MangoJumpLabel? {
        JumpLabelNode(data) { [unowned self] in mac.server.config }
    }

    func showSpecialDim(on m: Monitor, alpha: Float?, below: CGWindowID?) {
        let id = m.screen.displayID
        guard let alpha else { specialDims[id]?.hide(); return }
        let view = specialDims[id] ?? SpecialDimView()
        specialDims[id] = view
        view.show(frame: m.screen.frame, alpha: Double(alpha), below: below)
    }

    func showDropArea(_ area: CGRect?, color: RGBA) {
        guard let area else { dropArea?.hide(); return }
        if dropArea == nil { dropArea = DropAreaView() }
        dropArea?.show(area, color: color)
    }

    func nagSpawn(_ argv: [String], input: String, selected: CGDirectDisplayID?, macOS: Bool) {
        nagDisplay.spawn(argv, input: input, selected: selected, macOS: macOS)
    }

    func nagKill() { nagDisplay.kill() }

    func postFitNotification(title: String, body: String, fit: Bool) {
        FitNotification.shared.post(mac.server, title: title, body: body, fit: fit)
    }

    func removeFitNotification() { FitNotification.shared.remove() }

    func setCursorHidden(_ hidden: Bool) {
        if hidden { CursorHider.hide() } else { CursorHider.show() }
    }

    func setCursor(_ name: String?) {
        // mango's default cursor where no client is: the port's own windows (its panels) set their own
        if name == "default" && NSApp.isActive { return }
        CursorHider.setCursor(name)
    }

    func scenePanel(frame: CGRect, look: SceneDrawing.Look,
                    capture: @escaping ([ClientID], @escaping (ClientID, CGImage, CGSize) -> Void) -> Void,
                    icon: @escaping (ClientID) -> NSImage?,
                    layoutIcon: @escaping (LayoutKind) -> CGImage?,
                    windowSizes: @escaping (ClientID) -> SceneDrawing.WindowSize?) -> any ScenePanelDrawing {
        ScenePanel(frame: frame, look: look, capture: capture, icon: icon, layoutIcon: layoutIcon, windowSizes: windowSizes)
    }
}
