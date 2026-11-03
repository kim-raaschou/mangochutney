import XCTest
import ApplicationServices
@testable import Mango
@testable import Port

/// Borders follow the frames an app has been given, not the frames computed for "now".
/// The writes go to pid 0, which AX rejects at once, so the queue runs at full speed and
/// every write still reports back.
@MainActor
final class AnimatorBorderTests: MangoTestCase {
    let element = AXUIElementCreateApplication(0)

    func testWriteReportsItsFrameOnTheMainThread() {
        let q = AXWriteQueue(pid: 0)
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        let done = expectation(description: "written")
        q.setFrame(element, id: 1, frame: r) { rect in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(rect, r)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testOvertakenReportMovesToTheNewerWrite() {
        let q = AXWriteQueue(pid: 0)
        let gate = DispatchSemaphore(value: 0)
        q.async { gate.wait() }   // hold the queue so the writes below coalesce
        let carried = expectation(description: "report carried to the newer write")
        let replaced = expectation(description: "a report replaced by a newer one")
        replaced.isInverted = true
        let newest = expectation(description: "newest report")
        let r2 = CGRect(x: 2, y: 2, width: 2, height: 2)
        q.setFrame(element, id: 1, frame: .zero) { rect in XCTAssertEqual(rect, r2); carried.fulfill() }
        q.setFrame(element, id: 1, frame: r2)                       // no report of its own
        q.setFrame(element, id: 2, frame: .zero) { _ in replaced.fulfill() }
        q.setFrame(element, id: 2, frame: r2) { _ in newest.fulfill() }
        gate.signal()
        wait(for: [carried, newest, replaced], timeout: 1)
    }

    func testBorderStartsWhereTheWindowIsAndEndsOnTheClientFrame() {
        let animator = Animator()
        let q = AXWriteQueue(pid: 0)
        let from = CGRect(x: 0, y: 0, width: 400, height: 300)
        let to = CGRect(x: 800, y: 0, width: 400, height: 300)
        var reported: [CGRect] = []
        animator.onFrame = { frames in if let f = frames[7] { reported.append(f) } }
        let finished = expectation(description: "animation done")
        animator.animate(id: 7, element: element, queue: q, from: from, to: to, durationMs: 120,
                         curve: .mangoDefault) { finished.fulfill() }
        XCTAssertEqual(animator.shownRect(7), from, "before any write lands the border stays at the start")
        wait(for: [finished], timeout: 2)
        // Let the final write report back.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertNil(animator.shownRect(7), "after the last write the border uses the client's frame")
        XCTAssertFalse(reported.isEmpty)
        for f in reported {
            XCTAssertTrue(f.minX >= from.minX && f.minX <= to.minX, "reported frame \(f) outside the animation")
        }
    }

    func testReportsOfACancelledAnimationAreDropped() {
        let animator = Animator()
        let q = AXWriteQueue(pid: 0)
        let gate = DispatchSemaphore(value: 0)
        q.async { gate.wait() }   // the initial write is still in the queue when we cancel
        animator.animate(id: 3, element: element, queue: q, from: .zero,
                         to: CGRect(x: 500, y: 0, width: 10, height: 10), durationMs: 200, curve: .mangoDefault)
        animator.cancel(3)
        XCTAssertNil(animator.shownRect(3))
        gate.signal()
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
        XCTAssertNil(animator.shownRect(3), "a late report of a cancelled animation must not move the border")
    }

    func testRestartBeginsFromTheLastWrittenFrame() {
        let animator = Animator()
        let q = AXWriteQueue(pid: 0)
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 1000, y: 0, width: 100, height: 100)
        animator.animate(id: 5, element: element, queue: q, from: a, to: b, durationMs: 400, curve: .mangoDefault)
        let mid = expectation(description: "some frames written")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { mid.fulfill() }
        wait(for: [mid], timeout: 1)
        let shown = animator.shownRect(5)
        XCTAssertNotNil(shown)
        animator.animate(id: 5, element: element, queue: q, from: a, to: CGRect(x: 200, y: 0, width: 100, height: 100),
                         durationMs: 400, curve: .mangoDefault)
        XCTAssertEqual(animator.shownRect(5), shown, "a new animation starts where the window was last put")
        animator.cancelAll()
    }
}
