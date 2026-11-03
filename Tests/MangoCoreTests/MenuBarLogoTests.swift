import XCTest
@testable import Port
@testable import Mango

/// The port's chutney_menu_bar_logo (not in mango): the colour logo, its template shape, or none.
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
        XCTAssertEqual(logo("chutney_menu_bar_logo=blue"), "color")   // invalid: the default stays
    }
}
