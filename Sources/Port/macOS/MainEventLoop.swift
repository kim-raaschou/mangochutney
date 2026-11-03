import Dispatch
import Mango

/// Not in mango: wl_event_loop's fd sources on macOS, a read source on the main queue.
@MainActor
final class MainEventLoop: EventLoop {
    func addFd(_ fd: Int32, _ readable: @escaping @MainActor () -> Void) -> EventSource {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { readable() } }
        source.resume()
        return Source(source)
    }

    final class Source: EventSource {
        let source: DispatchSourceRead
        init(_ source: DispatchSourceRead) { self.source = source }
        func remove() { source.cancel() }
    }
}
