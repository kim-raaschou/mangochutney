@MainActor
public protocol EventLoop: AnyObject {
    func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource
}

@MainActor
public protocol EventSource: AnyObject {
    func remove()
}
