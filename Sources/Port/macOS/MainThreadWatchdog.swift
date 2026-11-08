import Foundation
import QuartzCore
import Mango

public final class MainThreadWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mango.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var pingSent: CFTimeInterval?
    private var sampled = false
    private var lastSample: CFTimeInterval = 0

    public init() {}

    public func start(interval: TimeInterval = 0.1, logAfterMs: Double = 500) {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick(logAfterMs: logAfterMs) }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    private func tick(logAfterMs: Double) {
        let now = CACurrentMediaTime()
        lock.lock()
        if let sent = pingSent {
            let blocked = now - sent
            let sample = wlrLogGetVerbosity() == .debug && blocked > 0.3 && !sampled && now - lastSample > 30
            if sample { sampled = true; lastSample = now }
            lock.unlock()
            if sample { Self.writeSample(blockedMs: blocked * 1000) }
            return
        }
        pingSent = now
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let sent = self.pingSent ?? CACurrentMediaTime()
            self.pingSent = nil
            self.sampled = false
            self.lock.unlock()
            let ms = (CACurrentMediaTime() - sent) * 1000
            if ms > logAfterMs { wlrLog(.info, String(format: "main thread was blocked for %.0f ms", ms)) }
        }
    }

    private static func writeSample(blockedMs: Double) {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        let path = "/tmp/mango-sample-\(f.string(from: Date())).txt"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        p.arguments = [String(getpid()), "1", "-file", path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            wlrLog(.info, String(format: "main thread blocked for %.0f ms: stack sample in %@", blockedMs, path))
        } catch {
            wlrLog(.error, "main thread blocked for \(Int(blockedMs)) ms; sample failed: \(error)")
        }
    }
}
