import XCTest
@testable import Port

/// Not in AeroSpace: its window-level rule for every app. A window above the normal level is
/// the app's own (Notion Calendar's meeting notification is at the floating level, 3).
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
