import XCTest
@testable import Port

final class PermissionsTests: MangoTestCase {
    func state(_ ax: Bool, _ screen: Bool, skip: Bool = false) -> PermissionState {
        PermissionState(accessibility: ax, screenRecording: screen, skipScreenRecording: skip)
    }

    func testAtLaunchWhenSomethingIsMissing() {
        XCTAssertTrue(state(false, false).showAtLaunch)
        XCTAssertTrue(state(false, true).showAtLaunch)
        XCTAssertTrue(state(true, false).showAtLaunch)
        XCTAssertFalse(state(true, true).showAtLaunch)
    }

    func testGoingOnWithoutScreenRecordingIsRemembered() {
        XCTAssertFalse(state(true, false, skip: true).showAtLaunch)
        XCTAssertFalse(state(true, false, skip: true).showForCapture)
        XCTAssertTrue(state(false, false, skip: true).showAtLaunch)
    }

    func testForCaptureOnlyWithoutScreenRecording() {
        XCTAssertTrue(state(true, false).showForCapture)
        XCTAssertFalse(state(true, true).showForCapture)
    }
}
