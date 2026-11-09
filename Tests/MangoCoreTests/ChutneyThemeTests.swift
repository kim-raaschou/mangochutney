import XCTest
@testable import Mango
@testable import Port

final class ChutneyThemeTests: MangoTestCase {
    let purple = RGBA(r: 0.6, g: 0.2, b: 0.8, a: 1)
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mango-theme-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func write(_ name: String, _ text: String) -> URL {
        let u = dir.appendingPathComponent(name)
        try? text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func testTheColoursAsMangoConfig() {
        let text = ChutneyTheme.text(macOS: true, resolve: { _ in self.purple })
        XCTAssertTrue(text.contains("\nfocus_color=0x9933ccff\n"))
        XCTAssertTrue(text.contains("\ndrop_color=0x9933cc55\n"))
        XCTAssertEqual(ChutneyTheme.text(macOS: false, resolve: { _ in self.purple }), ChutneyTheme.header + "\n")
    }

    func testWrittenOnlyWhenItChanges() {
        let config = write("config.conf", "chutney_macos_appearance=1\nsource_optional=chutney_theme.conf\n")
        XCTAssertTrue(ChutneyTheme.sync(configURL: config, resolve: { _ in self.purple }))
        XCTAssertFalse(ChutneyTheme.sync(configURL: config, resolve: { _ in self.purple }))
        XCTAssertTrue(MenuSave.isOwnWrite(ChutneyTheme.url(configURL: config)))
    }

    func testWithoutChutneyMacOSAppearanceNoFile() {
        let config = write("config.conf", "focus_color=0xc9b890ff\n")
        XCTAssertFalse(ChutneyTheme.sync(configURL: config, resolve: { _ in self.purple }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ChutneyTheme.url(configURL: config).path))
    }

    func testTheThemeWinsOverMangosExampleAndALaterLineWinsOverIt() {
        let config = write("config.conf", "chutney_macos_appearance=1\nfocus_color=0xc9b890ff\nsource_optional=chutney_theme.conf\nborder_color=0x112233ff\n")
        ChutneyTheme.sync(configURL: config, resolve: { _ in self.purple })
        let c = ConfigParser.parseConfig(fileAt: config).config
        XCTAssertEqual(c.focuscolor, parseColor("0x9933ccff")!)
        XCTAssertEqual(c.bordercolor, parseColor("0x112233ff")!)
    }
}
