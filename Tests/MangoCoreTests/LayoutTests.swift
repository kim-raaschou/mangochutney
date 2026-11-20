import XCTest
import CoreGraphics
@testable import Mango
@testable import Port

@MainActor
final class LayoutTests: MangoTestCase {
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

    // mango's dwindle (layout/dwindle.c) on a rig with this test's monitor, gaps and config
    @MainActor
    func dwindleRig(_ config: Config = Config(), work area: CGRect? = nil, gaps g: Int32? = nil) -> EngineRig {
        let r = EngineRig()
        let w = area ?? work
        r.server.rebuildMonitors(screens: [Screen(displayID: 1, name: "test", frame: area ?? monitor, workArea: w, scale: 1, isMain: true)])
        var cfg = config
        cfg.animations = false
        r.server.config = cfg
        let m = r.monitor
        m.gappih = g ?? 5; m.gappiv = g ?? 5; m.gappoh = g ?? 10; m.gappov = g ?? 10
        m.pertag.ltidxs[getMonCurtag(m)] = .dwindle
        return r
    }

    /// The windows `visible` shown (the others on another tag), `focus` on top of the focus stack, arranged;
    /// each shown one's box.
    @MainActor
    @discardableResult
    func dwindleStep(_ r: EngineRig, _ visible: [ClientID], focus: ClientID?) -> [ClientID: CGRect] {
        for id in visible where r.server.clientByIdAll(id) == nil { r.window(id) }
        for c in r.server.clientsAll { c.tags = visible.contains(c.id) ? 1 : 2 }
        if let focus {
            r.server.focusStack.removeAll { $0 == focus }
            r.server.focusStack.insert(focus, at: 0)
        }
        r.monitor.sel = focus
        r.arrange()
        return Dictionary(uniqueKeysWithValues: visible.map { ($0, r.server.clientByIdAll($0)!.geom) })
    }

    @MainActor
    func dwindleRoot(_ r: EngineRig) -> DwindleNode? { r.monitor.pertag.dwindleRoot[getMonCurtag(r.monitor)] }

