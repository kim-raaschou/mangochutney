import XCTest
@testable import Mango
@testable import Port

/// mangonag's Wayland side in a test: what mangonag asks of it, never a bar on the screen.
@MainActor
private final class FakeNagDisplay: NagDisplay {
    var setups = 0
    var forked: [NagButton] = []
    var destroyed = 0
    func nagSetupSurface() { setups += 1 }
    func nagFork(_ button: NagButton) { forked.append(button) }
    func nagDestroySurface() { destroyed += 1 }
}

/// mangonag (mangonag/mangonag.c): its options, its message, its buttons and its text, as mango's.
@MainActor
final class MangonagTests: MangoTestCase {
    private var display = FakeNagDisplay()

    override func setUp() async throws {
        await MainActor.run { display = FakeNagDisplay(); nag = NagState() }
    }

    override func tearDown() async throws {
        await MainActor.run { nag = NagState() }
    }

    @discardableResult
    private func run(_ args: [String], stdin: String = "") -> Int32 {
        mangonagMain(["mangonag"] + args, stdin: stdin, display: display)
    }

    func testErrorNagsArgumentsAsMangonag() {
        XCTAssertEqual(run(["-o", "Built-in", "-t", "error", "-e", "top", "-l", "-s", "Close",
                            "-b", "Edit", "nvim +2 '/x/config.conf'"], stdin: "[ERROR]: one\ntwo\n"), EXIT_SUCCESS)
        XCTAssertEqual(display.setups, 1)
        XCTAssertTrue(nag.display === display)
        XCTAssertTrue(nag.running)
        XCTAssertEqual(nag.outputName, "Built-in")
        XCTAssertEqual(nag.type, typeError)
        XCTAssertEqual(nag.edge, .top)
        XCTAssertEqual(nag.font, "monospace 13")
        XCTAssertEqual(nag.message, "[ERROR]: one\ntwo", "stdin as the message, its trailing newline gone")
        XCTAssertEqual(nag.buttons.map(\.text), ["Edit", "Close"], "the dismiss button last")
        XCTAssertEqual(nag.buttons[0].action, "nvim +2 '/x/config.conf'")
        XCTAssertTrue(nag.buttons[0].terminal)
        XCTAssertFalse(nag.buttons[0].dismiss)
        XCTAssertNil(nag.buttons[1].action)
        XCTAssertFalse(nag.buttons[1].terminal)
        XCTAssertTrue(nag.buttons[1].dismiss)
    }

    func testDefaults() {
        run([])
        XCTAssertNil(nag.message)
        XCTAssertEqual(nag.type, typeError)
        XCTAssertEqual(nag.layer, .top)
        XCTAssertEqual(nag.timeoutMs, 0)
        XCTAssertEqual(nag.buttons.map(\.text), ["X"])
    }

    func testLongOptionsAsShortOnes() {
        run(["--type=warning", "--message", "hi", "--edge=bottom", "--layer", "overlay", "--timeout", "500",
             "--font=Mono 9", "--dismiss-button="])
        XCTAssertEqual(nag.type, typeWarning)
        XCTAssertEqual(nag.message, "hi")
        XCTAssertEqual(nag.edge, .bottom)
        XCTAssertEqual(nag.layer, .overlay)
        XCTAssertEqual(nag.timeoutMs, 500)
        XCTAssertEqual(nag.font, "Mono 9")
        XCTAssertTrue(nag.buttons.isEmpty, "an empty dismiss text: no dismiss button")
    }

    func testTypesAndLayers() {
        run(["-t", "info", "-y", "bottom"])
        XCTAssertEqual(nag.type, typeInfo)
        XCTAssertEqual(nag.layer, .bottom)
        run(["-t", "nonsense", "-y", "nonsense", "-e", "left"])
        XCTAssertEqual(nag.type, typeError)
        XCTAssertEqual(nag.layer, .top)
        XCTAssertEqual(nag.edge, .top)
    }

