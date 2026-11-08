import Foundation

public let nagMaxLines = 4

public enum NagEdge { case top, bottom }

/// not in mango: zwlr_layer_shell_v1's layers, which -y picks.
public enum NagLayer { case bottom, top, overlay }

public struct NagType: Equatable {
    public var background: UInt32
    public var text: UInt32
    public var buttonBackground: UInt32
    public var buttonText: UInt32
    public var border: UInt32
    public var borderBottom: UInt32

    public init(background: UInt32, text: UInt32, buttonBackground: UInt32, buttonText: UInt32,
                border: UInt32, borderBottom: UInt32) {
        self.background = background
        self.text = text
        self.buttonBackground = buttonBackground
        self.buttonText = buttonText
        self.border = border
        self.borderBottom = borderBottom
    }
}

public let typeError = NagType(
    background: 0x201B14FF,
    text: 0xE1D1B6FF,
    buttonBackground: 0x3A332AFF,
    buttonText: 0xE1D1B6FF,
    border: 0xEF2929FF,
    borderBottom: 0xEF2929FF
)

public let typeWarning = NagType(
    background: 0xFFA800FF,
    text: 0x000000FF,
    buttonBackground: 0xFFC100FF,
    buttonText: 0x000000FF,
    border: 0xAB7100FF,
    borderBottom: 0xAB7100FF
)

public let typeInfo = NagType(
    background: 0x323232FF,
    text: 0xFFFFFFFF,
    buttonBackground: 0x333333FF,
    buttonText: 0xFFFFFFFF,
    border: 0x222222FF,
    borderBottom: 0x444444FF
)

public struct NagButton {
    public var text: String
    public var action: String?
    public var terminal: Bool
    public var dismiss: Bool

    public var x = 0, y = 0, width = 0, height = 0
    public var outerX = 0, outerY = 0, outerWidth = 0, outerHeight = 0
}

public struct NagState {
    /// not in mango: the port's side of the Wayland connection (outputs, layer surface, seat).
    public var display: NagDisplay?

    public var outputName: String?

    public var layer = NagLayer.top

    public var message: String?
    public var details: String?
    public var type = typeError
    public var font: String?

    public var edge = NagEdge.top
    public var timeoutMs: Int32 = 0
    public var dismissText: String?

    public var buttons: [NagButton] = []

    public var running = false
}

@MainActor public var nag = NagState()
@MainActor var nagPointerX = 0.0
@MainActor var nagPointerY = 0.0

/// not in mango: mangonag's stdin, the text error_nag pipes in (mangonag runs in mango's process).
@MainActor private var nagStdin: String?

@MainActor public func nagSignal(_ signalNumber: Int32) {
    nag.running = false
}

@MainActor public func nagRunAction(_ button: NagButton?) {
    guard let button else { return }
    if button.dismiss {
        nag.running = false
    }
    if button.action == nil || button.action!.isEmpty {
        return
    }

    nag.display?.nagFork(button)   // not in mango: the port forks (mangonag runs in mango's process)
}

public struct NagStyle: Equatable {
    public var fg: Int32 = -1
    public var truecolor = false
    public var rgb: UInt32 = 0
    public var bg: Int32 = -1
    public var bgTrue = false
    public var bgRgb: UInt32 = 0
    public var bold = false
    public var dim = false
    public var italic = false
    public var underline = false

    public init() {}
}

let nagPalette: [UInt32] = [
    0x262626FF, 0xDE5959FF, 0x84D082FF, 0xE9B959FF, 0xE9B959FF, 0xD5A7E0FF,
    0xA5DE86FF, 0xE1D1B6FF, 0xC6C09CFF, 0xF57474FF, 0xB3EC7BFF, 0xF1E69FFF,
    0xA3C1E0FF, 0xCAACC6FF, 0xF1E69FFF, 0xF4F4F3FF,
]

public func nagColor(_ index: Int32) -> UInt32 {
    if index < 0 {
        return 0
    }
    if index < 16 {
        return nagPalette[Int(index)]
    }
    if index < 232 {
        let c = index - 16
        var r = c / 36
        var g = (c / 6) % 6
        var b = c % 6
        r = r != 0 ? 55 + r * 40 : 0
        g = g != 0 ? 55 + g * 40 : 0
        b = b != 0 ? 55 + b * 40 : 0
        return UInt32(truncatingIfNeeded: (r << 24) | (g << 16) | (b << 8) | 0xFF)
    }
    let v = 8 &+ (index &- 232) &* 10
    return UInt32(truncatingIfNeeded: (v << 24) | (v << 16) | (v << 8) | 0xFF)
}

