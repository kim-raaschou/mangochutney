import XCTest
@testable import Mango
@testable import Port

@MainActor
final class BorderOnRefusedTests: MangoTestCase {
    func check(layout: LayoutKind, min: [CGWindowID: CGSize], animations: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let r = EngineRig()
        r.server.config.animations = animations
        r.server.config.borderpx = 4
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        r.monitor.pertag.ltidxs[getMonCurtag(r.monitor)] = layout
        for id: CGWindowID in 1...3 { r.window(id) }
        for (id, size) in min { r.app.minSize[id] = size }
        r.arrange()
        r.settle(2)
        let fake = r.server.system as! FakeWindowSystem
        for (id, _) in min {
            let spec = fake.borderSpecs.first { $0.id == id }
            XCTAssertEqual(spec?.frame, r.app.frames[id], "\(layout) id \(id) anim \(animations): border \(String(describing: spec?.frame)) window \(String(describing: r.app.frames[id])) tile \(String(describing: r.server.clientByIdAll(id)?.geom))", file: file, line: line)
        }
    }

    func testTheBorderIsOnTheWindow() {
        for anim in [false, true] {
            check(layout: .tile, min: [1: CGSize(width: 1100, height: 0)], animations: anim)
            check(layout: .tile, min: [2: CGSize(width: 1000, height: 600)], animations: anim)
            check(layout: .tile, min: [3: CGSize(width: 0, height: 700)], animations: anim)
        }
    }
}
