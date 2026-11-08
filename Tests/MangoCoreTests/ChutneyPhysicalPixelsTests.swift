import XCTest
@testable import Mango
@testable import Port

@MainActor
final class ChutneyPhysicalPixelsTests: MangoTestCase {
    func testOffIsMangosPointsOnIsTheScreensPixels() {
        let r = EngineRig()
        r.server.renderBorder = true
        r.server.config.borderpx = 3
        let c = r.map(1)
        XCTAssertEqual(r.server.borderWidth(c, on: r.monitor), 3, "absent: mango's, border_px points")
        r.server.config.chutneyPhysicalPixels = true
        XCTAssertEqual(r.server.borderWidth(c, on: r.monitor), 1.5, "3 pixels on a scale 2 screen")
    }

    func testTheGapsAreTheScreensPixels() {
        let r = EngineRig()
        r.monitor.gaps = Gaps(ih: 10, iv: 10, oh: 10, ov: 10)
        let a = r.map(1), b = r.map(2)
        func gap() -> CGFloat {
            let (l, rt) = a.frame.minX < b.frame.minX ? (a.frame, b.frame) : (b.frame, a.frame)
            return rt.minX - l.maxX
        }
        let gapOff = gap()
        r.server.config.chutneyPhysicalPixels = true
        r.server.arrange(r.monitor, .none)
        let gapOn = gap()
        XCTAssertEqual(gapOn, gapOff / 2, accuracy: 1, "10 pixels on a scale 2 screen are 5 points")
    }

    func testTheKeyParses() {
        let cfg = ConfigParser.parse(text: "chutney_physical_pixels=1", baseDirectory: nil, fileName: "t").config
        XCTAssertTrue(cfg.chutneyPhysicalPixels)
    }
}