func nagStyleReset(_ style: inout NagStyle) {
    style.fg = -1
    style.truecolor = false
    style.rgb = 0
    style.bg = -1
    style.bgTrue = false
    style.bgRgb = 0
    style.bold = false
    style.dim = false
    style.italic = false
    style.underline = false
}

func nagStyleCode(_ style: inout NagStyle, _ code: Int32) {
    if code == 0 {
        nagStyleReset(&style)
    } else if code == 1 {
        style.bold = true
    } else if code == 2 {
        style.dim = true
    } else if code == 3 {
        style.italic = true
    } else if code == 4 {
        style.underline = true
    } else if code == 22 {
        style.bold = false
        style.dim = false
    } else if code == 23 {
        style.italic = false
    } else if code == 24 {
        style.underline = false
    } else if code == 39 {
        style.fg = -1
        style.truecolor = false
    } else if code == 49 {
        style.bg = -1
        style.bgTrue = false
    } else if code >= 30 && code <= 37 {
        style.fg = code - 30
    } else if code >= 90 && code <= 97 {
        style.fg = code - 90 + 8
    } else if code >= 40 && code <= 47 {
        style.bg = code - 40
    } else if code >= 100 && code <= 107 {
        style.bg = code - 100 + 8
    }
}

func nagStyleParams(_ style: inout NagStyle, _ params: [UInt8]) {
    var values: [Int32] = []
    var p = 0

    while p < params.count && params[p] != 0 && values.count < 64 {
        values.append(atoi(String(decoding: params[p...], as: UTF8.self)))
        while p < params.count && params[p] != 0 && params[p] != UInt8(ascii: ";") {
            p += 1
        }
        if p < params.count && params[p] == UInt8(ascii: ";") {
            p += 1
        }
    }
    let count = values.count

    if count == 0 {
        nagStyleReset(&style)
        return
    }

    var i = 0
    while i < count {
        let code = values[i]
        if code == 38 && i + 2 < count && values[i + 1] == 5 {
            style.fg = values[i + 2]
            style.truecolor = false
            i += 2
        } else if code == 38 && i + 4 < count && values[i + 1] == 2 {
            style.rgb = UInt32(truncatingIfNeeded: (values[i + 2] << 24) | (values[i + 3] << 16)
                | (values[i + 4] << 8) | 0xFF)
            style.truecolor = true
            i += 4
        } else if code == 48 && i + 2 < count && values[i + 1] == 5 {
            style.bg = values[i + 2]
            style.bgTrue = false
            i += 2
        } else if code == 48 && i + 4 < count && values[i + 1] == 2 {
            style.bgRgb = UInt32(truncatingIfNeeded: (values[i + 2] << 24) | (values[i + 3] << 16)
                | (values[i + 4] << 8) | 0xFF)
            style.bgTrue = true
            i += 4
        } else {
            nagStyleCode(&style, code)
        }
        i += 1
    }
}

/// not in mango: pango's attributes over the clean text's bytes start..<end, which the port
/// makes (pango_attr_foreground_new, pango_attr_background_new, …).
public struct NagAttr: Equatable {
    public var start: Int
    public var end: Int
    public var foreground: UInt32?
    public var background: UInt32?
    public var bold = false
    public var italic = false
    public var underline = false
    public var foregroundAlpha: UInt16?
}

func nagAttrEmit(_ list: inout [NagAttr], _ style: NagStyle, _ start: Int, _ end: Int) {
    if end <= start {
        return
    }

    var attr = NagAttr(start: start, end: end)

    if style.truecolor || style.fg >= 0 {
        let color = style.truecolor ? style.rgb : nagColor(style.fg)
        attr.foreground = color
    }
    if style.bgTrue || style.bg >= 0 {
        let color = style.bgTrue ? style.bgRgb : nagColor(style.bg)
        attr.background = color
    }
    if style.bold {
        attr.bold = true
    }
    if style.italic {
        attr.italic = true
    }
    if style.underline {
        attr.underline = true
    }
    if style.dim {
        attr.foregroundAlpha = 0x6000
    }
    if attr != NagAttr(start: start, end: end) {
        list.append(attr)   // not in mango: the attributes as one
    }
}

