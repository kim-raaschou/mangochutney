import AppKit
import ApplicationServices
import Mango

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
        var unseen = false
        var completion: (() -> Void)?
        var generation: Int
    }

    private var jobs: [CGWindowID: Job] = [:]
    private var shown: [CGWindowID: CGRect] = [:]
    private var reporting: [CGWindowID: Int] = [:]
    private var nextGeneration = 0
    private var bordersScheduled = false
    private var link: CADisplayLink?
    private var timer: DispatchSourceTimer?
    private lazy var linkTarget = DisplayLinkTarget { [weak self] in self?.tick() }
    public var fps: Double = 60
    public var onFrame: (([CGWindowID: CGRect]) -> Void)?

    public init() {}

    public func isAnimating(_ id: CGWindowID) -> Bool { jobs[id] != nil }

    public private(set) var holding = false

    public func hold() { holding = true }

    public func setProgress(_ p: Double) {
        guard holding else { return }
        for (id, job) in jobs where !job.unseen {
            let rect = CGRect.lerp(job.from, job.to, CGFloat(job.curve.findAnimationCurveAt(at: p))).rounded()
            job.queue.setFrame(job.element, id: id, frame: rect, setSize: job.from.size != job.to.size,
                               animating: job.from.size != job.to.size,
                               written: reporter(id, job.generation, final: false))
        }
    }

    public func resume(from p: Double) {
        guard holding else { return }
        holding = false
        let now = CACurrentMediaTime()
        for id in jobs.keys { jobs[id]!.start = now - p * jobs[id]!.duration }
        if !jobs.isEmpty { ensureTimer() }
    }

    public func letGo() {
        guard holding else { return }
        holding = false
        for id in jobs.keys { jobs[id]!.start = 0 }
        if !jobs.isEmpty { ensureTimer() }
    }
    public var isActive: Bool { !jobs.isEmpty }
    private var idleWaiters: [() -> Void] = []

    public func whenIdle(_ body: @escaping () -> Void) {
        if jobs.isEmpty { body() } else { idleWaiters.append(body) }
    }

    private func flushIdleWaiters() {
        guard jobs.isEmpty, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for w in waiters { w() }
    }

    public func shownRect(_ id: CGWindowID) -> CGRect? { shown[id] }

    public func covered(_ id: CGWindowID) -> CGRect? {
        guard let j = jobs[id] else { return nil }
        if j.unseen { return j.from }
        let e = j.curve.extremes
        return CGRect.lerp(j.from, j.to, CGFloat(e.low)).rounded()
            .intersection(CGRect.lerp(j.from, j.to, CGFloat(e.high)).rounded())
    }

    public func currentRect(_ id: CGWindowID) -> CGRect? {
        guard let j = jobs[id] else { return nil }
        if j.unseen { return j.from }
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
        shown[id] = start
        if waitingAt != nil { ensureTimer(); return }
        queue.setFrame(element, id: id, frame: start, setSize: start.size != to.size,
                       written: reporter(id, generation, final: false))
        ensureTimer()
    }

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

    private func written(_ id: CGWindowID, _ generation: Int, _ rect: CGRect, final: Bool) {
        guard reporting[id] == generation else { return }
        if final {
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
            var writeSize = job.from.size != job.to.size
            if t >= 1 {
                rect = job.to
                writeSize = true
                finished.append(id)
            }
            job.queue.setFrame(job.element, id: id, frame: rect, setSize: writeSize, animating: writeSize && t < 1,
                               written: reporter(id, job.generation, final: t >= 1))
        }
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

@MainActor
private final class DisplayLinkTarget: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func fire() { body() }
}

extension CGRect {
    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}
