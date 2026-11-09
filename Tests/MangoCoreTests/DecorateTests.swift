import XCTest
@testable import Mango
@testable import Port

@MainActor
final class DecorateTests: MangoTestCase {
    func testTheKeysAreReadForEveryBar() {
        let parsed = ConfigParser.parse(text: """
            tab_bar_decorate_bg_color=0x112233ff
            group_bar_decorate_border_width=2
            jump_label_decorate_font_desc=Sans 20
            title_message_bar_decorate_padding_x=7
            """, baseDirectory: FileManager.default.temporaryDirectory, fileName: "t")
        XCTAssertEqual(parsed.errors, [])
        XCTAssertEqual(parsed.config.tabbardata.bgColor, parseColor("0x112233ff"))
        XCTAssertEqual(parsed.config.groupbardata.borderWidth, 2)
        XCTAssertEqual(parsed.config.jumplabeldata.fontDesc, "Sans 20")
        XCTAssertEqual(parsed.config.titleMessageBardata.paddingX, 7)
    }

    func testChutneyStyleLeavesTheRestToMacOSAndWithoutItMangosDefaults() {
        let r = EngineRig()
        r.server.config.chutneyStyle = true
        r.server.config.tabbardata.bgColor = parseColor("0x112233ff")
        var look = r.server.mangoBarDecorationApplyConfig(r.server.config.tabbardata, mango: .mangoTabBar)
        XCTAssertEqual(look.bgColor, parseColor("0x112233ff"), "a key set wins")
        XCTAssertNil(look.fontDesc, "chutney_style: the rest is drawn the macOS way")
        r.server.config.chutneyStyle = false
        look = r.server.mangoBarDecorationApplyConfig(r.server.config.tabbardata, mango: .mangoTabBar)
        XCTAssertEqual(look.fontDesc, "monospace Bold 13", "mango's default")
        XCTAssertEqual(look.focusFgColor, parseColor("0x7aa2f7ff"))
        XCTAssertEqual(look.bgColor, parseColor("0x112233ff"))
        r.server.portHooks = PortHooks()
        r.server.config.chutneyStyle = true
        XCTAssertEqual(r.server.mangoBarDecorationApplyConfig(DecorateStyle(), mango: .mangoJumpLabel), .mangoJumpLabel, "without the port: mango")
    }

    func testAJumpLabelTakesMangosSize() {
        let square = JumpLabelLook("A", decorate: DecorateStyle(), side: 64, ring: .white)
        XCTAssertEqual(square.size, CGSize(width: 64, height: 64))
        let mango = JumpLabelLook("A", decorate: .mangoJumpLabel, side: 64, ring: .white)
        XCTAssertEqual(mango.cornerRadius, 5)
        XCTAssertEqual(mango.borderWidth, 4)
        XCTAssertGreaterThan(mango.size.width, 2 * 10 + 2 * 4, "padding and border around the letter")
    }
}

@MainActor
final class BorderRadiusTests: MangoTestCase {
    func testMangosRadiusUnlessChutneyStyle() {
        let r = EngineRig()
        r.server.config.borderRadius = 6
        r.server.config.borderpx = 2
        r.server.renderBorder = true
        r.server.drawsOverlays = true
        let c = r.window(900_900)
        r.window(900_901)
        let fake = r.server.system as! FakeWindowSystem
        r.server.arrange(r.monitor, .none)
        func radius() -> CGFloat {
            r.server.updateBorders()
            return fake.borderSpecs.first { $0.id == c.id }?.radius ?? 0
        }
        XCTAssertEqual(radius(), 6)
        r.server.config.chutneyStyle = true
        XCTAssertEqual(r.server.portHooks.borderRadius?(r.server, c), BorderGeometry.cornerRadius)
        r.server.config.chutneyStyle = false
        c.isFullscreen = true
        XCTAssertEqual(radius(), 0, "mango: none in fullscreen")
        c.isFullscreen = false
        r.server.config.noRadiusWhenSingle = true
        XCTAssertEqual(radius(), 6, "two tiled windows")
        r.server.clientByIdAll(900_901)!.isFloating = true
        XCTAssertEqual(radius(), 0, "no_radius_when_single")
    }
}
