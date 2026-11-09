import XCTest
@testable import Mango
@testable import Port

@MainActor
final class StaleFocusTests: MangoTestCase {
    func testAFocusRequestIsDroppedWhenMangoHasMovedOn() {
        let r = EngineRig()
        let a = r.window(1), b = r.window(2)
        r.server.arrange(r.monitor, .none)
        r.server.clientFocus(b)
        XCTAssertTrue(MacWindowSystem.stillFocused(b, in: r.server))
        r.server.mac.windowFocused(id: a.id)
        XCTAssertTrue(r.server.focused === a, "mango follows macOS")
        XCTAssertFalse(MacWindowSystem.stillFocused(b, in: r.server), "the request for b is stale")
    }

    func testAFocusRequestForAGoneWindowIsDropped() {
        let r = EngineRig()
        let a = r.window(1)
        r.server.arrange(r.monitor, .none)
        r.server.clientFocus(a)
        r.server.handleClientUnmap(a)
        r.server.handleClientDestroy(a)
        XCTAssertFalse(MacWindowSystem.stillFocused(a, in: r.server))
    }
}

final class RaiseQueueTests: XCTestCase {
    func testOnlyTheLatestRaiseWaitingIsDone() {
        let q = AXWriteQueue(pid: getpid())
        let a = AXUIElementCreateApplication(1), b = AXUIElementCreateApplication(2)
        var raised: [AXUIElement] = []
        q.performRaise = { raised.append($0) }
        let busy = DispatchSemaphore(value: 0)
        q.async { busy.wait() }
        q.raise(a)
        q.raise(b)
        busy.signal()
        q.sync {}
        XCTAssertEqual(raised.count, 1, "the raise of a was overtaken while the app was busy")
        XCTAssertTrue(raised.first.map { CFEqual($0, b) } ?? false)
        q.raise(a)
        q.sync {}
        XCTAssertEqual(raised.count, 2)
    }
}
