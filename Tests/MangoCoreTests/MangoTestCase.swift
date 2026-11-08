import XCTest
@testable import Port

class MangoTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        MacConfigPort.install()
        keepConfigErrorsInTests()
    }
}

func keepConfigErrorsInTests() {
    if getenv("XDG_RUNTIME_DIR") == nil {
        let dir = NSTemporaryDirectory() + "mango-tests-\(getpid())"
        mkdir(dir, 0o700)
        setenv("XDG_RUNTIME_DIR", dir, 1)
    }
}

extension String {
    var plain: String { replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression) }
}
