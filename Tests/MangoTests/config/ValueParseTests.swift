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

    /// remove_comment: a `#` after C's isspace starts a comment; after other white space it does not.
    func testACommentFollowsCsWhiteSpace() {
        XCTAssertEqual(ValueParse.removeComment("a # b"), "a ")
        XCTAssertEqual(ValueParse.removeComment("a\t# b"), "a\t")
        XCTAssertEqual(ValueParse.removeComment("a\u{00A0}# b"), "a\u{00A0}# b", "a no-break space is not isspace")
        XCTAssertEqual(ValueParse.removeComment("\"a # b\" # c"), "\"a # b\" ")
    }
}
