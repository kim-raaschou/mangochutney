/// The boundary, not in mango: wl_event_loop's fd sources. mango's IPC hands its sockets to the
/// event loop (wl_event_loop_add_fd); the port watches them on the main thread.
@MainActor
public protocol EventLoop: AnyObject {
    /// wl_event_loop_add_fd: `readable` runs on the main thread when `fd` can be read, or hangs up.
    func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource
}

/// wl_event_source: removed, it is watched no more (the fd stays open).
@MainActor
public protocol EventSource: AnyObject {
    func remove()
}