public func nagAnsiSkip(_ text: [UInt8], _ at: Int) -> Int {
    if at >= text.count || text[at] != 0x1B || at + 1 >= text.count || text[at + 1] != UInt8(ascii: "[") {
        return 0
    }

    var i = 2
    while at + i < text.count && text[at + i] != 0
        && !(text[at + i] >= UInt8(ascii: "@") && text[at + i] <= UInt8(ascii: "~")) {
        i += 1
    }
    if at + i >= text.count || text[at + i] == 0 {
        return 0
    }
    return i + 1
}

func nagTagMatch(_ text: [UInt8], _ at: Int) -> (length: Int, fg: UInt32, bg: UInt32)? {
    let tags: [(tag: String, fg: UInt32, bg: UInt32)] = [
        ("[ERROR]", 0x201B14FF, 0xEF2929FF),
        ("[WARN]", 0x201B14FF, 0xEAD96BFF),
        ("[INFO]", 0x201B14FF, 0x729FCFFF),
        ("[DEBUG]", 0x201B14FF, 0x8AE234FF),
    ]

    for t in tags {
        let n = Array(t.tag.utf8)
        if text[at...].starts(with: n) {
            return (n.count, t.fg, t.bg)
        }
    }
    return nil
}

public func nagAnsiAttrs(_ text: String?, _ cleanOut: inout String) -> [NagAttr] {
    let text = Array((text ?? "").utf8)

    var clean: [UInt8] = []
    clean.reserveCapacity(text.count)

    var list: [NagAttr] = []
    var style = NagStyle()
    nagStyleReset(&style)

    var runStart = 0
    var p = 0
    var lineStart = true

    while p < text.count && text[p] != 0 {
        let skip = nagAnsiSkip(text, p)
        if skip > 0 {
            if text[p + skip - 1] == UInt8(ascii: "m") {
                nagAttrEmit(&list, style, runStart, clean.count)
                var n = skip - 3
                if n >= 64 {
                    n = 64 - 1
                }
                nagStyleParams(&style, Array(text[(p + 2)..<(p + 2 + n)]))
                runStart = clean.count
            }
            p += skip
            continue
        }

        if lineStart {
            if let tag = nagTagMatch(text, p) {
                let start = clean.count
                clean += text[p..<(p + tag.length)]
                p += tag.length
                if p < text.count && text[p] == UInt8(ascii: ":") {
                    clean.append(text[p])
                    p += 1
                }
                var tagStyle = NagStyle()
                nagStyleReset(&tagStyle)
                tagStyle.truecolor = true
                tagStyle.rgb = tag.fg
                tagStyle.bgTrue = true
                tagStyle.bgRgb = tag.bg
                tagStyle.bold = true
                nagAttrEmit(&list, tagStyle, start, clean.count)
                runStart = clean.count
                lineStart = false
                continue
            }
            lineStart = false
        }

        if text[p] == UInt8(ascii: "\n") {
            nagAttrEmit(&list, style, runStart, clean.count)
            clean.append(UInt8(ascii: "\n"))
            nagStyleReset(&style)
            runStart = clean.count
            lineStart = true
            p += 1
            continue
        }

        clean.append(text[p])
        p += 1
    }

    nagAttrEmit(&list, style, runStart, clean.count)
    cleanOut = String(decoding: clean, as: UTF8.self)
    return list
}

public let btnLeft: UInt32 = 0x110

@MainActor public func nagPointerButton(_ button: UInt32, pressed: Bool) {
    if button != btnLeft || !pressed {
        return
    }

    for b in nag.buttons {
        if nagPointerX < Double(b.outerX)
            || nagPointerX >= Double(b.outerX + b.outerWidth)
            || nagPointerY < Double(b.outerY)
            || nagPointerY >= Double(b.outerY + b.outerHeight) {
            continue
        }
        nagRunAction(b)
        return
    }
}

@MainActor public func nagPointerEnter(_ sx: Double, _ sy: Double) {
    nagPointerX = sx
    nagPointerY = sy
}

