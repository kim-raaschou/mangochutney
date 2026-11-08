import XCTest
import QuartzCore
@testable import Mango
@testable import Port

@MainActor
final class OverviewBadgeTests: MangoTestCase {
    func image(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testTheLabelIsAtMost64AndAtMostHalfThePicture() {
        XCTAssertEqual(OverviewOverlay.badgeSide(for: CGRect(x: 0, y: 0, width: 600, height: 400)), 64)
        XCTAssertEqual(OverviewOverlay.badgeSide(for: CGRect(x: 0, y: 0, width: 360, height: 60)), 30, "a short, wide window")
        XCTAssertEqual(OverviewOverlay.badgeSide(for: CGRect(x: 0, y: 0, width: 360, height: 20)), 18, "still readable")
    }

    func testThePictureRectIsTheAspectFitInTheCard() {
        let l = CALayer()
        l.bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        XCTAssertEqual(OverviewOverlay.shownRect(of: l), l.bounds, "no picture yet: the card")
        l.contents = image(800, 100)
        let r = OverviewOverlay.shownRect(of: l)
        XCTAssertEqual(r.width, 400, accuracy: 0.01)
        XCTAssertEqual(r.height, 50, accuracy: 0.01)
        XCTAssertEqual(r.midY, 150, accuracy: 0.01, "centred, bars above and below")
        XCTAssertEqual(OverviewOverlay.badgeSide(for: r), 25)
    }
}
