import Dispatch
import Mango

@MainActor
final class MainEventLoop: EventLoop {
    func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { readable() } }
        source.resume()
        return Source(source)
    }

    /// wl_event_loop_add_timer: disarmed until timerUpdate arms it; 0 disarms it.
    func addTimer(_ fire: @escaping @MainActor () -> Void) -> EventSource {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .distantFuture)
        source.setEventHandler { MainActor.assumeIsolated { fire() } }
        source.resume()
        return Timer(source)
    }

    /// wl_event_loop_add_idle: the main queue's next turn.
    func addIdle(_ fire: @escaping @MainActor () -> Void) -> EventSource? {
        let idle = Idle()
        DispatchQueue.main.async { MainActor.assumeIsolated { if !idle.removed { fire() } } }
        return idle
    }

    final class Idle: EventSource {
        var removed = false
        func remove() { removed = true }
        func timerUpdate(_ msDelay: Int32) {}
    }

    final class Source: EventSource {
        let source: DispatchSourceRead
        init(_ source: DispatchSourceRead) { self.source = source }
        func remove() { source.cancel() }
        func timerUpdate(_ msDelay: Int32) {}
    }

    final class Timer: EventSource {
        let source: DispatchSourceTimer
        init(_ source: DispatchSourceTimer) { self.source = source }
        func remove() { source.cancel() }
        func timerUpdate(_ msDelay: Int32) {
            source.schedule(deadline: msDelay > 0 ? .now() + .milliseconds(Int(msDelay)) : .distantFuture)
        }
    }
}