    func testButtonsTakeTheirActionOnlyWhenItIsNoOption() {
        run(["-B", "Run", "-z", "Go", "true", "-Z", "Quiet", "", "-b", "Last"])
        XCTAssertEqual(nag.buttons.map(\.text), ["Run", "Go", "Quiet", "Last", "X"])
        XCTAssertEqual(nag.buttons.map(\.action), [nil, "true", "", nil, nil])
        XCTAssertEqual(nag.buttons.map(\.terminal), [false, true, false, true, false])
        XCTAssertEqual(nag.buttons.map(\.dismiss), [false, true, true, false, true])
    }

    func testHelpAndUnknownOptionsShowNoBar() {
        XCTAssertEqual(run(["-h"]), EXIT_SUCCESS)
        XCTAssertEqual(run(["--help"]), EXIT_SUCCESS)
        XCTAssertEqual(run(["-q"]), EXIT_FAILURE)
        XCTAssertEqual(run(["--nonsense"]), EXIT_FAILURE)
        XCTAssertEqual(run(["-m"]), EXIT_FAILURE, "an option without its argument")
        XCTAssertEqual(display.setups, 0)
    }

    func testDetailsAfterTheMessage() {
        run(["-m", "head", "-l"], stdin: "a\nb \t\r\n\n")
        XCTAssertEqual(nag.message, "head\na\nb")
        run(["-l"], stdin: "")
        XCTAssertNil(nag.message, "nothing on stdin: no details")
        run(["-m", "", "-l"], stdin: "a")
        XCTAssertEqual(nag.message, "a")
        run(["-l", "-l"], stdin: "a")
        XCTAssertNil(nag.message, "stdin read to its end the first time")
    }

    func testFourLinesAtMost() {
        run(["-m", "1\n2\n3\n4\n5\n6"])
        XCTAssertEqual(nag.message, "1\n2\n3\n\u{1B}[0m\u{2026} (+3 more)")
        XCTAssertEqual(nagLimitLines("a\nb\nc\nd", 4), "a\nb\nc\nd")
    }

    func testTruncateLines() {
        XCTAssertEqual(nagTruncateLines("\u{1B}[1mabcdef\u{1B}[0m\nxy", 3), "\u{1B}[1mabc\u{1B}[0m\u{2026}\nxy")
        XCTAssertEqual(nagTruncateLines("æøåæ", 3), "æøå\u{1B}[0m\u{2026}", "code points, not bytes")
        XCTAssertEqual(nagTruncateLines(nil, 3), "")
        XCTAssertEqual(nagTruncateLines("abc\n", 3), "abc\n")
    }

    func testClickRunsTheButtonUnderThePointer() {
        run(["-B", "Run", "echo hi", "-s", "Close"])
        nag.buttons[0].outerX = 100; nag.buttons[0].outerY = 2; nag.buttons[0].outerWidth = 40; nag.buttons[0].outerHeight = 20
        nag.buttons[1].outerX = 160; nag.buttons[1].outerY = 2; nag.buttons[1].outerWidth = 40; nag.buttons[1].outerHeight = 20

        nagPointerMotion(140, 10)
        nagPointerButton(btnLeft, pressed: true)
        XCTAssertTrue(display.forked.isEmpty, "the right and bottom edges are outside")

        nagPointerMotion(100, 2)
        nagPointerButton(btnLeft + 1, pressed: true)
        nagPointerButton(btnLeft, pressed: false)
        XCTAssertTrue(display.forked.isEmpty, "only a left press")

        nagPointerButton(btnLeft, pressed: true)
        XCTAssertEqual(display.forked.map(\.action), ["echo hi"])
        XCTAssertTrue(nag.running, "Run is no dismiss button")

        nagPointerMotion(170, 10)
        nagPointerButton(btnLeft, pressed: true)
        XCTAssertEqual(display.forked.count, 1, "the dismiss button has no action")
        XCTAssertFalse(nag.running)

        nagDestroy()
        XCTAssertEqual(display.destroyed, 1)
        XCTAssertNil(nag.display)
        XCTAssertTrue(nag.buttons.isEmpty)
    }