@MainActor public func nagPointerMotion(_ sx: Double, _ sy: Double) {
    nagPointerX = sx
    nagPointerY = sy
}

@MainActor public func nagKeyboardKey(_ key: UInt32, pressed: Bool) {
    if !pressed {
        return
    }
    if key == 1 {
        nag.running = false
    }
}

@MainActor public func nagLayerClosed() {
    nag.running = false
}

let nagLongOptions: [(name: String, shortOption: Character)] = [
    ("message", "m"),
    ("detailed-message", "l"),
    ("type", "t"),
    ("edge", "e"),
    ("layer", "y"),
    ("output", "o"),
    ("font", "f"),
    ("dismiss-button", "s"),
    ("button", "b"),
    ("button-no-terminal", "B"),
    ("button-dismiss", "z"),
    ("button-dismiss-no-terminal", "Z"),
    ("timeout", "T"),
    ("help", "h"),
]

func nagExpandLongOptions(_ argv: [String]) -> [String] {
    var out: [String] = []

    for (i, arg) in argv.enumerated() {
        let a = Array(arg.utf8)
        var value: String?
        var shortOption: Character?

        if i > 0 && a.count > 2 && a[0] == UInt8(ascii: "-") && a[1] == UInt8(ascii: "-") {
            let body = a[2...]
            let eq = body.firstIndex(of: UInt8(ascii: "="))
            let name = eq.map { body[..<$0] } ?? body

            for option in nagLongOptions where Array(option.name.utf8) == Array(name) {
                shortOption = option.shortOption
                break
            }
            if let eq {
                value = String(decoding: a[(eq + 1)...], as: UTF8.self)
            }
        }

        if let shortOption {
            out.append("-" + String(shortOption))
            if let value {
                out.append(value)
            }
            continue
        }

        out.append(arg)
    }

    return out
}

@MainActor func nagAddButton(_ text: String, _ action: String?, _ terminal: Bool, _ dismiss: Bool) {
    nag.buttons.append(NagButton(text: text, action: action, terminal: terminal, dismiss: dismiss))
}

@MainActor func nagReadStdin() -> String? {
    defer { nagStdin = nil }
    guard let buffer = nagStdin, !buffer.isEmpty else { return nil }
    return buffer
}

public func nagLimitLines(_ text: String, _ maxLines: Int) -> String {
    let t = Array(text.utf8)
    var lines = 1
    for c in t where c == UInt8(ascii: "\n") {
        lines += 1
    }
    if lines <= maxLines {
        return text
    }

    let keep = maxLines - 1
    var out: [UInt8] = []

    var p: Int? = 0
    var i = 0
    while i < keep, let start = p {
        let nl = t[start...].firstIndex(of: UInt8(ascii: "\n"))
        out += t[start..<(nl ?? t.count)]
        out.append(UInt8(ascii: "\n"))
        p = nl.map { $0 + 1 }
        i += 1
    }
    out += Array("\u{1B}[0m\u{2026} (+\(lines - keep) more)".utf8)
    return String(decoding: out, as: UTF8.self)
}

public func nagTruncateLines(_ text: String?, _ maxChars: Int) -> String {
    let t = Array((text ?? "").utf8)
    var out: [UInt8] = []

    var p = 0
    while true {
        let nl = t[p...].firstIndex(of: UInt8(ascii: "\n"))
        let len = (nl ?? t.count) - p

        var codepoints = 0
        var cut = len
        var i = 0
        while i < len {
            let skip = nagAnsiSkip(t, p + i)
            if skip > 0 {
                i += skip
                continue
            }
            let c = t[p + i]
            if c & 0xC0 != 0x80 {
                if codepoints == maxChars {
                    cut = i
                    break
                }
                codepoints += 1
            }
            i += 1
        }

        out += t[p..<(p + cut)]
        if cut < len {
            out += Array("\u{1B}[0m\u{2026}".utf8)
        }
        guard let nl else { break }
        out.append(UInt8(ascii: "\n"))
        p = nl + 1
    }
    return String(decoding: out, as: UTF8.self)
}

