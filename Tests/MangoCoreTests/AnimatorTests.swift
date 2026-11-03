import XCTest
@testable import Mango
@testable import Port

/// The frames an animation writes.
final class AnimatorTests: MangoTestCase {
    /// A tile whose top goes down while its bottom holds still: every frame on the way
    /// keeps the bottom where it is.
    func testABottomThatHoldsStillStaysPutOnEveryFrame() {
        let from = CGRect(x: 10, y: 10, width: 800, height: 1000)
        let to = CGRect(x: 10, y: 28, width: 800, height: 982)
        for i in 0...20 {
            let r = CGRect.lerp(from, to, CGFloat(i) / 20).rounded()
            XCTAssertEqual(r.maxY, 1010, "frame \(i)")
        }
    }

    /// Every frame on the way has the window's position and size, so its bottom, held still
    /// while its top goes down, never moves.
    @MainActor
    func testEveryFrameCarriesTheSize() {
        let a = Animator()
        let app = FakeApp()
        a.animate(id: 900_020, element: app.element(for: 900_020), queue: app,
                  from: CGRect(x: 12, y: 45, width: 1000, height: 1650), to: CGRect(x: 12, y: 65, width: 1000, height: 1630),
                  durationMs: 100, curve: BezierCurve(x1: 0.46, y1: 1, x2: 0.29, y2: 1))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertGreaterThan(app.writes.count, 2)
        XCTAssertTrue(app.writes.allSatisfy(\.setSize))
        XCTAssertEqual(Set(app.writes.map(\.frame.maxY)), [1695])
    }

    /// A floating window dragged across a screen's left edge keeps its whole size.
    func testAWholeSizeAtAHalfPointOriginKeepsItsSize() {
        for x in [-0.5, 0.5, 1.5, -1.5] as [CGFloat] {
            XCTAssertEqual(CGRect(x: x, y: x, width: 301, height: 200).rounded().size, CGSize(width: 301, height: 200))
        }
    }
}

/// A window the window server shows wholly under another is not animated.
@MainActor
final class CoveredWindowTests: MangoTestCase {
    /// Three windows on one monocle tag, the selected one in front. Without tab mode: with
    /// it, mango hides the ones behind (is_tab_hidden).
    func rig(_ kind: LayoutKind = .monocle) -> EngineRig {
        let r = EngineRig()
        r.server.config.monocleTabMode = false
        r.monitor.current.layout = kind
        for i in 0..<3 { r.window(CGWindowID(900_400 + i)) }
        r.monitor.sel = 900_400
        r.server.arrange(r.monitor, .none)
        r.settle(0.1)                                 // its read-backs
        stack(r, [900_400, 900_401, 900_402])
        r.server.config.animations = true
        r.server.config.animationDurationMove = 100
        r.app.writes.removeAll()
        return r
    }

    func writes(_ r: EngineRig, _ id: CGWindowID) -> [CGRect] { r.app.writes.filter { $0.id == id }.map(\.frame) }

    /// The usable area starts `by` points lower (as when a bar takes the top), and the
    /// monitor is arranged with animation.
    func lowerTop(_ r: EngineRig, by: CGFloat) {
        let w = r.screen.workArea
        r.monitor.screen.workArea = CGRect(x: w.minX, y: w.minY + by, width: w.width, height: w.height - by)
        r.server.arrange(r.monitor, .move)
    }

    /// The window server stacks `ids` front to back, where the app has them; `translucent`
    /// ones show what is under them.
    func stack(_ r: EngineRig, _ ids: [CGWindowID], translucent: Set<CGWindowID> = []) {
        let app = r.app
        r.server.mac.stackingOverride = { ids.map { StackedWindow(id: $0, frame: app.frames[$0]!, opaque: !translucent.contains($0)) } }
    }

    func testATranslucentWindowCoversNothing() {
        let r = rig()
        stack(r, [900_400, 900_401, 900_402], translucent: [900_400])
        lowerTop(r, by: 20)
        r.settle(0.3)
        XCTAssertGreaterThan(writes(r, 900_401).count, 2, "seen through the front window")
        XCTAssertEqual(writes(r, 900_402).count, 1, "under 900_401")
    }

    func testAWindowLargerThanAskedIsNotCovered() {
        let r = rig()
        r.app.frames[900_401]!.size.height += 40          // refused the size: reaches below the front one
        stack(r, [900_400, 900_401, 900_402])
        lowerTop(r, by: 20)
        r.settle(0.3)
        XCTAssertGreaterThan(writes(r, 900_401).count, 2, "its bottom is seen")
    }

    func testWindowsBehindTheFrontOneTakeTheirFrameWithoutFrames() {
        let r = rig()
        lowerTop(r, by: 20)   // shrinks from the top: inside where it was
        let under = r.server.clientByIdAll(900_401)!.geom!
        XCTAssertEqual(writes(r, 900_401), [under], "at once")
        r.settle(0.3)
        XCTAssertEqual(writes(r, 900_401), [under])
        XCTAssertGreaterThan(writes(r, 900_400).count, 2, "the front one is animated")

        r.app.writes.removeAll()
        lowerTop(r, by: 0)    // grows: not before the front one is there
        XCTAssertEqual(writes(r, 900_402), [])
        r.settle(0.3)
        XCTAssertEqual(writes(r, 900_402), [r.server.clientByIdAll(900_402)!.geom!])
    }

    func testSideBySideWindowsAreAnimated() {
        let r = rig(.tile)
        lowerTop(r, by: 20)
        r.settle(0.3)
        for id: CGWindowID in [900_400, 900_401, 900_402] {
            XCTAssertGreaterThan(writes(r, id).count, 2, "\(id) is seen")
        }
    }

    func testTheWindowServerDecidesWhatIsInFront() {
        let r = rig()
        stack(r, [900_402, 900_401, 900_400])   // the selected one at the back
        lowerTop(r, by: 20)
        r.settle(0.3)
        XCTAssertGreaterThan(writes(r, 900_400).count, 2, "selected (raised): never covered")
        XCTAssertGreaterThan(writes(r, 900_402).count, 2, "in front")
        XCTAssertEqual(writes(r, 900_401).count, 1, "under 900_402")
    }

    func testAnOvershootingCurveReachesPastItsEnds() {
        XCTAssertTrue(BezierCurve.mangoDefault.extremes == (0, 1))
        XCTAssertEqual(BezierCurve(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1).extremes.high, 1.1, accuracy: 0.05)
        XCTAssertLessThan(BezierCurve(x1: 0.6, y1: -0.28, x2: 0.735, y2: 0.045).extremes.low, 0)
    }
}