    func testRunActionDismissesBeforeItsEmptyActionReturns() {
        nag.running = true
        nag.display = display
        nagRunAction(NagButton(text: "x", action: "", terminal: false, dismiss: true))
        XCTAssertFalse(nag.running)
        XCTAssertTrue(display.forked.isEmpty)
        nagRunAction(nil)
    }

    func testEscapeAndClosedEndTheLoop() {
        run([])
        nagKeyboardKey(1, pressed: false)
        XCTAssertTrue(nag.running)
        nagKeyboardKey(1, pressed: true)
        XCTAssertFalse(nag.running)
        run([])
        nagLayerClosed()
        XCTAssertFalse(nag.running)
        run([])
        nagSignal(SIGTERM)
        XCTAssertFalse(nag.running)
    }

    func testStyleParams() {
        var st = NagStyle()
        nagStyleParams(&st, Array("1;".utf8))
        XCTAssertTrue(st.bold, "a trailing ';' is no reset")
        nagStyleParams(&st, Array("38;5;196".utf8))
        XCTAssertEqual(st.fg, 196)
        XCTAssertFalse(st.truecolor)
        nagStyleParams(&st, Array("48;2;1;2;3;4".utf8))
        XCTAssertTrue(st.bgTrue)
        XCTAssertEqual(st.bgRgb, 0x010203FF)
        XCTAssertTrue(st.underline)
        nagStyleParams(&st, Array("22;39;49".utf8))
        XCTAssertFalse(st.bold)
        XCTAssertEqual(st.fg, -1)
        XCTAssertFalse(st.bgTrue)
        nagStyleParams(&st, Array("38;2;-1;0;0".utf8))
        XCTAssertEqual(st.rgb, 0xFF0000FF, "C's int: -1 << 24, no crash")
        nagStyleParams(&st, [])
        XCTAssertEqual(st, NagStyle())
    }

    func testColors() {
        XCTAssertEqual(nagColor(-1), 0)
        XCTAssertEqual(nagColor(1), 0xDE5959FF)
        XCTAssertEqual(nagColor(16), 0x000000FF)
        XCTAssertEqual(nagColor(196), 0xFF0000FF)
        XCTAssertEqual(nagColor(231), 0xFFFFFFFF)
        XCTAssertEqual(nagColor(232), 0x080808FF)
        XCTAssertEqual(nagColor(255), 0xEEEEEEFF)
    }

    func testAnsiAttrs() {
        var clean = ""
        let attrs = nagAnsiAttrs("[ERROR]: æ \u{1B}[1m\u{1B}[31mkey\u{1B}[0m\n\u{1B}[2mx", &clean)
        XCTAssertEqual(clean, "[ERROR]: æ key\nx")
        XCTAssertEqual(attrs, [
            NagAttr(start: 0, end: 8, foreground: 0x201B14FF, background: 0xEF2929FF, bold: true),
            NagAttr(start: 12, end: 15, foreground: 0xDE5959FF, bold: true),
            NagAttr(start: 16, end: 17, foregroundAlpha: 0x6000),
        ], "byte offsets into the clean text, as pango's")
        XCTAssertEqual(nagAnsiSkip(Array("\u{1B}[31".utf8), 0), 0, "an escape without its end")
    }

    /// The port turns mangonag's attributes into AppKit's, as pango does.
    func testPortsAttributedText() {
        let s = Nag.attributed("[ERROR]: bad \u{1B}[1m\u{1B}[31mkey\u{1B}[0m", font: .systemFont(ofSize: 13), color: .white)
        XCTAssertEqual(s.string, "[ERROR]: bad key")
        XCTAssertEqual(s.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor, Nag.ns(0xEF2929FF))
        XCTAssertEqual(s.attribute(.foregroundColor, at: 13, effectiveRange: nil) as? NSColor, Nag.ns(nagColor(1)))
        XCTAssertEqual(s.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor, .white)
    }
}