func usage() {
    fputs("Usage: mangonag [options]\n"
        + "  -m, --message <text>              message text\n"
        + "  -l, --detailed-message            read extra lines from stdin\n"
        + "  -t, --type <error|warning|info>   color preset\n"
        + "  -e, --edge <top|bottom>           edge to anchor to\n"
        + "  -y, --layer <overlay|top|bottom>  layer to appear on\n"
        + "  -o, --output <name>               output to show on\n"
        + "  -f, --font <pango font>           font description\n"
        + "  -s, --dismiss-button <text>       dismiss button text\n"
        + "  -b, --button <text> <command>     terminal button\n"
        + "  -B, --button-no-terminal ...      run directly\n"
        + "  -z, --button-dismiss <text> <cmd> command then dismiss\n"
        + "  -Z, --button-dismiss-no-terminal  run directly then dismiss\n"
        + "  -T, --timeout <ms>                auto dismiss after ms (0 = never)\n"
        + "  -h, --help                        show this help\n", stderr)
}

/// mangonag main (mangonag/mangonag.c)
@discardableResult
@MainActor public func mangonagMain(_ argv: [String], stdin: String, display: NagDisplay) -> Int32 {
    nag = NagState()
    nag.type = typeError
    nag.layer = .top
    // not in mango: the layer surface's anchor is the port's, from nag.edge
    nag.dismissText = "X"
    nag.font = "monospace 13"
    nag.running = true
    nagStdin = stdin   // not in mango: mangonag's stdin (mangonag runs in mango's process)

    let argv = nagExpandLongOptions(argv)
    let argc = Int32(argv.count)
    var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
    defer { cArgv.forEach { free($0) } }

    optreset = 1   // not in mango: getopt from the start (mangonag is a new process each time)
    optind = 1
    func arg() -> String { String(cString: optarg) }

    while case let option = getopt(argc, &cArgv, "m:lt:e:y:o:f:s:b:B:z:Z:T:h"), option != -1 {
        switch Character(Unicode.Scalar(UInt8(truncatingIfNeeded: option))) {
        case "m":
            nag.message = arg()
        case "l":
            nag.details = nagReadStdin()
        case "t":
            if arg() == "warning" {
                nag.type = typeWarning
            } else if arg() == "info" {
                nag.type = typeInfo
            } else {
                nag.type = typeError
            }
        case "e":
            if arg() == "bottom" {
                nag.edge = .bottom
            }
        case "y":
            if arg() == "overlay" {
                nag.layer = .overlay
            } else if arg() == "bottom" {
                nag.layer = .bottom
            } else {
                nag.layer = .top
            }
        case "o":
            nag.outputName = arg()
        case "f":
            nag.font = arg()
        case "s":
            nag.dismissText = arg()
        case "b", "B", "z", "Z":
            let text = arg()
            var action: String?
            if optind < argc && !argv[Int(optind)].hasPrefix("-") {
                action = argv[Int(optind)]
                optind += 1
            }
            nagAddButton(text, action, option == Int32(UInt8(ascii: "b")) || option == Int32(UInt8(ascii: "z")),
                         option == Int32(UInt8(ascii: "z")) || option == Int32(UInt8(ascii: "Z")))
        case "T":
            nag.timeoutMs = atoi(arg())
        case "h":
            usage()
            return EXIT_SUCCESS
        default:
            usage()
            return EXIT_FAILURE
        }
    }

    if let details = nag.details, !details.isEmpty {
        let a = nag.message ?? ""
        nag.message = a + (a.isEmpty ? "" : "\n") + details
    }

    if let dismissText = nag.dismissText, !dismissText.isEmpty {
        nagAddButton(dismissText, nil, false, true)
    }

    if var message = nag.message {
        while let last = message.unicodeScalars.last,
              last == "\n" || last == "\r" || last == " " || last == "\t" {
            message.unicodeScalars.removeLast()
        }
        nag.message = nagLimitLines(message, nagMaxLines)
    }

    // not in mango: no signal handlers; error_nag's nag_kill calls nagSignal
    nag.display = display   // not in mango: the port's display, for wl_display_connect

    nag.display?.nagSetupSurface()   // not in mango: the outputs and nag_setup_surface are the port's

    // not in mango: the loop, its -T timeout and nag_destroy at its end are the port's run loop
    return EXIT_SUCCESS
}

@MainActor public func nagDestroy() {
    nag.display?.nagDestroySurface()   // not in mango: the surface, seat and outputs are the port's

    nag = NagState()
}
