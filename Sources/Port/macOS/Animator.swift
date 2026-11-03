import AppKit
import ApplicationServices
import Mango

/// Animates window frames by writing the AX frame every display frame, size
/// included, like mango's compositor animation. (This only works because
/// `AXWriteQueue` switches AXEnhancedUserInterface off: with it on, apps finish
/// each resize late with a stale position and the window jumps.) A window whose size
/// changes gets its position and size on every frame; an app that resizes slowly gets
/// fewer frames.
///
/// Borders follow the frames the app has been given (`AXWriteQueue` reports each write
/// back), not the frames computed for "now": a slow app (Ghostty's 12 ms per resize) is
/// a frame or more behind the computation, and a border drawn from it would run ahead.
@MainActor
public final class Animator {
    public struct Job {
        var element: AXUIElement
        var queue: any WindowWriter
        var from: CGRect
        var to: CGRect
        var start: TimeInterval
        var duration: TimeInterval
        var curve: BezierCurve
        /// No one sees the window on the way: it waits where it was put, without frames, and
        /// takes its target with the last frame.
        var unseen = false
        var completion: (() -> Void)?
        /// Writes of this animation report back only while it is the window's current one.
        var generation: Int
    }

    private var jobs: [CGWindowID: Job] = [:]
    /// Last frame written per animating window (reported by the write queue); kept until
    /// the animation's final frame has been written.
    private var shown: [CGWindowID: CGRect] = [:]
    /// The animation generation whose writes are reported, per window.
    private var reporting: [CGWindowID: Int] = [:]
    private var nextGeneration = 0
    private var bordersScheduled = false
    /// Frames come from the display's refresh (vsync): written in step with what the screen
    /// shows, not drifting against it as a free-running timer does (an uneven step now and
    /// then). A timer only without a screen to follow.
    private var link: CADisplayLink?
    private var timer: DispatchSourceTimer?
    private lazy var linkTarget = DisplayLinkTarget { [weak self] in self?.tick() }
    /// At most this many frames a second (each one an Accessibility write to every app
    /// animating; a 120 Hz screen would double that).
    public var fps: Double = 60
    /// Called (at most once per main run-loop turn) after animation frames were written,
    /// with the written frame of each animating window (borders follow).
    public var onFrame: (([CGWindowID: CGRect]) -> Void)?

    public init() {}

    public func isAnimating(_ id: CGWindowID) -> Bool { jobs[id] != nil }

    /// mango's swipe_drive_freeze: animations wait for the fingers instead of the clock;
    /// setProgress writes each where the fingers have it.
    public private(set) var holding = false

    public func hold() { holding = true }

    /// client_animation_set_progress: every animation at `p` of its way (on its curve).
    public func setProgress(_ p: Double) {
        guard holding else { return }
        for (id, job) in jobs where !job.unseen {
            let rect = CGRect.lerp(job.from, job.to, CGFloat(job.curve.findAnimationCurveAt(at: p))).rounded()
            job.queue.setFrame(job.element, id: id, frame: rect, setSize: job.from.size != job.to.size,
                               animating: job.from.size != job.to.size,
                               written: reporter(id, job.generation, final: false))
        }
    }

    /// client_animation_resume: the animations run on from `p`, for the rest of their time.
    public func resume(from p: Double) {
        guard holding else { return }
        holding = false
        let now = CACurrentMediaTime()
        for id in jobs.keys { jobs[id]!.start = now - p * jobs[id]!.duration }
        if !jobs.isEmpty { ensureTimer() }
    }

    /// The fingers undid the transition: what comes next starts from where the windows
    /// were last put (their shown frames); anything left finishes at once.
    public func letGo() {
        guard holding else { return }
        holding = false
        for id in jobs.keys { jobs[id]!.start = 0 }
        if !jobs.isEmpty { ensureTimer() }
    }
    public var isActive: Bool { !jobs.isEmpty }
    private var idleWaiters: [() -> Void] = []

    /// Runs `body` once no window is animating: now, or when the last animation ends
    /// (or is cancelled; then on the next main-queue turn, since a cancel happens inside
    /// `place` during an arrange, which a waiter must not re-enter).
    public func whenIdle(_ body: @escaping () -> Void) {
        if jobs.isEmpty { body() } else { idleWaiters.append(body) }
    }

    private func flushIdleWaiters() {
        guard jobs.isEmpty, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for w in waiters { w() }
    }

    /// Where the window is during an animation: the last frame its app was given. Nil when
    /// the window is not animating or its final frame has been written.
    public func shownRect(_ id: CGWindowID) -> CGRect? { shown[id] }

    /// Inside every frame the window is still given before its last one: what it keeps
    /// covered through its animation (nil: not animating). Every frame's edges lie between
    /// those of the frames at the curve's least and most progress (the first and the last,
    /// unless the curve dips back or overshoots).
    public func covered(_ id: CGWindowID) -> CGRect? {
        guard let j = jobs[id] else { return nil }
        if j.unseen { return j.from }
        let e = j.curve.extremes
        return CGRect.lerp(j.from, j.to, CGFloat(e.low)).rounded()
            .intersection(CGRect.lerp(j.from, j.to, CGFloat(e.high)).rounded())
    }

