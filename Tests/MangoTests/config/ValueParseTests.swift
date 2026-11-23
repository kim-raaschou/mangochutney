import XCTest
@testable import Mango

/// mango's src/config/value_parse.c
final class ValueParseTests: XCTestCase {

    // MARK: parse_color

    func testAColourIsAlwaysRRGGBBAA() {
        let c = parseColor("0xff0000")!

        XCTAssertEqual([c.r, c.g, c.b, c.a], [0, 1, 0, 0])
        XCTAssertNil(parseColor("#ff0000ff"))
        XCTAssertEqual(parseColor("0x112233ff")?.a, 1)
    }

    // MARK: parse_tag_mask

    func testTheTagMaskIsMangos() {
        XCTAssertEqual(ValueParse.parseTagMask("1|0"), TAG0_MASK)
        XCTAssertEqual(ValueParse.parseTagMask("32"), 32)
        XCTAssertEqual(ValueParse.parseTagMask("1|abc"), 1)
        XCTAssertEqual(ValueParse.parseTagMask("00"), 0)
        XCTAssertEqual(ValueParse.parseTagMask("-1"), 0xFFFF_FFFF)
    }
}
