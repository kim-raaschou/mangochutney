import AppKit
import Mango

/// wlroots' output frame events: on each scheduled monitor's next frame the port calls mango's
/// handle_output_frame. The display link runs only while a frame is scheduled; it is the screen's
/// refresh, not a timer (a timer stands in where there is no screen).
@MainActor
final class FrameClock {
    private unowned let server: MangoServer
    private var scheduled: Set<CGDirectDisplayID> = []
    private var link: CADisplayLink?
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
    var animationsRunning: Bool { server.clientsAll.contains { $0.animation.running } }

    /// wlr_output_schedule_frame.
    func schedule(_ m: Monitor) {
        scheduled.insert(m.screen.displayID)
        start()
    }

    /// The body runs once no client is moving.
    func whenIdle(_ body: @escaping () -> Void) {
        if !animationsRunning { body() } else { idleWaiters.append(body) }
    }

    func screensChanged() {
        guard link != nil else { return }
        link?.invalidate(); link = nil
        if !scheduled.isEmpty { start() }
    }

    func stop() {
        scheduled.removeAll()
        link?.invalidate(); link = nil
        timer?.cancel(); timer = nil
    }

    func fire() {
        let due = scheduled
        scheduled.removeAll()
        for m in server.monitors where due.contains(m.screen.displayID) {
            server.handleOutputFrame(m)
        }
        commit?()
        guard scheduled.isEmpty else { return }
        link?.invalidate(); link = nil
        timer?.cancel(); timer = nil
        if !animationsRunning && !idleWaiters.isEmpty {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for w in waiters { w() }
        }
    }

    private func start() {
        guard !manual, link == nil, timer == nil else { return }
        if let screen = NSScreen.screens.first {
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
