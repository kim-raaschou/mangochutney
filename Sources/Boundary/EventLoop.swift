@MainActor
public protocol EventLoop: AnyObject {
    func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource
    func addTimer(_ fire: @escaping @MainActor () -> Void) -> EventSource
    /// wl_event_loop_add_idle: runs once the events at hand are handled; nil where it cannot.
    func addIdle(_ fire: @escaping @MainActor () -> Void) -> EventSource?
}

@MainActor
public protocol EventSource: AnyObject {
    func remove()
    func timerUpdate(_ msDelay: Int32)
}
