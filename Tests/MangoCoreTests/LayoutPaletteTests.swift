import XCTest
@testable import Mango
@testable import Port

/// The layout palette (chutney_toggle_layout_palette, port extension): its grid, its keys and
/// chutney_layout_palette_keys.
final class LayoutPaletteTests: MangoTestCase {
    func testGridHoldsEveryLayoutOnce() {
        let all = LayoutPaletteGrid(selecting: .tile).cells.flatMap { $0 }.compactMap { $0 }
        XCTAssertEqual(all.count, LayoutKind.allCases.count)
        XCTAssertEqual(Set(all), Set(LayoutKind.allCases))
    }

    func testOpensOnTheLayoutInViewAndStopsAtEdges() {
        var g = LayoutPaletteGrid(selecting: .verticalDeck)
        XCTAssertEqual(g.selected, .verticalDeck)
        g.move(0, -1); XCTAssertEqual(g.selected, .deck)
        g.move(0, -1); XCTAssertEqual(g.selected, .deck)
        g.move(1, 0); XCTAssertEqual(g.selected, .fair)
        g.move(1, 0); XCTAssertEqual(g.selected, .fair)
        g.move(0, 1); g.move(0, 1)   // the empty cell stops it
        XCTAssertEqual(g.selected, .verticalFair)
    }

    func testCircleLayoutInItsOrderFiveARow() {
        var g = LayoutPaletteGrid(circle: ["tile", "monocle"], selecting: .monocle)
        XCTAssertEqual(g.cells, [[.tile, .monocle]])
        XCTAssertEqual(g.width, 2)
        XCTAssertEqual(g.selected, .monocle)
        g.move(-1, 0); XCTAssertEqual(g.selected, .tile)
        g.move(0, 1); XCTAssertEqual(g.selected, .tile, "one row")
        let six = ["scroller", "tile", "grid", "deck", "fair", "dwindle"]
        g = LayoutPaletteGrid(circle: six, selecting: .dwindle)
        XCTAssertEqual(g.cells, [[.scroller, .tile, .grid], [.deck, .fair, .dwindle]], "even rows")
        XCTAssertEqual(g.selected, .dwindle)
        g.move(1, 0); XCTAssertEqual(g.selected, .dwindle, "stops at the row's end")
        g.move(0, -1); XCTAssertEqual(g.selected, .grid)
    }

    func testAShorterRowIsCentredForUpAndDown() {
        var g = LayoutPaletteGrid(circle: ["tile", "scroller", "grid", "deck", "fair", "dwindle", "monocle"], selecting: .deck)
        XCTAssertEqual(g.cells.map(\.count), [4, 3])
        g.move(0, 1); XCTAssertEqual(g.selected, .monocle, "the last of three stands under the last of four")
        g.move(0, -1); XCTAssertEqual(g.selected, .deck)
        g = LayoutPaletteGrid(circle: ["tile", "scroller", "grid", "deck", "fair", "dwindle", "monocle"], selecting: .tile)
        g.move(0, 1); XCTAssertEqual(g.selected, .fair)
    }

    func testTicksAreCircleLayout() {
        XCTAssertTrue(CircleLayout.contains([], .grid), "without circle_layout every layout is in")
        XCTAssertEqual(CircleLayout.toggled(["tile", "monocle"], .grid), ["tile", "monocle", "grid"], "last in the round")
        XCTAssertEqual(CircleLayout.toggled(["tile", "monocle"], .tile), ["monocle"])
        XCTAssertNil(CircleLayout.toggled(["monocle"], .monocle), "the last one stays")
        XCTAssertEqual(CircleLayout.toggled([], .tile)?.count, LayoutKind.allCases.count - 1)
    }

    func testCircleLayoutWithoutTheLayoutInViewOrAnyLayout() {
        XCTAssertEqual(LayoutPaletteGrid(circle: ["tile", "monocle"], selecting: .grid).selected, .tile, "the first")
        XCTAssertEqual(LayoutPaletteGrid(circle: ["nope", "tile", "tile"], selecting: .tile).cells, [[.tile]])
        XCTAssertEqual(LayoutPaletteGrid(circle: ["nope"], selecting: .tile).cells, LayoutPaletteGrid.all, "none: all 14")
    }

    func testArrowsAlwaysAndConfiguredKeys() {
        let vim = ["h", "j", "k", "l"]
        XCTAssertTrue(LayoutPaletteGrid.direction(keyCode: 123, characters: nil, keys: vim)! == (-1, 0))
        XCTAssertTrue(LayoutPaletteGrid.direction(keyCode: 4, characters: "h", keys: vim)! == (-1, 0))
        XCTAssertTrue(LayoutPaletteGrid.direction(keyCode: 38, characters: "j", keys: vim)! == (0, 1))
        XCTAssertTrue(LayoutPaletteGrid.direction(keyCode: 37, characters: "l", keys: vim)! == (1, 0))
        XCTAssertNil(LayoutPaletteGrid.direction(keyCode: 4, characters: "h", keys: ["left", "down", "up", "right"]))
    }

    func testConfigKey() {
        var c = Config()
        XCTAssertEqual(c.chutneyLayoutPaletteKeys, ["left", "down", "up", "right"])
        c = ConfigParser.parse(text: "chutney_layout_palette_keys=h,j,k,l\nbind=SUPER,l,chutney_toggle_layout_palette\n", baseDirectory: nil, fileName: "t").config
        XCTAssertEqual(c.chutneyLayoutPaletteKeys, ["h", "j", "k", "l"])
        XCTAssertTrue(c.keyBindings.contains { $0.dispatch.name == "chutney_toggle_layout_palette" })
    }
}
