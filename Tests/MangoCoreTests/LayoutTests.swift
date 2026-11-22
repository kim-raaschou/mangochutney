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

}
