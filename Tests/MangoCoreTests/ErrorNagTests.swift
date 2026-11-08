import XCTest
@testable import Mango
@testable import Port

@MainActor
final class ErrorNagTests: MangoTestCase {
    func testConfigErrorsReachTheNagAsMango() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let conf = dir.appendingPathComponent("config.conf")
        try "border_px=2\nnot a line\nfoo_bar=1\n".write(to: conf, atomically: true, encoding: .utf8)
        let editor = getenv("EDITOR").map { String(cString: $0) }
        setenv("EDITOR", "nvim", 1)
        defer { if let editor { setenv("EDITOR", editor, 1) } else { unsetenv("EDITOR") } }

        let r = EngineRig()
        let fake = try XCTUnwrap(r.server.system as? FakeWindowSystem)
        r.server.configURL = conf
        r.server.reloadConfig()

        XCTAssertEqual(fake.nagArgv, ["mangonag", "-o", "Built-in", "-t", "error", "-e", "top", "-l", "-s", "Close",
                                      "-b", "Edit", "nvim +2 '\(conf.path)'"])
        let lines = fake.nagInput.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "[ERROR]: Invalid line format: \u{1B}[1m\u{1B}[31mnot a line")
        XCTAssertEqual(lines[1], "\u{1B}[0m")
        XCTAssertTrue(lines[2].contains("[Index]") && lines[2].contains(conf.path), lines[2])
        XCTAssertEqual(lines[3], "\u{2026} (+6 more lines)")

        try "border_px=2\n".write(to: conf, atomically: true, encoding: .utf8)
        r.server.reloadConfig()
        XCTAssertNil(fake.nagArgv, "no errors: the nag is gone")
    }

    func testEditorsLineArguments() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let conf = dir.appendingPathComponent("config.conf")
        try "foo_bar=1\n".write(to: conf, atomically: true, encoding: .utf8)
        let editor = getenv("EDITOR").map { String(cString: $0) }
        defer { if let editor { setenv("EDITOR", editor, 1) } else { unsetenv("EDITOR") } }

        let r = EngineRig()
        let fake = try XCTUnwrap(r.server.system as? FakeWindowSystem)
        r.server.configURL = conf
        for (e, cmd) in [("/usr/local/bin/code --wait", "/usr/local/bin/code --wait -g '\(conf.path):1'"),
                         ("hx", "hx '\(conf.path):1'"), ("subl", "subl '\(conf.path)'")] {
            setenv("EDITOR", e, 1)
            r.server.reloadConfig()
            XCTAssertEqual(fake.nagArgv?.last, cmd)
        }
    }

    func testWlrLogRespectsTheLevel() {
        let before = wlrLogGetVerbosity()
        defer { wlrLogInit(before) }
        wlrLogInit(.error)
        var asked = false
        wlrLog(.debug, { asked = true; return "x" }())
        XCTAssertFalse(asked, "a debug message is not even made at WLR_ERROR")
    }
}

@MainActor
final class ConfigWatchPathTests: MangoTestCase {
    func testASymlinkedConfigIsWatchedAtItsTarget() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dotfiles"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("dotfiles/config.conf")
        try "border_px=2\n".write(to: real, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.conf")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "dotfiles/config.conf")

        let r = EngineRig()
        let fake = try XCTUnwrap(r.server.system as? FakeWindowSystem)
        r.server.configURL = link
        r.server.reloadConfig()
        XCTAssertEqual(fake.watchedConfig.map(\.path), [real.path])
    }
}
