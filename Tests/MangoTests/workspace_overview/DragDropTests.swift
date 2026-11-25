import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/workspace_overview/drag_drop.c
@MainActor
final class DragDropTests: XCTestCase {

    // MARK: wsov_finish_drop

    /// What facit cannot show: a virtual keyboard's Ctrl and Shift do not count (keyboard_hard_modifiers).
    /// Tag 1's card is at 5,1 and tag 2's at 643,1, 633x356 each (the 3x3 grid on 1920x1080, gap 5).
    func dragBToTag2(_ mods: Modifiers) -> TestMango {
        let mango = TestMango("new_is_master=0")
        mango.map("a")
        mango.map("b")
        mango.run("toggleworkspaceoverview", "all")
        mango.wlroots.modifiers = mods

        mango.pointer(to: CGPoint(x: 480, y: 180))
        mango.button(0, down: true)
        mango.pointer(to: CGPoint(x: 500, y: 180))
        mango.pointer(to: CGPoint(x: 960, y: 180))
        mango.button(0, down: false)
        return mango
    }

    func testAPlainDropMovesTheWindowFromItsTagToTheTarget() {
        let mango = dragBToTag2([])

        XCTAssertEqual(mango.client("b").tags, 0b10)
        XCTAssertEqual(mango.viewedTags, 0b10, "the overview views the tag it was dropped on")
    }

    func testACtrlDropPutsTheWindowOnTheTargetOnly() {
        let mango = TestMango("new_is_master=0")
        mango.map("a")
        mango.map("b")
        mango.run("tag", "5")   // b on tag 5, a is left on tag 1
        mango.run("view", "1")
        mango.run("toggletag", ["1"], on: mango.client("b"))   // b on tags 1 and 5
        mango.run("toggleworkspaceoverview", "all")
        mango.wlroots.modifiers = .ctrl

        mango.pointer(to: CGPoint(x: 480, y: 180))
        mango.button(0, down: true)
        mango.pointer(to: CGPoint(x: 500, y: 180))
        mango.pointer(to: CGPoint(x: 960, y: 180))
        mango.button(0, down: false)

        XCTAssertEqual(mango.client("b").tags, 0b10, "c->tags = target_bit")
    }

    func testAShiftDropAddsTheTargetTag() {
        let mango = dragBToTag2(.shift)

        XCTAssertEqual(mango.client("b").tags, 0b11, "c->tags |= target_bit")
    }

    /// Not mango's own detail: the port has no live surfaces, so a card's buffer must show the window dropped
    /// on an empty tag at once, as mango's live surface does.
    func testAWindowDroppedOnAnEmptyTagIsShownInItsCard() {
        let mango = TestMango("new_is_master=0")
        mango.map("a")
        mango.map("b")
        mango.run("toggleworkspaceoverview", "all")

        mango.pointer(to: CGPoint(x: 480, y: 180))
        mango.button(0, down: true)
        mango.pointer(to: CGPoint(x: 500, y: 180))
        mango.pointer(to: CGPoint(x: 960, y: 540))
        mango.button(0, down: false)

        let card = wsov.cells.first { $0.tag == 5 }!
        XCTAssertEqual(card.contents.buffer?.items.map(\.client), [mango.client("b").windowID])
        XCTAssertTrue(card.contents.enabled)
    }
}
