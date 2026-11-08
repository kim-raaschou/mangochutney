import XCTest
import CoreGraphics
@testable import Mango
@testable import Port

final class WindowBookTests: MangoTestCase {
    typealias Book = WindowBook<Int, CGWindowID>

    var dead: Set<Int> = []
    var onScreen: Set<CGWindowID> = []
    var popups: Set<CGWindowID> = []
    var subscribeFails: Set<Int> = []
    var subscribed: [Int] = []
    var unsubscribed: [Int] = []
    var classified: [CGWindowID] = []

    var answers: Book.Answers {
        .init(subscribe: { [unowned self] el in subscribed.append(el); return !subscribeFails.contains(el) },
              unsubscribe: { [unowned self] el in unsubscribed.append(el) },
              isInvalid: { [unowned self] el in dead.contains(el) },
              onScreen: { [unowned self] id in onScreen.contains(id) },
              classify: { [unowned self] _, id in classified.append(id); return popups.contains(id) ? nil : id })
    }

    func list(_ ids: CGWindowID...) -> [(CGWindowID, Int)] { ids.map { ($0, Int($0)) } }

    func testANewWindowIsFoundOnceAndSubscribed() {
        var book = Book()
        XCTAssertEqual(book.refresh(listed: list(1, 2), recheck: false, notified: false, answers: answers).found, [1, 2])
        XCTAssertEqual(subscribed, [1, 2])
        XCTAssertTrue(book.refresh(listed: list(1, 2), recheck: true, notified: false, answers: answers).found.isEmpty)
        XCTAssertEqual(classified, [1, 2], "a known window is not classified again")
    }

    func testAWindowNotListedButAliveIsKept() {
        var book = Book()
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        let out = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        XCTAssertTrue(out.gone.isEmpty)
        XCTAssertNotNil(book.windows[1])
    }

    func testADeadElementOfAWindowOnScreenIsAnOrphanUntilListedAgain() {
        var book = Book()
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        dead = [1]; onScreen = [1]
        let asleep = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        XCTAssertEqual(asleep.orphaned, [1])
        XCTAssertTrue(asleep.gone.isEmpty)
        XCTAssertTrue(unsubscribed.isEmpty, "an orphan keeps its registrations (its destroyed notice)")
        XCTAssertTrue(book.refresh(listed: [], recheck: true, notified: false, answers: answers).gone.isEmpty,
                      "no clock: still on screen, still kept")
        let awake = book.refresh(listed: [(1, 101)], recheck: false, notified: false, answers: answers)
        XCTAssertEqual(awake.reacquired.map(\.0), [1])
        XCTAssertEqual(awake.reacquired.first?.1, 101, "the new element")
        XCTAssertTrue(awake.found.isEmpty, "not a new window")
        XCTAssertEqual(book.windows[1], 101)
        XCTAssertEqual(unsubscribed, [1], "the dead element's registrations are dropped")
    }

    func testTheAppsDestroyedNoticeEndsAnOrphan() {
        var book = Book()
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        dead = [1]; onScreen = [1]
        XCTAssertEqual(book.refresh(listed: [], recheck: false, notified: false, answers: answers).orphaned, [1])
        book.forget(1)
        XCTAssertTrue(book.orphans.isEmpty)
        XCTAssertNil(book.windows[1])
        onScreen = []
        XCTAssertTrue(book.refresh(listed: [], recheck: false, notified: false, answers: answers).gone.isEmpty,
                      "reported once, by the notice")
    }

    func testAnOrphanTheWindowServerNoLongerShowsIsGone() {
        var book = Book()
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        dead = [1]; onScreen = [1]
        _ = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        onScreen = []
        let out = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        XCTAssertEqual(out.gone.map(\.0), [1])
        XCTAssertEqual(out.gone.first?.1, .notOnScreen)
        XCTAssertTrue(book.orphans.isEmpty)
    }

    func testADeadElementOfAWindowNotOnScreenIsGoneAtOnce() {
        var book = Book()
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        dead = [1]
        let out = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        XCTAssertEqual(out.gone.map(\.0), [1])
        XCTAssertEqual(out.gone.first?.1, .elementInvalid)
        XCTAssertNil(book.windows[1])
    }

    func testARejectedWindowIsRecheckedFiveTimesByRescansAndAlwaysWhenNotified() {
        var book = Book()
        popups = [7]
        _ = book.refresh(listed: list(7), recheck: false, notified: false, answers: answers)
        XCTAssertEqual(classified, [7])
        _ = book.refresh(listed: list(7), recheck: false, notified: false, answers: answers)
        XCTAssertEqual(classified.count, 1, "without recheck: left alone")
        for _ in 0..<8 { _ = book.refresh(listed: list(7), recheck: true, notified: false, answers: answers) }
        XCTAssertEqual(classified.count, 1 + Book.maxRechecks, "a rescan's budget")
        _ = book.refresh(listed: list(7), recheck: true, notified: true, answers: answers)
        XCTAssertEqual(classified.count, 2 + Book.maxRechecks, "the app's own notification always rechecks")
        popups = []
        _ = book.refresh(listed: list(7), recheck: true, notified: true, answers: answers)
        XCTAssertNotNil(book.windows[7], "built by now: found")
        XCTAssertNil(book.rejected[7])
    }

    func testARejectedWindowThatIsNoLongerListedIsForgotten() {
        var book = Book()
        popups = [7]
        _ = book.refresh(listed: list(7), recheck: false, notified: false, answers: answers)
        _ = book.refresh(listed: [], recheck: false, notified: false, answers: answers)
        XCTAssertNil(book.rejected[7])
    }

    func testAFailedSubscriptionIsRetriedWhileListed() {
        var book = Book()
        subscribeFails = [1]
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        XCTAssertTrue(book.unsubscribed.contains(1))
        subscribeFails = []
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        XCTAssertFalse(book.unsubscribed.contains(1))
        XCTAssertEqual(subscribed, [1, 1])
    }

    func testForgetDropsADestroyedWindow() {
        var book = Book()
        subscribeFails = [1]
        _ = book.refresh(listed: list(1), recheck: false, notified: false, answers: answers)
        book.forget(1)
        XCTAssertNil(book.windows[1])
        XCTAssertFalse(book.unsubscribed.contains(1))
    }

    func testADeadElementIsAClosedWindowWhenTheAppListsOthers() {
        var book = Book()
        _ = book.refresh(listed: list(1, 2), recheck: false, notified: false, answers: answers)
        dead = [1]; onScreen = [1, 2]
        let out = book.refresh(listed: list(2), recheck: false, notified: false, answers: answers)
        XCTAssertEqual(out.gone.map(\.0), [1], "the app answers: window 1 is closed")
        XCTAssertTrue(out.orphaned.isEmpty)
    }

    func testAnOrphanIsGoneWhenItsAppListsWindowsAgainWithoutIt() {
        var book = Book()
        _ = book.refresh(listed: list(1, 2), recheck: false, notified: false, answers: answers)
        dead = [1, 2]; onScreen = [1, 2]
        XCTAssertEqual(Set(book.refresh(listed: [], recheck: false, notified: false, answers: answers).orphaned), [1, 2])
        let awake = book.refresh(listed: [(2, 102)], recheck: false, notified: false, answers: answers)
        XCTAssertEqual(awake.reacquired.map(\.0), [2])
        XCTAssertEqual(awake.gone.map(\.0), [1], "the app is back and did not list it")
    }
}