    func checkInvariants(_ name: String, _ input: LayoutInput, _ r: LayoutResult,
                         insideWork: Bool = true, stacked: Bool = false,
                         file: StaticString = #filePath, line: UInt = #line) {
        for c in input.clients {
            guard let f = r.frames[c.id] else {
                XCTFail("\(name): client \(c.id) has no frame", file: file, line: line); continue
            }
            XCTAssertGreaterThanOrEqual(f.width, 1, "\(name)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(f.height, 1, "\(name)", file: file, line: line)
            XCTAssertEqual(f, f.integral, "\(name): non-integral frame \(f)", file: file, line: line)
            if insideWork {
                XCTAssertTrue(work.contains(f), "\(name): \(c.id) \(f) outside work area", file: file, line: line)
            }
        }
        if stacked { return }
        let visible = input.clients.map(\.id)
        for (i, a) in visible.enumerated() {
            for b in visible[(i + 1)...] {
                let fa = r.frames[a]!, fb = r.frames[b]!
                XCTAssertEqual(fa.overlapArea(fb), 0, "\(name): \(a) \(fa) overlaps \(b) \(fb)", file: file, line: line)
                let dx = max(fb.minX - fa.maxX, fa.minX - fb.maxX)
                let dy = max(fb.minY - fa.maxY, fa.minY - fb.maxY)
                let sep = max(dx, dy)
                let need = dx >= dy ? gaps.ih : gaps.iv
                XCTAssertGreaterThanOrEqual(sep, need - 1, "\(name): \(a) and \(b) only \(sep) apart", file: file, line: line)
            }
        }
    }

    var statelessLayouts: [LayoutKind] {
        [.tile, .rightTile, .centerTile, .verticalTile, .deck, .verticalDeck, .monocle, .grid, .verticalGrid,
         .fair, .verticalFair]
    }

    func testStatelessLayoutsInvariants() {
        for kind in statelessLayouts {
            for n in [1, 2, 3, 5] {
                let input = makeInput(ids(n), focused: ClientID(n))
                checkInvariants("\(kind.name) n=\(n)", input, runLayout(kind, input), stacked: kind.isMonocleLike)
            }
        }
    }

    func testStatelessLayoutsWithTwoMasters() {
        var pt = PertagSettings(); pt.nmaster = 2
        for kind in statelessLayouts where !kind.name.contains("deck") {
            for n in [1, 2, 3, 5] {
                let input = makeInput(ids(n), pertag: pt)
                checkInvariants("\(kind.name) nmaster=2 n=\(n)", input, runLayout(kind, input), stacked: kind.isMonocleLike)
            }
        }
    }

    @MainActor
    func testDwindleInvariants() {
        for n in [1, 2, 3, 5] {
            let r = dwindleRig()
            let frames = dwindleStep(r, ids(n), focus: ClientID(n))
            checkInvariants("dwindle n=\(n)", makeInput(ids(n), focused: ClientID(n)), LayoutResult(frames: frames))
        }
    }

    func testScrollerInvariants() {
        for vertical in [false, true] {
            for n in [1, 2, 3, 5] {
                let input = makeInput(ids(n), focused: 1)
                let r = runLayout(vertical ? .verticalScroller : .scroller, input)
                checkInvariants("scroller v=\(vertical) n=\(n)", input, r, insideWork: false)
                XCTAssertTrue(work.contains(r.frames[1]!), "focused \(r.frames[1]!)")
            }
        }
    }

    func testTileGeometry() {
        let input = makeInput([1, 2, 3])
        let r = runLayout(.tile, input)
        XCTAssertEqual(r.frames[1], CGRect(x: 10, y: 35, width: 1053, height: 1060))
        XCTAssertEqual(r.frames[2], CGRect(x: 1068, y: 35, width: 842, height: 527))
        XCTAssertEqual(r.frames[3], CGRect(x: 1068, y: 567, width: 842, height: 528))
        let one = runLayout(.tile, makeInput([1]))
        XCTAssertEqual(one.frames[1], CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testRightTileMirrorsTile() {
        let r = runLayout(.rightTile, makeInput([1, 2]))
        XCTAssertEqual(r.frames[1], CGRect(x: 1920 - 1058 - 10 + 5, y: 35, width: 1053, height: 1060))
        XCTAssertEqual(r.frames[2], CGRect(x: 10, y: 35, width: 842, height: 1060))
    }

    func testCenterTile() {
        let r = runLayout(.centerTile, makeInput([1, 2, 3]))
        let m = r.frames[1]!, a = r.frames[2]!, b = r.frames[3]!
        XCTAssertEqual(m.midX, work.midX, accuracy: 3)
        XCTAssertLessThan(a.maxX, m.minX)
        XCTAssertGreaterThan(b.minX, m.maxX)
        XCTAssertEqual(a.minX, 10)
        XCTAssertEqual(b.maxX, 1910)
        let r2 = runLayout(.centerTile, makeInput([1, 2]))
        XCTAssertEqual(r2.frames[1]!.midX, work.midX, accuracy: 3)
        XCTAssertGreaterThan(r2.frames[2]!.minX, r2.frames[1]!.maxX)
        var cfg = Config(); cfg.centerWhenSingleStack = false
        let r3 = runLayout(.centerTile, makeInput([1, 2], config: cfg))
        XCTAssertEqual(r3.frames[1]!.minX, 10)
        XCTAssertEqual(r3.frames[2]!.maxX, 1910)
        let r4 = runLayout(.centerTile, makeInput([1]))
        XCTAssertEqual(r4.frames[1]!.midX, work.midX, accuracy: 3)
        XCTAssertLessThan(r4.frames[1]!.width, 1900)
        cfg = Config(); cfg.centerMasterOverspread = true
        XCTAssertEqual(runLayout(.centerTile, makeInput([1], config: cfg)).frames[1],
                       CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testDeckAndMonocleVisibility() {
        let input = makeInput([1, 2, 3, 4], focused: 3)
        let deck = runLayout(.deck, input)
        XCTAssertEqual(deck.frames[2], deck.frames[3])
        XCTAssertEqual(deck.frames[4], deck.frames[3], "the stack one behind the other")
        let vdeck = runLayout(.verticalDeck, input)
        XCTAssertEqual(vdeck.frames[2], vdeck.frames[4])
        XCTAssertGreaterThan(vdeck.frames[3]!.minY, vdeck.frames[1]!.maxY)

        let mono = runLayout(.monocle, input)
        for id: ClientID in [1, 2, 3, 4] { XCTAssertEqual(mono.frames[id], CGRect(x: 10, y: 35, width: 1900, height: 1060)) }
        var cfg = Config(); cfg.monocleNoGap = true
        XCTAssertEqual(runLayout(.monocle, makeInput([1], config: cfg)).frames[1], work)
    }

    func testFullscreenAndMaximized() {
        let s = LayoutRunner(.tile)
        _ = s.arrange(makeInput([1, 2, 3]))
        s.server.clientSetFullscreen(s.server.clientByIdAll(2)!, true, rearrange: true)
        s.server.clientSetMaximizeScreen(s.server.clientByIdAll(3)!, true, rearrange: true)
        XCTAssertEqual(s.server.clientByIdAll(2)!.geom, monitor)
        XCTAssertEqual(s.server.clientByIdAll(3)!.geom, CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    func testGridShapes() {
        let one = runLayout(.grid, makeInput([1]))
        XCTAssertEqual(one.frames[1]!.width, CGFloat(Int(1900.0 * 0.9)))
        XCTAssertEqual(one.frames[1]!.midX, work.midX, accuracy: 1)
        let two = runLayout(.grid, makeInput([1, 2]))
        XCTAssertEqual(two.frames[1]!.height, CGFloat(Int(1060.0 * 0.65)))
        XCTAssertEqual(two.frames[1]!.minY, two.frames[2]!.minY)
        let five = runLayout(.grid, makeInput(ids(5)))
        XCTAssertEqual(five.frames[1]!.minY, five.frames[3]!.minY)
        XCTAssertEqual(five.frames[4]!.minY, five.frames[5]!.minY)
        let rowMid = (five.frames[4]!.minX + five.frames[5]!.maxX) / 2
        XCTAssertEqual(rowMid, work.midX, accuracy: 2)
        let v = runLayout(.verticalGrid, makeInput(ids(5)))
        XCTAssertEqual(v.frames[1]!.minX, v.frames[3]!.minX)
        XCTAssertEqual(v.frames[4]!.minX, v.frames[5]!.minX)
    }

    func testFairShapes() {
        let r = runLayout(.fair, makeInput(ids(5)))
        XCTAssertEqual(r.frames[1]!.height, 1060)
        XCTAssertEqual(r.frames[2]!.minX, r.frames[3]!.minX)
        XCTAssertEqual(r.frames[4]!.minX, r.frames[5]!.minX)
        XCTAssertEqual(r.frames[5]!.maxX, 1910)
        let v = runLayout(.verticalFair, makeInput(ids(5)))
        XCTAssertEqual(v.frames[1]!.width, 1900)
        XCTAssertEqual(v.frames[2]!.minY, v.frames[3]!.minY)
    }

    @MainActor
    func testDwindleSplitsAndRemove() {
        let t = dwindleRig()
        var r = dwindleStep(t, [1], focus: 1)
        XCTAssertEqual(r[1], CGRect(x: 10, y: 35, width: 1900, height: 1060))
        r = dwindleStep(t, [1, 2], focus: 1)
        XCTAssertEqual(r[1], CGRect(x: 10, y: 35, width: 948, height: 1060))
        XCTAssertEqual(r[2], CGRect(x: 963, y: 35, width: 947, height: 1060))
        r = dwindleStep(t, [1, 2, 3], focus: 2)
        XCTAssertEqual(r[1], CGRect(x: 10, y: 35, width: 948, height: 1060))
        XCTAssertEqual(r[2]!.minX, 963)
        XCTAssertEqual(r[3]!.minX, 963)
        XCTAssertLessThan(r[2]!.maxY, r[3]!.minY)
        XCTAssertEqual(r[3]!.minY - r[2]!.maxY, 5)
        let c2 = t.server.clientByIdAll(2)!
        t.server.dwindleRemove(&t.monitor.pertag.dwindleRoot[getMonCurtag(t.monitor)], c2)
        XCTAssertNil(t.server.dwindleFindLeaf(dwindleRoot(t), c2))
        r = dwindleStep(t, [1, 3], focus: 3)
        XCTAssertEqual(r[3], CGRect(x: 963, y: 35, width: 947, height: 1060))
        r = dwindleStep(t, [3], focus: 3)
        XCTAssertNil(t.server.dwindleFindLeaf(dwindleRoot(t), t.server.clientByIdAll(1)!))
        XCTAssertEqual(r[3], CGRect(x: 10, y: 35, width: 1900, height: 1060))
    }

    @MainActor
    func testDwindleSplitSide() {
        var cfg = Config(); cfg.dwindleHsplit = 2
        let t = dwindleRig(cfg)
        dwindleStep(t, [1], focus: 1)
        let r = dwindleStep(t, [1, 2], focus: 1)
        XCTAssertLessThan(r[2]!.minX, r[1]!.minX)
    }

    @MainActor
    func testDwindleResizeAndExchange() {
        let t = dwindleRig()
        dwindleStep(t, [1], focus: 1)
        dwindleStep(t, [1, 2], focus: 1)
        let c1 = t.server.clientByIdAll(1)!, c2 = t.server.clientByIdAll(2)!
        t.server.dwindleResizeClientStep(t.monitor, c1, 190, 0)
        var r = dwindleStep(t, [1, 2], focus: 1)
        XCTAssertEqual(r[1]!.width, CGFloat(Int(1900 * 0.6) - 2))
        t.server.dwindleResizeClientStep(t.monitor, c1, 10_000, 0)
        r = dwindleStep(t, [1, 2], focus: 1)
        XCTAssertEqual(r[1]!.width, CGFloat(Int(1900 * 0.95) - 2))
        let before = r
        t.server.dwindleSwapClients(c1, c2)
        r = dwindleStep(t, [1, 2], focus: 1)
        XCTAssertEqual(r[1], before[2])
        XCTAssertEqual(r[2], before[1])
    }

    @MainActor
    func testDwindleMoveAndToggle() {
        let t = dwindleRig()
        dwindleStep(t, [1], focus: 1)
        dwindleStep(t, [1, 2], focus: 1)
        dwindleStep(t, [1, 2, 3], focus: 2)
        let c1 = t.server.clientByIdAll(1)!, c2 = t.server.clientByIdAll(2)!, c3 = t.server.clientByIdAll(3)!
        t.server.dwindleMoveNextTo(c1, c3, 0.5, RIGHT)
        let r = dwindleStep(t, [1, 2, 3], focus: 1)
        checkInvariants("dwindle after move", makeInput([1, 2, 3]), LayoutResult(frames: r))
        XCTAssertEqual(r[2]!.height, 1060)
        _ = t.server.dispatch(Dispatch(name: "dwindle_toggle_current_split"), target: c2)
        let r2 = dwindleStep(t, [1, 2, 3], focus: 1)
        checkInvariants("dwindle after toggle", makeInput([1, 2, 3]), LayoutResult(frames: r2))
        XCTAssertNotEqual(r[2], r2[2])
        t.server.dwindleSetSplitDirection(c2, false, false)
        XCTAssertEqual(t.server.dwindleFindLeaf(dwindleRoot(t), c2)?.customLeafSplitH, false)
        t.server.dwindleSetSplitDirection(c2, true, false)
        XCTAssertEqual(t.server.dwindleFindLeaf(dwindleRoot(t), c2)?.customLeafSplitH, true)
    }

    @MainActor
    func testDwindleManualSplitEqualShares() {
        var cfg = Config(); cfg.dwindleManualSplit = true
        let t = dwindleRig(cfg)
        dwindleStep(t, [1], focus: 1)
        dwindleStep(t, [1, 2], focus: 1)
        let r = dwindleStep(t, [1, 2, 3], focus: 2)
        let ws = [1, 2, 3].map { r[ClientID($0)]!.width }
        XCTAssertEqual(ws.max()! - ws.min()!, 0, accuracy: 3)
        checkInvariants("dwindle manual", makeInput([1, 2, 3], config: cfg), LayoutResult(frames: r))
    }

    func testScrollerSelfHealAndGeometry() {
        let s = LayoutRunner(.scroller)
        var r = s.arrange(makeInput([1, 2, 3], focused: 1))
        XCTAssertEqual(s.server.scrollerStacks(s.monitor), [[1], [2], [3]])
        let input = makeInput([1, 2, 4, 3], focused: 2, frames: r.frames)
        r = s.arrange(input)
        XCTAssertEqual(s.server.scrollerStacks(s.monitor), [[1], [2], [4], [3]])
        let colW = CGFloat(Int(Double(1920 - 2 * 20 - 5) * Double(Float(0.9))))
        XCTAssertEqual(r.frames[2]!.width, colW)
        XCTAssertEqual(r.frames[2]!.height, 1060)
        XCTAssertEqual(r.frames[4]!.minX - r.frames[2]!.maxX, 5)
        XCTAssertEqual(r.frames[2]!.minX - r.frames[1]!.maxX, 5)
        XCTAssertFalse(r.frames[3]!.intersects(monitor), "beyond the monitor")
        r = s.arrange(makeInput([1, 4], focused: 4, frames: r.frames))
        XCTAssertEqual(s.server.scrollerStacks(s.monitor), [[1], [4]])
    }

    func testScrollerStackGeometry() {
        let s = LayoutRunner(.scroller)
        _ = s.arrange(makeInput([1, 2], focused: 1))
        _ = s.server.dispatch(Dispatch(name: "scroller_stack", args: ["left"]), target: s.server.clientByIdAll(2))
        let r = s.arrange(makeInput([1, 2], focused: 2))
        let a = r.frames[1]!, b = r.frames[2]!
        XCTAssertEqual(a.minX, b.minX)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(b.minY - a.maxY, 5)
        XCTAssertEqual(a.minY, 35)
        XCTAssertEqual(b.maxY, 1095)
        XCTAssertEqual(a.midX, work.midX, accuracy: 1)
    }

    func testScrollerSingleProportionAndCenter() {
        var pt = PertagSettings(); pt.scrollerIgnoreProportionSingle = false; pt.scrollerDefaultProportionSingle = 0.5
        let r = runLayout(.scroller, makeInput([1], pertag: pt))
        XCTAssertEqual(r.frames[1], CGRect(x: 485, y: 35, width: 950, height: 1060))

        let s2 = LayoutRunner(.scroller)
        var cfg = Config(); cfg.scrollerPreferOverspread = false
        var p = PertagSettings(); p.scrollerDefaultProportion = 0.5
        var r2 = s2.arrange(makeInput([1, 2, 3], focused: 2, config: cfg, pertag: p))
        var frames = r2.frames
        frames[2]!.origin.x = 100
        r2 = s2.arrange(makeInput([1, 2, 3], focused: 2, config: cfg, pertag: p, frames: frames))
        XCTAssertEqual(r2.frames[2]!.minX, 100)
        _ = s2.server.dispatch(Dispatch(name: "centerwin"), target: s2.server.clientByIdAll(2))
        XCTAssertEqual(s2.server.clientByIdAll(2)!.geom.midX, work.midX, accuracy: 1)
    }

    func testVerticalScroller() {
        let r = runLayout(.verticalScroller, makeInput([1, 2, 3], focused: 2))
        let f = r.frames[2]!
        XCTAssertEqual(f.width, 1900)
        XCTAssertEqual(f.height, CGFloat(Int(Double(1080 - 40 - 5) * Double(Float(0.9)))))
        XCTAssertEqual(f.minX, 10)
        XCTAssertGreaterThan(r.frames[3]!.minY, f.maxY)
        XCTAssertLessThan(r.frames[1]!.maxY, f.minY)
    }

    func testScrollerFullscreenColumn() {
        var input = makeInput([1, 2], focused: 1)
        input.clients[0].isfullscreen = true
        let r = runLayout(.scroller, input)
        XCTAssertEqual(r.frames[1], monitor)
        XCTAssertGreaterThanOrEqual(r.frames[2]!.minX, monitor.maxX)
    }

    func testOverviewPack() {
        let sizes: [(id: ClientID, size: CGSize)] = [
            (1, CGSize(width: 1600, height: 900)), (2, CGSize(width: 800, height: 600)),
            (3, CGSize(width: 1200, height: 1000)), (4, CGSize(width: 400, height: 800)),
            (5, CGSize(width: 1000, height: 700)),
        ]
        let runner = OverviewRunner()
        let frames = runner.cards(sizes, workArea: work, gapInner: 5, gapOuter: 30)
        XCTAssertEqual(frames.count, 5)
        let inner = work.insetBy(dx: 30, dy: 30)
        let list = sizes.map { frames[$0.id]! }
        for (i, f) in list.enumerated() {
            XCTAssertTrue(inner.insetBy(dx: -1, dy: -1).contains(f), "\(f) outside \(inner)")
            let s = sizes[i].size
            XCTAssertEqual(f.width / s.width, f.height / s.height, accuracy: 0.01)
            XCTAssertLessThanOrEqual(f.width, s.width)
            for g in list[(i + 1)...] { XCTAssertEqual(f.overlapArea(g), 0) }
        }
        let one = OverviewRunner().cards([(9, CGSize(width: 400, height: 300))], workArea: work,
                                         gapInner: 5, gapOuter: 30)
        XCTAssertEqual(one[9]!.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(one[9]!.midX, work.midX, accuracy: 1)
        XCTAssertEqual(one[9]!.midY, work.midY, accuracy: 1)
    }

    func testGridLayoutsHonourToggleGapsAndIgnoreIncGaps() {
        var off = makeInput(ids(4))
        off.gaps = .zero
        off.enableGaps = false
        let g0 = runLayout(.grid, off)
        XCTAssertEqual(g0.frames[1], CGRect(x: 0, y: 25, width: 960, height: 540))
        XCTAssertEqual(g0.frames[4], CGRect(x: 960, y: 565, width: 960, height: 540))
        let v0 = runLayout(.verticalGrid, off)
        XCTAssertEqual(v0.frames[1]!.minX, 0)
        XCTAssertEqual(v0.frames[1]!.minY, 25)

        var inc = makeInput(ids(4))
        inc.gaps = Gaps(ih: 40, iv: 40, oh: 50, ov: 50)
        XCTAssertEqual(runLayout(.grid, inc).frames, runLayout(.grid, makeInput(ids(4))).frames)

        var smart = makeInput([1])
        smart.config.smartgaps = true
        smart.gaps = .zero
        XCTAssertEqual(runLayout(.grid, smart).frames, runLayout(.grid, makeInput([1])).frames)
    }

    func testRandomInputsNeverTrapOrDropClients() {
        var rng = SystemRandomNumberGenerator()
        var runners = LayoutKind.allCases.map { LayoutRunner($0) }
        let overviewRunner = OverviewRunner()
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
                let r = runners[i].arrange(input)
                for c in clients { XCTAssertNotNil(r.frames[c.id], "\(kind.name) n=\(n) lost client \(c.id)") }
            }
            if iter % 5 == 0 { runners = LayoutKind.allCases.map { LayoutRunner($0) } }
            let cards = overviewRunner.cards(ids.map { ($0, CGSize(width: Double.random(in: 0...1500, using: &rng), height: Double.random(in: 0...1500, using: &rng))) },
                                            workArea: area, gapInner: CGFloat(Int.random(in: 0...100, using: &rng)), gapOuter: CGFloat(Int.random(in: 0...200, using: &rng)))
            XCTAssertTrue(cards.count == n || cards.isEmpty, "mango: all placed, or none when no scale fits")
        }
    }

    /// mango's vertical_grid_core counts visible floats in its index, unlike grid_core (docs/afvigelser.md §6).
    func testAFloatingWindowLeavesTheVerticalGridAlone() {
        let r = EngineRig()
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = .verticalGrid
        let float = CGRect(x: 300, y: 300, width: 200, height: 150)
        let f = r.window(10, floating: true, frame: float)
        f.floatGeom = float
        let tiled = [r.window(11), r.window(12), r.window(13)]
        r.server.clients.removeAll { $0 === f }
        r.arrange()
        let alone = tiled.map(\.geom)
        r.server.clients.insert(f, at: 0)
        r.arrange()
        XCTAssertEqual(tiled.map(\.geom), alone, "the floating window takes no grid slot")
    }
}
