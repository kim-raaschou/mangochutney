import Foundation
import CoreGraphics

@MainActor
package protocol WindowSystem: AnyObject {
    var pointer: CGPoint { get }
    func quit()
    func focus(_ c: Client, raise: Bool)
    func warp(to p: CGPoint)
    func restack()
    func drawBorders(_ specs: [BorderSpec])
    func drawTabBars(_ strips: [TabStrip], style: TabStripStyle)
    func drawGroupBars(_ strips: [TabStrip], style: TabStripStyle)
    var windowCornerRadius: CGFloat { get }
    func showOverview(_ cards: [OverviewCard], on m: Monitor, look: OverviewLook)
    func updateOverview(_ cards: [OverviewCard])
    func captureOverviewCards(scale: CGFloat)
    func closeOverview()
    func showJumpLabels(_ labels: [(String, CGRect)], look: DecorateStyle)
    func closeJumpLabels()
    func showSwitcher(panel: CGRect, tiles: [SwitcherTile], look: SwitcherLook, scale: CGFloat)
    func highlightSwitcher(_ tiles: [SwitcherTile])
    func closeSwitcherPanel()
    func showTitleMessageBar(frame: CGRect, title: String, appid: String, look: DecorateStyle)
    func hideTitleMessageBar()
    func showSpecialDim(on m: Monitor, alpha: Double?, over: Set<ClientID>)
    func showDropArea(_ area: CGRect?, color: RGBA)
    func nagSpawn(_ argv: [String], input: String)
    func nagKill()
    func setCursorHidden(_ hidden: Bool)
    func setCursor(_ name: String?)
    func surfaceAt(_ p: CGPoint) -> ClientID?
    func raise(_ c: Client)
    func unminimize(_ c: Client)
    func prepare()
    func startWatching()
    func shutdown()
    var eventLoop: EventLoop { get }
    func rescan()
    func spawn(_ command: String)
    func spawnShell(_ command: String)
    func watchConfig(_ files: [URL])
    func cancelAnimation(_ id: ClientID)
    func animatedFrame(_ id: ClientID) -> CGRect?
    func whenAnimationsIdle(_ body: @escaping () -> Void)
    var animationsActive: Bool { get }
    func holdAnimations()
    func setAnimationProgress(_ p: Double)
    func resumeAnimations(from p: Double)
    func letGoAnimations()
    var canCapture: Bool { get }
    func askToCapture()
    var modifiers: Modifiers { get }
    var screens: [Screen] { get }
    func allWindowIDs() -> Set<ClientID>
    func setKeyboardOptions(_ options: String)
    var keyboardLayout: String { get }
    var mouseButtons: Int { get }
    func startInput()
    func watchGestures(_ on: Bool)
    func keyboardCancelPendingReleaseBind()
    func publishInput(_ state: InputState)
    func publishGlobalKeys(_ keys: [GlobalKey])
    func resize(_ placements: [(Client, CGRect)], _ anim: ArrangeAnimation, rising: Set<ClientID>)
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation, cover: CGRect?, now: CGRect?)
    func hide(_ c: Client)
    func hide(_ c: Client, tagout: TagoutAnimation)
    func keepHidden(_ c: Client, seenAt actual: CGRect?)
    func keepPlaced(_ c: Client, at target: CGRect)
    func settle(_ c: Client)
    func setFrame(_ c: Client, _ frame: CGRect, size: Bool)
    func readFrame(_ c: Client, _ done: @escaping @MainActor (CGRect?) -> Void)
    func clientSendClose(_ c: Client)
    func keepOnDisplay(_ frame: CGRect, _ m: Monitor) -> CGRect
    func grabBegan(_ c: Client)
    func grabEnded(_ c: Client)
}

package extension WindowSystem {
    func resize(_ c: Client, to frame: CGRect, _ anim: ArrangeAnimation) {
        resize(c, to: frame, anim, cover: nil, now: nil)
    }
}
