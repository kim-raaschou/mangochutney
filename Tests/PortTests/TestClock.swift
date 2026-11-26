import Foundation
@testable import Port

/// The port's time in the tests: it moves only when the test steps it, and the timers due by then run in
/// their order.
@MainActor
final class TestClock: PortClock {
    private(set) var now: TimeInterval = 1000
    private var due: [(at: TimeInterval, order: Int, timer: PortTimer, body: @MainActor () -> Void)] = []
    private var order = 0

    @discardableResult
    func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) -> PortTimer {
        let timer = PortTimer()
        order += 1
        due.append((now + max(0, seconds), order, timer, body))
        return timer
    }

    /// The clock moved on by `seconds`; each timer due runs at its time.
    func advance(by seconds: TimeInterval) {
        let end = now + seconds
        while let next = due.enumerated().filter({ $0.element.at <= end }).min(by: { ($0.element.at, $0.element.order) < ($1.element.at, $1.element.order) }) {
            due.remove(at: next.offset)
            now = max(now, next.element.at)
            if !next.element.timer.isCancelled { next.element.body() }
        }
        now = end
    }
}