    /// The frame computed for this moment (ahead of the window when its app is slow).
    public func currentRect(_ id: CGWindowID) -> CGRect? {
        guard let j = jobs[id] else { return nil }
        if j.unseen { return j.from }   // it stays there until the last frame
        let t = min(1, (CACurrentMediaTime() - j.start) / j.duration)
        return CGRect.lerp(j.from, j.to, CGFloat(j.curve.findAnimationCurveAt(at: t)))
    }

    public func animate(id: CGWindowID, element: AXUIElement, queue: any WindowWriter, from: CGRect, to: CGRect,
                        durationMs: Int, curve: BezierCurve, waitingAt: CGRect? = nil,
                        completion: (() -> Void)? = nil) {
        if durationMs <= 0 || from == to {
            cancel(id)
            queue.setFrame(element, id: id, frame: to)
            completion?()
            return
        }
        // Start from where the window is: the last frame written by a running animation
        // (its app may lag behind the computed position).
        var start = shown[id] ?? currentRect(id) ?? from
        if let at = waitingAt {
            if at != start { queue.setFrame(element, id: id, frame: at) }
            start = at
        }
        nextGeneration += 1
        let generation = nextGeneration
        jobs[id] = Job(element: element, queue: queue, from: start, to: to, start: CACurrentMediaTime(),
                       duration: Double(durationMs) / 1000, curve: curve, unseen: waitingAt != nil,
                       completion: completion, generation: generation)
        reporting[id] = generation
        shown[id] = start   // borders follow the window, also while it waits
        if waitingAt != nil { ensureTimer(); return }
        // Write the initial frame immediately, with its size only where the size changes on
        // the way: an app lays its window out again for a size write, even of the same size
        // (VS Code 30 ms, Messages 40), and the frames after it waited. The last frame
        // writes the full frame in any case.
        queue.setFrame(element, id: id, frame: start, setSize: start.size != to.size,
                       written: reporter(id, generation, final: false))
        ensureTimer()
    }

    /// Displays came or went: the link may follow a screen that is gone (and then never
    /// fires again). A new one for the running animations.
    public func screensChanged() {
        guard link != nil else { return }
        link?.invalidate(); link = nil
        if !jobs.isEmpty { ensureTimer() }
    }

    public func cancel(_ id: CGWindowID) {
        jobs.removeValue(forKey: id)
        shown.removeValue(forKey: id)
        reporting.removeValue(forKey: id)
        flushIdleWaitersLater()
    }

    public func cancelAll() {
        jobs.removeAll()
        shown.removeAll()
        reporting.removeAll()
        flushIdleWaitersLater()
    }

    private func flushIdleWaitersLater() {
        guard jobs.isEmpty, !idleWaiters.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.flushIdleWaiters() } }
    }

    private func reporter(_ id: CGWindowID, _ generation: Int, final: Bool) -> @MainActor (CGRect) -> Void {
        { [weak self] rect in self?.written(id, generation, rect, final: final) }
    }

    /// A frame of animation `generation` reached the window.
    private func written(_ id: CGWindowID, _ generation: Int, _ rect: CGRect, final: Bool) {
        guard reporting[id] == generation else { return }   // cancelled or restarted since
        if final {
            // The window has its target frame; from now on the border uses the client's frame.
            shown.removeValue(forKey: id)
            reporting.removeValue(forKey: id)
        } else {
            shown[id] = rect
        }
        scheduleBorders()
    }

    private func scheduleBorders() {
        guard !bordersScheduled else { return }
        bordersScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bordersScheduled = false
                self.onFrame?(self.shown)
            }
        }
    }

    private func ensureTimer() {
        guard link == nil, timer == nil else { return }
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
            MainActor.assumeIsolated { self?.tick() }
        }
        t.resume()
        timer = t
    }

    private func tick() {
        if holding { return }
        let now = CACurrentMediaTime()
        var finished: [CGWindowID] = []
        for (id, job) in jobs {
            let t = min(1, (now - job.start) / job.duration)
            if job.unseen && t < 1 { continue }
            let f = CGFloat(job.curve.findAnimationCurveAt(at: t))
            var rect = CGRect.lerp(job.from, job.to, f).rounded()
            // Position only while the size stays the same; always the full frame at the
            // end, since a size written earlier may have been refused or lost.
            var writeSize = job.from.size != job.to.size
            if t >= 1 {
                rect = job.to
                writeSize = true
                finished.append(id)
            }
            job.queue.setFrame(job.element, id: id, frame: rect, setSize: writeSize, animating: writeSize && t < 1,
                               written: reporter(id, job.generation, final: t >= 1))
        }
        // The last frame's report ends the window's `shown`. It always comes: a write to a
        // hung app returns when Accessibility gives up waiting (AX.messagingTimeout).
        for id in finished {
            jobs.removeValue(forKey: id)?.completion?()
        }
        if jobs.isEmpty {
            link?.invalidate(); link = nil
            timer?.cancel(); timer = nil
            flushIdleWaiters()
        }
    }
}

/// The display link's target (it needs an Objective-C selector).
@MainActor
private final class DisplayLinkTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}

extension CGRect {
    /// A frame between two, as mango's client_animation_next_tick takes it.
    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}
