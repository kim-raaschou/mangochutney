import AppKit
import Mango

/// wlroots' output frame events: on each scheduled monitor's next frame the port calls mango's
/// handle_output_frame. The display link runs only while a frame is scheduled; it is the screen's
/// refresh, not a timer (a timer stands in where there is no screen).
@MainActor
final class FrameClock {
    private weak var server: MangoServer?
    private var scheduled: Set<CGDirectDisplayID> = []
    private var link: CADisplayLink?
    /// The display the link follows: gone with its screen, the link is made again on another.
    private var linkDisplay: CGDirectDisplayID?
    private var timer: DispatchSourceTimer?
    private lazy var linkTarget = DisplayLinkTarget { [weak self] in self?.fire() }
    private var idleWaiters: [() -> Void] = []
    var fps: Double = 60
    /// wlroots' output commit: what the frame changed in the scene is shown now.
    var commit: (() -> Void)?
    /// The tests drive the frames themselves (`fire`), with no display link.
    var manual = false

    init(_ server: MangoServer) { self.server = server }

    /// Whether a client is moving: mango's c->animation.running.
    var animationsRunning: Bool { server?.clientsAll.contains { $0.animation.running } ?? false }

    /// wlr_output_schedule_frame.
    func schedule(_ m: Monitor) {
        scheduled.insert(m.screen.displayID)
        if let d = linkDisplay, !NSScreen.screens.contains(where: { Self.displayID($0) == d }) {
            link?.invalidate(); link = nil; linkDisplay = nil
        }
        start(on: m.screen.displayID)
    }

    private static func displayID(_ s: NSScreen) -> CGDirectDisplayID? {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The body runs once no client is moving.
    func whenIdle(_ body: @escaping () -> Void) {
        if !animationsRunning { body() } else { idleWaiters.append(body) }
    }

    func screensChanged() {
        guard link != nil else { return }
        link?.invalidate(); link = nil; linkDisplay = nil
        if let d = scheduled.first { start(on: d) }
    }

    func stop() {
        scheduled.removeAll()
        link?.invalidate(); link = nil; linkDisplay = nil
        timer?.cancel(); timer = nil
    }

    func fire() {
        guard let server else { stop(); return }
        let due = scheduled
        scheduled.removeAll()
        let start = CACurrentMediaTime()
        for m in server.monitors where due.contains(m.screen.displayID) {
            server.handleOutputFrame(m)
        }
        commit?()
        let ms = (CACurrentMediaTime() - start) * 1000
        if ms > 50 { wlrLog(.info, String(format: "slow on the main thread: a frame took %.0f ms", ms)) }
        guard scheduled.isEmpty else { return }
        link?.invalidate(); link = nil; linkDisplay = nil
        timer?.cancel(); timer = nil
        if !animationsRunning && !idleWaiters.isEmpty {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for w in waiters { w() }
        }
    }

    private func start(on display: CGDirectDisplayID) {
        guard !manual, link == nil, timer == nil else { return }
        if let screen = NSScreen.screens.first(where: { Self.displayID($0) == display }) ?? NSScreen.screens.first {
            linkDisplay = Self.displayID(screen)
            let l = screen.displayLink(target: linkTarget, selector: #selector(DisplayLinkTarget.fire))
            let rate = Float(fps)
            l.preferredFrameRateRange = CAFrameRateRange(minimum: rate / 2, maximum: rate, preferred: rate)
            l.add(to: .main, forMode: .common)
            link = l
            return
        }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / fps, leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        t.resume()
        timer = t
    }
}

@MainActor
private final class DisplayLinkTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}
