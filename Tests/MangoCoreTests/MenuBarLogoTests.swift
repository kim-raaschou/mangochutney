import XCTest
@testable import Port
@testable import Mango

final class MenuBarLogoTests: MangoTestCase {
    func logo(_ line: String) -> String {
        ConfigParser.parse(text: line, baseDirectory: nil, fileName: "t").config.chutneyMenuBarLogo
    }

    func testValues() {
        XCTAssertEqual(logo(""), "color")
        XCTAssertEqual(logo("chutney_menu_bar_logo=1"), "color")
        XCTAssertEqual(logo("chutney_menu_bar_logo=0"), "off")
        XCTAssertEqual(logo("chutney_menu_bar_logo=mono"), "mono")
        XCTAssertEqual(logo("chutney_menu_bar_logo=color"), "color")
        XCTAssertEqual(logo("chutney_menu_bar_logo=blue"), "color")
    }
}
