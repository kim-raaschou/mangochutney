import XCTest
@testable import Port

/// Every test reads configs as the app does: with the port's answers to mango's config
/// reader (MacConfigPort: its keys, its notes, what HYPER is).
class MangoTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        MacConfigPort.install()
        keepConfigErrorsInTests()
    }
}

/// mango's config error store under the tests' own runtime dir, never the running mango's.
func keepConfigErrorsInTests() {
    if getenv("XDG_RUNTIME_DIR") == nil {
        let dir = NSTemporaryDirectory() + "mango-tests-\(getpid())"
        mkdir(dir, 0o700)
        setenv("XDG_RUNTIME_DIR", dir, 1)
    }
}
