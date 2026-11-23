import Foundation
import QuartzCore

/// The port's time: now, and a body run once a while from now (a timer). The tests give their own
/// and step it without waiting.
@MainActor
protocol PortClock: AnyObject {
    var now: TimeInterval { get }
    @discardableResult
    func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) -> PortTimer
}

/// A body waiting on a PortClock; cancelled, it does not run.
@MainActor
final class PortTimer {
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

/// The real clock: the host's media time, and the main queue's timers.
final class HostClock: PortClock {
    var now: TimeInterval { CACurrentMediaTime() }

    @discardableResult
    func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) -> PortTimer {
        let timer = PortTimer()
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds)) {
            MainActor.assumeIsolated {
                if !timer.isCancelled { body() }
            }
        }
        return timer
    }
}
