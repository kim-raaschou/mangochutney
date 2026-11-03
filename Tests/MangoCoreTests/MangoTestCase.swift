import XCTest
@testable import Port

/// Every test reads configs as the app does: with the port's answers to mango's config
/// reader (MacConfigPort: its keys, its notes, what HYPER is).
class MangoTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        MacConfigPort.install()
    }
}
