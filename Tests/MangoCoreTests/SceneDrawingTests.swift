import XCTest
import CoreGraphics
@testable import Mango
@testable import Port

/// SceneDrawing: how the port draws the workspace overview's scene tree. Trees are built as the core builds
/// them (Boundary's wlr_scene functions); no window is made.
@MainActor
final class SceneDrawingTests: XCTestCase {
    let size = CGSize(width: 1000, height: 600)
    let grey = RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1)
    let orange = RGBA(r: 1, g: 0.5, b: 0, a: 1)

    func rect(_ t: WlrSceneTree, _ r: CGRect, _ color: RGBA) -> WlrSceneRect {
        let n = wlrSceneRectCreate(t, Int(r.width), Int(r.height), color)
        wlrSceneNodeSetPosition(n, Int(r.minX), Int(r.minY))
        return n
    }

    func buffer(_ t: WlrSceneTree, _ r: CGRect, items: [WlrBuffer.Item] = []) -> WlrSceneBuffer {
        let n = wlrSceneBufferCreate(t, WlrBuffer(width: Int(r.width), height: Int(r.height),
                                                  background: RGBA(r: 0, g: 0, b: 0, a: 0), items: items))
        wlrSceneNodeSetPosition(n, Int(r.minX), Int(r.minY))
        wlrSceneBufferSetDestSize(n, Int(r.width), Int(r.height))
        return n
    }

    /// A grid card: its frame, four 2-pixel border rects, its buffer inside them.
    func gridCard(_ t: WlrSceneTree, _ f: CGRect) -> (frame: WlrSceneRect, borders: [WlrSceneRect], buffer: WlrSceneBuffer) {
        let frame = rect(t, f, grey)
        let borders = [CGRect(x: f.minX, y: f.minY, width: f.width, height: 2),
                       CGRect(x: f.minX, y: f.maxY - 2, width: f.width, height: 2),
                       CGRect(x: f.minX, y: f.minY, width: 2, height: f.height),
                       CGRect(x: f.maxX - 2, y: f.minY, width: 2, height: f.height)].map { rect(t, $0, orange) }
        return (frame, borders, buffer(t, f.insetBy(dx: 2, dy: 2)))
    }

    func draw(_ t: WlrSceneTree, macOS: Bool = true, badges: [SceneDrawing.Badge] = [],
              windows: @escaping (ClientID) -> SceneDrawing.WindowSize? = { _ in nil }) -> SceneDrawing.DrawList {
        SceneDrawing.draw(t, at: .zero, look: SceneDrawing.Look(size: size, macOS: macOS, windowCornerRadius: 10),
                          badges: badges, windows: windows)
    }

    func style(_ list: SceneDrawing.DrawList, _ node: WlrSceneNode) -> SceneDrawing.Rect? {
        guard case .rect(let r)? = list.nodes.first(where: { $0.id == ObjectIdentifier(node) })?.kind else { return nil }
        return r
    }

    func bufferNode(_ list: SceneDrawing.DrawList, _ node: WlrSceneNode) -> SceneDrawing.Buffer? {
        guard case .buffer(let b)? = list.nodes.first(where: { $0.id == ObjectIdentifier(node) })?.kind else { return nil }
        return b
    }

    // MARK: Cards

    func testAGridCardIsRoundWithItsBorderAsItsFrame() {
        let t = wlrSceneTreeCreate(nil)
        _ = rect(t, CGRect(origin: .zero, size: size), grey)
        let card = gridCard(t, CGRect(x: 10, y: 10, width: 300, height: 180))

        let list = draw(t)

        let frame = style(list, card.frame)
        XCTAssertEqual(frame?.radius, 10)
        XCTAssertEqual(frame?.borderWidth, 2)
        XCTAssertEqual(frame?.borderColor, orange)
        XCTAssertTrue(card.borders.allSatisfy { style(list, $0)?.hidden == true }, "the border rects give way to the frame")
        XCTAssertEqual(bufferNode(list, card.buffer)?.radius, 8, "round within the frame")
    }

    func testAScrollCardWithoutBordersIsRound() {
        let t = wlrSceneTreeCreate(nil)
        let frame = rect(t, CGRect(x: 100, y: 100, width: 800, height: 400), grey)
        let content = buffer(t, CGRect(x: 100, y: 100, width: 800, height: 400))

        let list = draw(t)

        XCTAssertEqual(style(list, frame)?.radius, 10)
        XCTAssertEqual(style(list, frame)?.borderWidth, 0)
        XCTAssertEqual(bufferNode(list, content)?.radius, 10)
    }

    func testTheBackdropAndANeighbourCutAtTheEdgeAreNoBorders() {
        let t = wlrSceneTreeCreate(nil)
        let backdrop = rect(t, CGRect(origin: .zero, size: size), grey)
        let neighbour = rect(t, CGRect(x: 100, y: 0, width: 800, height: 40), grey)   // the card above, cut at the top
        _ = buffer(t, CGRect(x: 100, y: 0, width: 800, height: 40))
        _ = rect(t, CGRect(x: 100, y: 80, width: 800, height: 440), grey)
        _ = buffer(t, CGRect(x: 100, y: 80, width: 800, height: 440))

        let list = draw(t)

        XCTAssertNil(style(list, backdrop)?.color, "under the blur")
        XCTAssertEqual(style(list, backdrop)?.borderWidth, 0, "the backdrop is no card")
        XCTAssertEqual(style(list, neighbour)?.hidden, false, "a cut neighbour is a card, not a border")
    }

    func testMangosLookHasNoCardsAndShowsTheBackdrop() {
        let t = wlrSceneTreeCreate(nil)
        _ = rect(t, CGRect(origin: .zero, size: size), grey)
        let card = gridCard(t, CGRect(x: 10, y: 10, width: 300, height: 180))

        let list = draw(t, macOS: false)

        XCTAssertEqual(list.backdrop, grey)
        XCTAssertEqual(style(list, card.frame)?.radius, 0)
        XCTAssertTrue(card.borders.allSatisfy { style(list, $0)?.hidden == false })
    }

    // MARK: Windows

    func item(_ list: SceneDrawing.DrawList, _ node: WlrSceneNode) -> SceneDrawing.Item? {
        bufferNode(list, node)?.items.first
    }

    func windowBuffer(_ t: WlrSceneTree) -> WlrSceneBuffer {
        buffer(t, CGRect(x: 0, y: 0, width: 400, height: 300),
               items: [WlrBuffer.Item(client: 7, box: CGRect(x: 0, y: 0, width: 400, height: 300), borderX: 2, borderY: 2,
                                      borderColor: orange)])
    }

    func testASmallerWindowIsShownAtItsOwnSizeAndItsRingFollowsIt() {
        let t = wlrSceneTreeCreate(nil)
        let b = windowBuffer(t)

        // its box is 800x600 on the card's tag; the window is 400x300 now: half of its box
        let list = draw(t, windows: { _ in .init(tile: CGSize(width: 800, height: 600), now: CGSize(width: 400, height: 300)) })

        let i = item(list, b)
        XCTAssertEqual(i?.picture, CGRect(x: 2, y: 2, width: 200, height: 150), "top left, not stretched")
        XCTAssertEqual(i?.pictureContents, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(i?.pictureRing, CGRect(x: 0, y: 0, width: 204, height: 154), "around the picture, not the box")
    }

    func testALargerWindowIsCutAtTheRightAndTheBottom() {
        let t = wlrSceneTreeCreate(nil)
        let b = windowBuffer(t)

        let list = draw(t, windows: { _ in .init(tile: CGSize(width: 400, height: 300), now: CGSize(width: 800, height: 600)) })

        let i = item(list, b)
        XCTAssertEqual(i?.picture, i?.inner, "fills its box")
        XCTAssertEqual(i?.pictureContents.width ?? 0, 396.0 / 800, accuracy: 0.001, "its left part, not zoomed")
        XCTAssertEqual(i?.pictureContents.height ?? 0, 296.0 / 600, accuracy: 0.001, "its top part")
    }

    func testTheWindowsCornersScaleWithIt() {
        let t = wlrSceneTreeCreate(nil)
        let b = windowBuffer(t)

        let list = draw(t, windows: { _ in .init(tile: CGSize(width: 800, height: 600), now: CGSize(width: 800, height: 600)) })

        XCTAssertEqual(item(list, b)?.radius, 5, "10 on the screen, the box at half the window's size")
        XCTAssertEqual(item(list, b)?.ringRadius, 7)
    }

    // MARK: Layout icons

    func testALayoutIconStandsOverThePictureAtTheCardsBottomLeft() {
        let t = wlrSceneTreeCreate(nil)
        let card = CGRect(x: 10, y: 20, width: 300, height: 200)

        let list = draw(t, badges: [.init(card: card, kind: .tile, tag: 3),
                                    .init(card: CGRect(x: 0, y: 0, width: 30, height: 20), kind: .grid, tag: 4)])

        let size = SceneDrawing.badgeSize, inset = SceneDrawing.badgeInset
        XCTAssertEqual(list.badges[0].frame, CGRect(x: 10 + inset, y: 220 - inset - size.height, width: size.width, height: size.height))
        XCTAssertEqual(list.badges[0].tag, 3)
        XCTAssertFalse(list.badges[0].hidden)
        XCTAssertTrue(list.badges[1].hidden, "no icon on a card too small for it")
    }

    // MARK: The scene on the monitor

    func testTheSceneIsScaledInsideTheInsetAndThePointerMapsBack() {
        let g = SceneDrawing.Geometry(size: CGSize(width: 1000, height: 1000), inset: .init(top: 100))

        XCTAssertEqual(g.scale, 0.9)
        XCTAssertEqual(g.offset, CGPoint(x: 50, y: 100))
        let card = CGRect(x: 100, y: 200, width: 300, height: 100)
        let onScreen = g.screenBox(card)
        XCTAssertEqual(g.scenePoint(CGPoint(x: onScreen.minX, y: onScreen.minY)), CGPoint(x: 100, y: 200))
    }
}
