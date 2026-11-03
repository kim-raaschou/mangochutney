import XCTest
import CoreGraphics
@testable import Mango
@testable import Port

final class LayoutTests: MangoTestCase {

    // 1920x1080 work area below a 25pt menu bar.
    let work = CGRect(x: 0, y: 25, width: 1920, height: 1080)
    let monitor = CGRect(x: 0, y: 0, width: 1920, height: 1105)
    let gaps = Gaps(ih: 5, iv: 5, oh: 10, ov: 10)

    func makeInput(_ ids: [ClientID], focused: ClientID? = nil, prev: ClientID? = nil,
                   config: Config = Config(), pertag: PertagSettings = PertagSettings(),
                   frames: [ClientID: CGRect] = [:]) -> LayoutInput {
        let clients = ids.map { LayoutClient(id: $0, currentFrame: frames[$0] ?? CGRect(x: 400, y: 300, width: 800, height: 600)) }
        return LayoutInput(workArea: work, monitorFrame: monitor, gaps: gaps, clients: clients,
                           focusedID: focused ?? ids.first, prevFocusedID: prev, pertag: pertag, config: config)
    }

    func ids(_ n: Int) -> [ClientID] { (1...n).map { ClientID($0) } }

    // MARK: Generic invariants

    /// Every client framed, integral, >= 1; visible frames don't overlap,
    /// keep at least the inner gap between them and (optionally) lie inside
    /// the work area.
    func checkInvariants(_ name: String, _ input: LayoutInput, _ r: LayoutResult,
                         insideWork: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for c in input.clients {
            guard let f = r.frames[c.id] else {
                XCTFail("\(name): client \(c.id) has no frame", file: file, line: line); continue
            }
            XCTAssertGreaterThanOrEqual(f.width, 1, "\(name)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(f.height, 1, "\(name)", file: file, line: line)
            XCTAssertEqual(f, f.integral, "\(name): non-integral frame \(f)", file: file, line: line)
            if insideWork && !r.hidden.contains(c.id) {
                XCTAssertTrue(work.contains(f), "\(name): \(c.id) \(f) outside work area", file: file, line: line)
            }
        }
        let visible = input.clients.map(\.id).filter { !r.hidden.contains($0) }
        for (i, a) in visible.enumerated() {
            for b in visible[(i + 1)...] {
                let fa = r.frames[a]!, fb = r.frames[b]!
                XCTAssertEqual(fa.overlapArea(fb), 0, "\(name): \(a) \(fa) overlaps \(b) \(fb)", file: file, line: line)
                // Gap: separation along the axis on which they are apart.
                let dx = max(fb.minX - fa.maxX, fa.minX - fb.maxX)
                let dy = max(fb.minY - fa.maxY, fa.minY - fb.maxY)
                let sep = max(dx, dy)
                let need = dx >= dy ? gaps.ih : gaps.iv
                XCTAssertGreaterThanOrEqual(sep, need - 1, "\(name): \(a) and \(b) only \(sep) apart", file: file, line: line)
            }
        }
    }

    typealias Layout = (LayoutInput) -> LayoutResult

    var statelessLayouts: [(String, Layout)] {
        [("tile", TileLayouts.tile), ("right_tile", TileLayouts.rightTile),
         ("center_tile", TileLayouts.centerTile), ("vertical_tile", TileLayouts.verticalTile),
         ("deck", TileLayouts.deck), ("vertical_deck", TileLayouts.verticalDeck),
         ("monocle", TileLayouts.monocle), ("grid", GridLayouts.grid),
         ("vertical_grid", GridLayouts.verticalGrid), ("fair", GridLayouts.fair),
         ("vertical_fair", GridLayouts.verticalFair)]
    }

    func testStatelessLayoutsInvariants() {
        for (name, layout) in statelessLayouts {
            for n in [1, 2, 3, 5] {
                let input = makeInput(ids(n), focused: ClientID(n))
                checkInvariants("\(name) n=\(n)", input, layout(input))
            }
        }
    }

    func testStatelessLayoutsWithTwoMasters() {
        var pt = PertagSettings(); pt.nmaster = 2
        for (name, layout) in statelessLayouts where !name.contains("deck") {  // deck masters share no gap (as mango)
            for n in [1, 2, 3, 5] {
                let input = makeInput(ids(n), pertag: pt)
                checkInvariants("\(name) nmaster=2 n=\(n)", input, layout(input))
            }
        }
    }

    func testDwindleInvariants() {
        for n in [1, 2, 3, 5] {
            let tree = DwindleTree()
            let input = makeInput(ids(n), focused: ClientID(n))
            checkInvariants("dwindle n=\(n)", input, tree.dwindleCore(input))
        }
    }

    func testScrollerInvariants() {
        for vertical in [false, true] {
            for n in [1, 2, 3, 5] {
                let s = ScrollerState()
                let input = makeInput(ids(n), focused: 1)
                let r = s.arrange(input, vertical: vertical)
                checkInvariants("scroller v=\(vertical) n=\(n)", input, r, insideWork: false)
                // The focused column is fully inside the work area; every
                // non-hidden frame touches the monitor.
                XCTAssertTrue(work.contains(r.frames[1]!), "focused \(r.frames[1]!)")
                for id in ids(n) where !r.hidden.contains(id) {
                    XCTAssertTrue(r.frames[id]!.intersects(monitor))
                }
                for id in r.hidden { XCTAssertFalse(r.frames[id]!.intersects(monitor)) }
            }
        }
    }

    // MARK: Exact geometry

    func testTileGeometry() {
        let input = makeInput([1, 2, 3])
        let r = TileLayouts.tile(input)
        // mw = (1920 + 5) * 0.55 = 1058
        XCTAssertEqual(r.frames[1], CGRect(x: 10, y: 35, width: 1053, height: 1060))
        XCTAssertEqual(r.frames[2], CGRect(x: 1068, y: 35, width: 842, height: 527))
        XCTAssertEqual(r.frames[3], CGRect(x: 1068, y: 567, width: 842, height: 528))
        // Single client fills the work area minus outer gaps.
        let one = TileLayouts.tile(makeInput([1]))
        XCTAssertEqual(one.frames[1], CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testRightTileMirrorsTile() {
        let r = TileLayouts.rightTile(makeInput([1, 2]))
        XCTAssertEqual(r.frames[1], CGRect(x: 1920 - 1058 - 10 + 5, y: 35, width: 1053, height: 1060))
        XCTAssertEqual(r.frames[2], CGRect(x: 10, y: 35, width: 842, height: 1060))
    }

    func testCenterTile() {
        // 3 clients (odd n): master centered, first stack client left, second right.
        let r = TileLayouts.centerTile(makeInput([1, 2, 3]))
        let m = r.frames[1]!, a = r.frames[2]!, b = r.frames[3]!
        XCTAssertEqual(m.midX, work.midX, accuracy: 3)
        XCTAssertLessThan(a.maxX, m.minX)
        XCTAssertGreaterThan(b.minX, m.maxX)
        XCTAssertEqual(a.minX, 10)
        XCTAssertEqual(b.maxX, 1910)
        // 2 clients + center_when_single_stack: master centered, stack right.
        let r2 = TileLayouts.centerTile(makeInput([1, 2]))
        XCTAssertEqual(r2.frames[1]!.midX, work.midX, accuracy: 3)
        XCTAssertGreaterThan(r2.frames[2]!.minX, r2.frames[1]!.maxX)
        // Without it: master left, stack right.
        var cfg = Config(); cfg.centerWhenSingleStack = false
        let r3 = TileLayouts.centerTile(makeInput([1, 2], config: cfg))
        XCTAssertEqual(r3.frames[1]!.minX, 10)
        XCTAssertEqual(r3.frames[2]!.maxX, 1910)
        // Only a master: centered unless overspread.
        let r4 = TileLayouts.centerTile(makeInput([1]))
        XCTAssertEqual(r4.frames[1]!.midX, work.midX, accuracy: 3)
        XCTAssertLessThan(r4.frames[1]!.width, 1900)
        cfg = Config(); cfg.centerMasterOverspread = true
        XCTAssertEqual(TileLayouts.centerTile(makeInput([1], config: cfg)).frames[1],
                       CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testDeckAndMonocleVisibility() {
        let input = makeInput([1, 2, 3, 4], focused: 3)
        let deck = TileLayouts.deck(input)
        XCTAssertEqual(deck.hidden, [2, 4])
        XCTAssertEqual(deck.frames[2], deck.frames[3])
        // Focus on the master: first stack client is shown.
        let deck2 = TileLayouts.deck(makeInput([1, 2, 3, 4], focused: 1))
        XCTAssertEqual(deck2.hidden, [3, 4])
        let vdeck = TileLayouts.verticalDeck(input)
        XCTAssertEqual(vdeck.hidden, [2, 4])
        XCTAssertGreaterThan(vdeck.frames[3]!.minY, vdeck.frames[1]!.maxY)

        let mono = TileLayouts.monocle(input)
        XCTAssertEqual(mono.hidden, [1, 2, 4])
        XCTAssertEqual(mono.frames[1], CGRect(x: 10, y: 35, width: 1900, height: 1060))
        var cfg = Config(); cfg.monocleNoGap = true
        XCTAssertEqual(TileLayouts.monocle(makeInput([1], config: cfg)).frames[1], work)
    }

    func testFullscreenAndMaximized() {
        var input = makeInput([1, 2, 3])
        input.clients[1].isFullscreen = true
        input.clients[2].isMaximized = true
        let r = TileLayouts.tile(input)
        XCTAssertEqual(r.frames[2], monitor)
        XCTAssertEqual(r.frames[3], CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testGridShapes() {
        let one = GridLayouts.grid(makeInput([1]))
        XCTAssertEqual(one.frames[1]!.width, CGFloat(Int(1900.0 * 0.9)))
        XCTAssertEqual(one.frames[1]!.midX, work.midX, accuracy: 1)
        let two = GridLayouts.grid(makeInput([1, 2]))
        XCTAssertEqual(two.frames[1]!.height, CGFloat(Int(1060.0 * 0.65)))
        XCTAssertEqual(two.frames[1]!.minY, two.frames[2]!.minY)
        // 5 clients: 3 columns x 2 rows, last row (2 clients) centered.
        let five = GridLayouts.grid(makeInput(ids(5)))
        XCTAssertEqual(five.frames[1]!.minY, five.frames[3]!.minY)
        XCTAssertEqual(five.frames[4]!.minY, five.frames[5]!.minY)
        let rowMid = (five.frames[4]!.minX + five.frames[5]!.maxX) / 2
        XCTAssertEqual(rowMid, work.midX, accuracy: 2)
        // vertical_grid is the transpose: 5 clients -> columns of 3 and 2.
        let v = GridLayouts.verticalGrid(makeInput(ids(5)))
        XCTAssertEqual(v.frames[1]!.minX, v.frames[3]!.minX)
        XCTAssertEqual(v.frames[4]!.minX, v.frames[5]!.minX)
    }

    func testFairShapes() {
        // 5 clients: 3 columns; first column 1 row, the other two 2 rows.
        let r = GridLayouts.fair(makeInput(ids(5)))
        XCTAssertEqual(r.frames[1]!.height, 1060)
        XCTAssertEqual(r.frames[2]!.minX, r.frames[3]!.minX)
        XCTAssertEqual(r.frames[4]!.minX, r.frames[5]!.minX)
        XCTAssertEqual(r.frames[5]!.maxX, 1910)
        let v = GridLayouts.verticalFair(makeInput(ids(5)))
        XCTAssertEqual(v.frames[1]!.width, 1900)
        XCTAssertEqual(v.frames[2]!.minY, v.frames[3]!.minY)
    }

    // MARK: Dwindle

    func testDwindleSplitsAndRemove() {
        let t = DwindleTree()
        var r = t.dwindleCore(makeInput([1]))
        XCTAssertEqual(r.frames[1], CGRect(x: 10, y: 35, width: 1900, height: 1060))
        r = t.dwindleCore(makeInput([1, 2], focused: 1))
        // Horizontal split: w1 = 1900 * 0.5 - 5/2.
        XCTAssertEqual(r.frames[1], CGRect(x: 10, y: 35, width: 948, height: 1060))
        XCTAssertEqual(r.frames[2], CGRect(x: 963, y: 35, width: 947, height: 1060))
        // New client splits the focused (portrait) leaf vertically, below it.
        r = t.dwindleCore(makeInput([1, 2, 3], focused: 2))
        XCTAssertEqual(r.frames[1], CGRect(x: 10, y: 35, width: 948, height: 1060))
        XCTAssertEqual(r.frames[2]!.minX, 963)
        XCTAssertEqual(r.frames[3]!.minX, 963)
        XCTAssertLessThan(r.frames[2]!.maxY, r.frames[3]!.minY)
        XCTAssertEqual(r.frames[3]!.minY - r.frames[2]!.maxY, 5)
        // Removing 2: its sibling 3 takes the parent's place.
        t.dwindleRemove(2, config: Config())
        XCTAssertFalse(t.contains(2))
        r = t.dwindleCore(makeInput([1, 3], focused: 3))
        XCTAssertEqual(r.frames[3], CGRect(x: 963, y: 35, width: 947, height: 1060))
        // Self-heal: clients missing from the input are dropped.
        r = t.dwindleCore(makeInput([3], focused: 3))
        XCTAssertFalse(t.contains(1))
        XCTAssertEqual(r.frames[3], CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testDwindleSplitSide() {
        var cfg = Config(); cfg.dwindleHsplit = 2
        let t = DwindleTree()
        _ = t.dwindleCore(makeInput([1], config: cfg))
        let r = t.dwindleCore(makeInput([1, 2], focused: 1, config: cfg))
        XCTAssertLessThan(r.frames[2]!.minX, r.frames[1]!.minX)
    }

    func testDwindleResizeAndExchange() {
        let t = DwindleTree()
        _ = t.dwindleCore(makeInput([1]))
        _ = t.dwindleCore(makeInput([1, 2], focused: 1))
        t.dwindleResizeClientStep(1, dx: 190, dy: 0, config: Config())   // ratio 0.5 -> 0.6
        var r = t.dwindleCore(makeInput([1, 2], focused: 1))
        XCTAssertEqual(r.frames[1]!.width, CGFloat(Int(1900 * 0.6) - 2))
        t.dwindleResizeClientStep(1, dx: 10_000, dy: 0, config: Config())  // clamped to 0.95
        r = t.dwindleCore(makeInput([1, 2], focused: 1))
        XCTAssertEqual(r.frames[1]!.width, CGFloat(Int(1900 * 0.95) - 2))
        let before = r
        t.dwindleSwapClients(1, 2)
        r = t.dwindleCore(makeInput([1, 2], focused: 1))
        XCTAssertEqual(r.frames[1], before.frames[2])
        XCTAssertEqual(r.frames[2], before.frames[1])
    }

    func testDwindleMoveAndToggle() {
        let t = DwindleTree()
        _ = t.dwindleCore(makeInput([1]))
        _ = t.dwindleCore(makeInput([1, 2], focused: 1))
        _ = t.dwindleCore(makeInput([1, 2, 3], focused: 2))
        // Move 1 next to 3: it leaves the left half and splits 3's leaf.
        t.dwindleMoveNextTo(1, nextTo: 3, direction: .right, config: Config())
        let r = t.dwindleCore(makeInput([1, 2, 3], focused: 1))
        checkInvariants("dwindle after move", makeInput([1, 2, 3]), r)
        XCTAssertEqual(r.frames[2]!.height, 1060)
        // Toggling the current split flips 2|3 orientation.
        t.dwindleToggleCurrentSplit(for: 2)
        let r2 = t.dwindleCore(makeInput([1, 2, 3], focused: 1))
        checkInvariants("dwindle after toggle", makeInput([1, 2, 3]), r2)
        XCTAssertNotEqual(r.frames[2], r2.frames[2])
        t.dwindleSetSplitDirection(2, horizontal: false)
        XCTAssertEqual(t.leafSplitHorizontal(for: 2), false)
        t.dwindleSetSplitDirection(2, horizontal: nil)
        XCTAssertEqual(t.leafSplitHorizontal(for: 2), true)
        t.dwindleFreeTree()
        XCTAssertFalse(t.contains(1))
    }

    func testDwindleManualSplitEqualShares() {
        var cfg = Config(); cfg.dwindleManualSplit = true
        let t = DwindleTree()
        _ = t.dwindleCore(makeInput([1], config: cfg))
        _ = t.dwindleCore(makeInput([1, 2], focused: 1, config: cfg))
        let r = t.dwindleCore(makeInput([1, 2, 3], focused: 2, config: cfg))
        // Three equal columns (all horizontal splits).
        let ws = [1, 2, 3].map { r.frames[ClientID($0)]!.width }
        XCTAssertEqual(ws.max()! - ws.min()!, 0, accuracy: 3)
        checkInvariants("dwindle manual", makeInput([1, 2, 3], config: cfg), r)
    }

    // MARK: Scroller

    func testScrollerStateOperations() {
        let s = ScrollerState()
        s.insert(1, afterFocused: nil)
        s.insert(2, afterFocused: 1)
        s.insert(3, afterFocused: 1)
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[1], [3], [2]])
        // Stack 3 into its right neighbour's column (tail).
        XCTAssertTrue(s.scrollerApplyStack(3, direction: .right, vertical: false, clientOrder: [1, 2, 3]))
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[1], [2, 3]])
        XCTAssertEqual(s.column(of: 3), [2, 3])
        XCTAssertEqual(s.position(of: 3, in: [1, 2, 3])?.column, 1)
        XCTAssertEqual(s.position(of: 3, in: [1, 2, 3])?.row, 1)
        // Wrong axis is ignored.
        XCTAssertFalse(s.scrollerApplyStack(3, direction: .up, vertical: false, clientOrder: [1, 2, 3]))
        // Exchange within a stack.
        s.exchangeTwoScrollerClients(2, 3)
        XCTAssertEqual(s.column(of: 2), [3, 2])
        // Unstack to the left: becomes its own column before the stack.
        XCTAssertTrue(s.scrollerApplyStack(2, direction: .left, vertical: false, clientOrder: [1, 2, 3]))
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[1], [2], [3]])
        // No column to the left of 1.
        XCTAssertFalse(s.scrollerApplyStack(1, direction: .left, vertical: false, clientOrder: [1, 2, 3]))
        // Exchange across columns swaps whole stacks.
        _ = s.scrollerApplyStack(3, direction: .left, vertical: false, clientOrder: [1, 2, 3])
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[1], [2, 3]])
        s.exchangeTwoScrollerClients(1, 3)
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[2, 3], [1]])
        s.scrollerNodeRemove(2)
        XCTAssertEqual(s.columns(for: [1, 3]), [[3], [1]])
        XCTAssertFalse(s.contains(2))
        // Vertical scroller stacks along up/down.
        XCTAssertTrue(s.scrollerApplyStack(1, direction: .up, vertical: true, clientOrder: [1, 3]))
        XCTAssertEqual(s.columns(for: [1, 3]), [[3, 1]])
        s.clearScrollerState()
        XCTAssertFalse(s.contains(1))
    }

    func testScrollerSelfHealAndGeometry() {
        let s = ScrollerState()
        var r = s.arrange(makeInput([1, 2, 3], focused: 1), vertical: false)
        XCTAssertEqual(s.columns(for: [1, 2, 3]), [[1], [2], [3]])
        // New client 4, put after the focused client in the client list (mango
        // client_insert_tiling_order), becomes a column there: the columns follow the list.
        let input = makeInput([1, 2, 4, 3], focused: 2, frames: r.frames)
        r = s.arrange(input, vertical: false)
        XCTAssertEqual(s.columns(for: [1, 2, 3, 4]), [[1], [2], [4], [3]])
        let colW = CGFloat(Int(Double(1920 - 2 * 20 - 5) * 0.9))
        XCTAssertEqual(r.frames[2]!.width, colW)
        XCTAssertEqual(r.frames[2]!.height, 1060)
        XCTAssertEqual(r.frames[4]!.minX - r.frames[2]!.maxX, 5)
        XCTAssertEqual(r.frames[2]!.minX - r.frames[1]!.maxX, 5)
        // Columns far off-screen are hidden but keep a frame.
        XCTAssertTrue(r.hidden.contains(3))
        XCTAssertNotNil(r.frames[3])
        // Stale clients are dropped.
        r = s.arrange(makeInput([1, 4], focused: 4, frames: r.frames), vertical: false)
        XCTAssertEqual(s.columns(for: [1, 4]), [[1], [4]])
    }

    func testScrollerStackGeometry() {
        let s = ScrollerState()
        _ = s.arrange(makeInput([1, 2], focused: 1), vertical: false)
        _ = s.scrollerApplyStack(2, direction: .left, vertical: false, clientOrder: [1, 2])
        let r = s.arrange(makeInput([1, 2], focused: 2), vertical: false)
        let a = r.frames[1]!, b = r.frames[2]!
        XCTAssertEqual(a.minX, b.minX)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(b.minY - a.maxY, 5)
        XCTAssertEqual(a.minY, 35)
        XCTAssertEqual(b.maxY, 1095)
        // Single column (ignore_proportion_single): centered.
        XCTAssertEqual(a.midX, work.midX, accuracy: 1)
    }

    func testScrollerSingleProportionAndCenter() {
        let s = ScrollerState()
        var pt = PertagSettings(); pt.scrollerIgnoreProportionSingle = false; pt.scrollerDefaultProportionSingle = 0.5
        let r = s.arrange(makeInput([1], pertag: pt), vertical: false)
        XCTAssertEqual(r.frames[1], CGRect(x: 485, y: 35, width: 950, height: 1060))

        // Focused column already inside the struts keeps its x; centerwin centers it.
        let s2 = ScrollerState()
        var cfg = Config(); cfg.scrollerPreferOverspread = false
        var frames: [ClientID: CGRect] = [:]
        var p = PertagSettings(); p.scrollerDefaultProportion = 0.5
        var r2 = s2.arrange(makeInput([1, 2, 3], focused: 2, config: cfg, pertag: p), vertical: false)
        frames = r2.frames
        frames[2]!.origin.x = 100
        r2 = s2.arrange(makeInput([1, 2, 3], focused: 2, config: cfg, pertag: p, frames: frames), vertical: false)
        XCTAssertEqual(r2.frames[2]!.minX, 100)
        s2.centerWindow(2)
        r2 = s2.arrange(makeInput([1, 2, 3], focused: 2, config: cfg, pertag: p, frames: r2.frames), vertical: false)
        XCTAssertEqual(r2.frames[2]!.midX, work.midX, accuracy: 1)
    }

    func testVerticalScroller() {
        let s = ScrollerState()
        let r = s.arrange(makeInput([1, 2, 3], focused: 2), vertical: true)
        let f = r.frames[2]!
        XCTAssertEqual(f.width, 1900)
        XCTAssertEqual(f.height, CGFloat(Int(Double(1080 - 40 - 5) * 0.9)))
        XCTAssertEqual(f.minX, 10)
        XCTAssertGreaterThan(r.frames[3]!.minY, f.maxY)
        XCTAssertLessThan(r.frames[1]!.maxY, f.minY)
    }

    func testScrollerFullscreenColumn() {
        let s = ScrollerState()
        var input = makeInput([1, 2], focused: 1)
        input.clients[0].isFullscreen = true
        let r = s.arrange(input, vertical: false)
        XCTAssertEqual(r.frames[1], monitor)
        XCTAssertGreaterThanOrEqual(r.frames[2]!.minX, monitor.maxX)
    }

    func testLayoutEngineDispatchFramesEveryClient() {
        let state = TagLayoutState()
        for kind in LayoutKind.allCases {
            let input = makeInput(ids(4), focused: 2)
            let r = LayoutEngine.arrange(kind, input: input, state: state)
            XCTAssertEqual(Set(r.frames.keys), Set(ids(4)), kind.name)
        }
    }

    // MARK: Overview

    func testOverviewPack() {
        let sizes: [(id: ClientID, size: CGSize)] = [
            (1, CGSize(width: 1600, height: 900)), (2, CGSize(width: 800, height: 600)),
            (3, CGSize(width: 1200, height: 1000)), (4, CGSize(width: 400, height: 800)),
            (5, CGSize(width: 1000, height: 700)),
        ]
        let frames = OverviewLayout.overviewScale(clients: sizes, workArea: work, gapInner: 5, gapOuter: 30)
        XCTAssertEqual(frames.count, 5)
        let inner = work.insetBy(dx: 30, dy: 30)
        let list = sizes.map { frames[$0.id]! }
        for (i, f) in list.enumerated() {
            XCTAssertTrue(inner.insetBy(dx: -1, dy: -1).contains(f), "\(f) outside \(inner)")
            // Aspect ratio preserved, scale <= 1.
            let s = sizes[i].size
            XCTAssertEqual(f.width / s.width, f.height / s.height, accuracy: 0.01)
            XCTAssertLessThanOrEqual(f.width, s.width)
            for g in list[(i + 1)...] { XCTAssertEqual(f.overlapArea(g), 0) }
        }
        // A single small window is not upscaled and is centered.
        let one = OverviewLayout.overviewScale(clients: [(9, CGSize(width: 400, height: 300))], workArea: work,
                                      gapInner: 5, gapOuter: 30)
        XCTAssertEqual(one[9]!.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(one[9]!.midX, work.midX, accuracy: 1)
        XCTAssertEqual(one[9]!.midY, work.midY, accuracy: 1)
    }

    // MARK: Gaps in the grid layouts (mango reads config.gapp*, but honours togglegaps)

    func testGridLayoutsHonourToggleGapsAndIgnoreIncGaps() {
        // `togglegaps` switched them off (server.enable_gaps): no gaps in grid either.
        var off = makeInput(ids(4))
        off.gaps = .zero
        off.enableGaps = false
        let g0 = GridLayouts.grid(off)
        XCTAssertEqual(g0.frames[1], CGRect(x: 0, y: 25, width: 960, height: 540))
        XCTAssertEqual(g0.frames[4], CGRect(x: 960, y: 565, width: 960, height: 540))
        let v0 = GridLayouts.verticalGrid(off)
        XCTAssertEqual(v0.frames[1]!.minX, 0)
        XCTAssertEqual(v0.frames[1]!.minY, 25)

        // `incgaps` changes the monitor's gaps only; mango's grid keeps using config.gappoh/gappih.
        var inc = makeInput(ids(4))
        inc.gaps = Gaps(ih: 40, iv: 40, oh: 50, ov: 50)
        XCTAssertEqual(GridLayouts.grid(inc).frames, GridLayouts.grid(makeInput(ids(4))).frames)

        // smart_gaps zeroes the gaps of a lone window in the engine; mango's grid ignores it.
        var smart = makeInput([1])
        smart.config.smartgaps = true
        smart.gaps = .zero
        XCTAssertEqual(GridLayouts.grid(smart).frames, GridLayouts.grid(makeInput([1])).frames)
    }

    // MARK: Robustness

    /// `mmsg dispatch set_proportion,nan` reaches the layouts as NaN (Double("nan") parses); the
    /// float -> Int conversions would trap and take the window manager down.
    func testNonFiniteInputsDoNotTrap() {
        var pt = PertagSettings()
        pt.mfact = .nan
        pt.scrollerDefaultProportion = .infinity
        let nan = CGFloat.nan
        let clients = (1...4).map {
            LayoutClient(id: ClientID($0), currentFrame: CGRect(x: nan, y: 0, width: 100, height: 100),
                         scrollerProportion: $0 % 2 == 0 ? nan : .infinity, scrollerProportionSingle: nan, masterInnerPer: nan,
                         stackInnerPer: nan, scrollerStackWeight: nan)
        }
        let input = LayoutInput(workArea: work, monitorFrame: monitor, gaps: gaps, clients: clients, focusedID: 2,
                                prevFocusedID: 3, pertag: pt, config: Config())
        for kind in LayoutKind.allCases {
            let r = LayoutEngine.arrange(kind, input: input, state: TagLayoutState())
            XCTAssertEqual(r.frames.count, 4, kind.name)
            for f in r.frames.values { XCTAssertTrue(f.origin.x.isFinite && f.width.isFinite && f.width >= 1, "\(kind.name) \(f)") }
        }
    }

    /// No layout may trap or lose a client for odd inputs (tiny work areas, huge gaps,
    /// more masters than clients, shares that do not add up).
    func testRandomInputsNeverTrapOrDropClients() {
        var rng = SystemRandomNumberGenerator()
        let states = LayoutKind.allCases.map { _ in TagLayoutState() }
        for iter in 0..<300 {
            let n = Int.random(in: 0...10, using: &rng)
            let area = CGRect(x: CGFloat(Int.random(in: -2000...2000, using: &rng)), y: CGFloat(Int.random(in: -500...500, using: &rng)),
                              width: CGFloat(Int.random(in: 1...3000, using: &rng)), height: CGFloat(Int.random(in: 1...2000, using: &rng)))
            let gaps = Gaps(ih: CGFloat(Int.random(in: 0...400, using: &rng)), iv: CGFloat(Int.random(in: 0...400, using: &rng)),
                            oh: CGFloat(Int.random(in: 0...400, using: &rng)), ov: CGFloat(Int.random(in: 0...400, using: &rng)))
            var cfg = Config()
            cfg.scrollerStructs = Int.random(in: 0...1000, using: &rng)
            cfg.centerMasterOverspread = Bool.random(); cfg.scrollerPreferCenter = Bool.random()
            cfg.scrollerFocusCenter = Bool.random(); cfg.dwindleManualSplit = Bool.random(); cfg.dwindleSmartSplit = Bool.random()
            cfg.gappih = Int(gaps.ih); cfg.gappoh = Int(gaps.oh)
            cfg.gappiv = Int(gaps.iv); cfg.gappov = Int(gaps.ov)
            var pt = PertagSettings()
            pt.nmaster = Int.random(in: 0...12, using: &rng)
            pt.mfact = CGFloat(Double.random(in: 0.1...0.9, using: &rng))
            let ids = (0..<n).map { ClientID($0 + 1) }
            let clients = ids.map { id in
                LayoutClient(id: id,
                             currentFrame: CGRect(x: Double.random(in: -3000...3000, using: &rng), y: Double.random(in: -1000...1000, using: &rng),
                                                  width: Double.random(in: 0...2000, using: &rng), height: Double.random(in: 0...2000, using: &rng)),
                             scrollerProportion: Bool.random() ? CGFloat(Double.random(in: 0.1...1, using: &rng)) : nil,
                             masterInnerPer: Bool.random() ? CGFloat(Double.random(in: 0...1, using: &rng)) : 0)
            }
            let input = LayoutInput(workArea: area, monitorFrame: area, gaps: gaps, clients: clients,
                                    focusedID: ids.randomElement(using: &rng), prevFocusedID: ids.randomElement(using: &rng),
                                    pertag: pt, config: cfg, cursor: CGPoint(x: 100, y: 100))
            for (i, kind) in LayoutKind.allCases.enumerated() {
                let r = LayoutEngine.arrange(kind, input: input, state: states[i])
                for c in clients { XCTAssertNotNil(r.frames[c.id], "\(kind.name) n=\(n) lost client \(c.id)") }
            }
            if iter % 5 == 0 { for st in states { st.scrollerState.clearScrollerState(); st.dwindleRoot.dwindleFreeTree() } }
            let cards = OverviewLayout.overviewScale(clients: ids.map { ($0, CGSize(width: Double.random(in: 0...1500, using: &rng), height: Double.random(in: 0...1500, using: &rng))) },
                                            workArea: area, gapInner: CGFloat(Int.random(in: 0...100, using: &rng)), gapOuter: CGFloat(Int.random(in: 0...200, using: &rng)))
            XCTAssertTrue(cards.count == n || cards.isEmpty, "mango: all placed, or none when no scale fits")
        }
    }
}
