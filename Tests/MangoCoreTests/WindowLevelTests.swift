import XCTest
@testable import Port

final class WindowLevelTests: MangoTestCase {
    func testAboveTheNormalLevelIsNeverManaged() {
        for type in [AxUiElementWindowType.window, .dialog] {
            XCTAssertEqual(AppWorker.windowType(type, level: .alwaysOnTopWindow), .popup)
            XCTAssertEqual(AppWorker.windowType(type, level: .unknown(windowLevel: 25)), .popup)
        }
    }

    func testAtTheNormalLevelOrOffScreenAeroSpaceDecides() {
        XCTAssertEqual(AppWorker.windowType(.window, level: .normalWindow), .window)
        XCTAssertEqual(AppWorker.windowType(.dialog, level: .normalWindow), .dialog)
        XCTAssertEqual(AppWorker.windowType(.window, level: nil), .window)
        XCTAssertEqual(AppWorker.windowType(.popup, level: .normalWindow), .popup)
    }
}
