import Foundation

// not in mango: a String as a Result's error
extension String: @retroactive Error {}

// not in mango: an error kept as well as printed, for mango -p and the tests
public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public var file: String
    public var line: Int
    public var message: String
    /// mango_error's verbosity: WLR_ERROR, or WLR_INFO for a binding conflict.
    public var verbosity: WlrLogImportance
    /// Followed by report_config_line_error for the line (not a binding conflict).
    public var reportsLine: Bool

    public init(file: String, line: Int, message: String, verbosity: WlrLogImportance = .error, reportsLine: Bool = true) {
        self.file = file; self.line = line; self.message = message
        self.verbosity = verbosity; self.reportsLine = reportsLine
    }

    public var description: String {
        line > 0 ? "\(file):\(line): \(message)" : "\(file): \(message)"
    }

    /// The error as mango prints it: mango_error, then report_config_line_error with the line as read.
    public func emit() {
        if !message.isEmpty { mangoError(false, verbosity, message + "\n") }
        guard reportsLine, line > 0 else { return }
        var text = ""
        if let data = FileManager.default.contents(atPath: file) {
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            if line <= lines.count { text = lines[line - 1] + (line < lines.count ? "\n" : "") }
        }
        reportConfigLineError(file, line, text)
    }
}

// not in mango: \033[1m\033[31m%s\033[0m, which mango's config errors put round a value
func mangoHighlight(_ s: String) -> String { "\u{1B}[1m\u{1B}[31m\(s)\u{1B}[0m" }

/// mango report_config_line_error (value_parse.c)
public func reportConfigLineError(_ fullPath: String, _ lineNumber: Int, _ line: String) {
    mangoErrorUntagged(.info,
                       "\u{1B}[1;31m╰─\u{1B}[1;33m[Index]\u{1B}[0m "
                       + "\u{1B}[1;36m\(fullPath)\u{1B}[0m:\u{1B}[1;35m\(lineNumber)\u{1B}[0m\n"
                       + "   \u{1B}[1;36m╰─\u{1B}[0;33m\(line)\u{1B}[0m\n\n")
}

public struct ParsedConfig {
    public var config: Config
    public var errors: [ConfigError]
    /// Not in mango: the port's notes on lines it cannot honour or that are its own
    /// (ConfigPort), carried for `mango -p`.
    public var notes: [ConfigNote] = []
    public var sourcedFiles: [URL]

    public init(config: Config, errors: [ConfigError], sourcedFiles: [URL]) {
        self.config = config; self.errors = errors; self.sourcedFiles = sourcedFiles
    }
}

public enum ConfigParser {
    static let maxValueBytes = 255

    // not in mango: parse_config's choice of the user's file (load.c), without its SYSCONFDIR fallback
    public static func defaultConfigURL() -> URL {
        let dir = URL(fileURLWithPath: ConfigOptions.homeDirectory(), isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mango", isDirectory: true)
        let conf = dir.appendingPathComponent("config.conf", isDirectory: false)
        let toml = dir.appendingPathComponent("config.toml", isDirectory: false)
        let fm = FileManager.default
        return !fm.fileExists(atPath: conf.path) && fm.fileExists(atPath: toml.path) ? toml : conf
    }

    // not in mango: `text`, the file's text given instead of read, named `name`; `emits`, the
    // errors printed as they are found (mango's server), or only kept (mango -p, the tests)
    public static func parseConfig(fileAt url: URL, text: (String, name: String)? = nil, emits: Bool = false) -> ParsedConfig {
        var state = ParserState(baseDirectory: url.deletingLastPathComponent())
        state.emits = emits
        state.parseConfigFile(url.standardizedFileURL, mustExist: true, from: nil, text: text)
        state.recordConfigLineError(text?.name ?? url.standardizedFileURL.path, 0, failed: false)
        state.config.overrideConfig()
        state.checkKeyBindingConflicts()
        var parsed = ParsedConfig(config: state.config, errors: state.errors, sourcedFiles: state.sourcedFiles)
        parsed.notes = state.notes
        return parsed
    }

    /// mango parse_option (option_defs.c), for a caller without a file (setoption)
    // not in mango: `baseDirectory`, where a relative source path is read from
    @discardableResult
    public static func parseOption(_ config: inout Config, _ key: String, _ value: String, _ lineNumber: Int,
                                   baseDirectory: URL) -> Bool {
        var state = ParserState(baseDirectory: baseDirectory)
        state.emits = true
        state.config = config
        let ok = state.parseOption(key: key, value: value, file: "", line: lineNumber)
        state.recordConfigLineError("", lineNumber, failed: false)
        config = state.config
        return ok
    }

    /// Not in mango: parsing config text without a file.
    public static func parse(text: String, baseDirectory: URL?, fileName: String) -> ParsedConfig {
        let base = baseDirectory ?? defaultConfigURL().deletingLastPathComponent()
        return parseConfig(fileAt: base.appendingPathComponent(fileName), text: (text, fileName))
    }

    public enum Format: Equatable { case conf, toml }

    public static func detectConfigFormat(fileName: String, text: String) -> Format {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "toml" { return .toml }
        if ext == "conf" { return .conf }
        var inComment = false
        for ch in text {
            if inComment { if ch == "\n" { inComment = false }; continue }
            if ch == "#" { inComment = true; continue }
            if ch.isWhitespace { continue }
            return ch == "[" ? .toml : .conf
        }
        return .conf
    }

    static func removeComment(_ line: String) -> String {
        var quote: Character?
        var prev: Character?
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#", let p = prev, p.isWhitespace {
                return String(line[..<idx])
            }
            prev = c
            idx = line.index(after: idx)
        }
        return line
    }

    static func stripQuotes(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" else { return s }
        return trimWhitespace(s.dropFirst().dropLast())
    }

    /// mango trim_whitespace (value_parse.c)
    static func trimWhitespace(_ s: some StringProtocol) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
    }

    static func isValidVarName(_ name: String) -> Bool {
        guard let f = name.unicodeScalars.first, f == "_" || (f.isASCII && CharacterSet.letters.contains(f)) else {
            return false
        }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    static func expandConfigVariables(_ value: String, vars: [String: String]) -> String {
        guard value.contains("$"), !vars.isEmpty else { return value }
        let chars = Array(value)
        var out = ""
        var i = 0
        func isNameStart(_ c: Character) -> Bool { c == "_" || (c.isASCII && c.isLetter) }
        func isNameChar(_ c: Character) -> Bool { c == "_" || (c.isASCII && (c.isLetter || c.isNumber)) }
        while i < chars.count {
            if chars[i] == "$", i + 1 < chars.count {
                if chars[i + 1] == "{", let close = chars[(i + 2)...].firstIndex(of: "}") {
                    let name = String(chars[(i + 2)..<close])
                    if !name.isEmpty, let v = vars[name] { out += v } else { out += String(chars[i...close]) }
                    i = close + 1
                    continue
                }
                if isNameStart(chars[i + 1]) {
                    var j = i + 1
                    while j < chars.count, isNameChar(chars[j]) { j += 1 }
                    let name = String(chars[(i + 1)..<j])
                    if let v = vars[name] { out += v } else { out += String(chars[i..<j]) }
                    i = j
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}

// not in mango: a binding's file_index and line_number, kept beside it
package struct BindingLocation {
    var file: String
    var line: Int
}

// not in mango: the state of one parse (mango's globals for it), and what the port and mango -p keep of it
package struct ParserState {
    var config = Config()
    var errors: [ConfigError] = []
    var notes: [ConfigNote] = []
    var sourcedFiles: [URL] = []
    var emits = false
    var vars: [String: String] {
        get { config.vars }
        set { config.vars = newValue }
    }
    var keyMode: String {
        get { config.keymode }
        set { config.keymode = newValue }
    }
    let baseDirectory: URL
    var includeStack: [String] = []
    // not in mango: mango_error's messages for the line being parsed, kept until the line is done
    var lineErrors: [String] = []

    var keyLocs: [BindingLocation] = []
    var mouseLocs: [BindingLocation] = []
    var axisLocs: [BindingLocation] = []
    var gestureLocs: [BindingLocation] = []

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // not in mango: check_key_binding_conflicts, and the mouse, axis and gesture checks
    // (check_simple_binding_conflicts) here too
    mutating func checkKeyBindingConflicts() {
        func report(_ kind: String, _ mode: String, _ a: BindingLocation, _ b: BindingLocation) {
            let e = ConfigError(file: b.file, line: b.line,
                                message: "\(kind) conflict in keymode \(mode):\n"
                                    + "  File \"\(a.file)\", line \(a.line)\n"
                                    + "  File \"\(b.file)\", line \(b.line)",
                                verbosity: .info, reportsLine: false)
            errors.append(e)
            if emits { e.emit() }
        }
        func modeOf(_ a: String, _ b: String) -> String? {
            a == "common" || b == "common" ? "common" : (a == b ? a : nil)
        }
        // not in mango: wlroots' modifier bits, which compare_keybind_by_key_only sorts by
        func wlrMod(_ m: Modifiers) -> Int {
            (m.contains(.shift) ? 1 : 0) | (m.contains(.ctrl) ? 4 : 0) | (m.contains(.alt) ? 8 : 0)
                | (m.contains(.hyper) ? 32 : 0) | (m.contains(.superKey) ? 64 : 0) | (m.contains(.fn) ? 256 : 0)
        }
        let keys = config.keyBindings
        func sortKey(_ i: Int) -> (Int, Int, Int) {
            (wlrMod(keys[i].mods), keys[i].flags.contains(.keysym) ? 1 : 0, Int(keys[i].keyCodes.first ?? 0))
        }
        let sorted = keys.indices.filter { !keys[$0].keyCodes.isEmpty }.sorted { sortKey($0) < sortKey($1) }
        var i = 0
        while i < sorted.count {
            var j = i
            while j < sorted.count && sortKey(sorted[j]) == sortKey(sorted[i]) { j += 1 }
            for a in i..<j {
                for b in (a + 1)..<max(a + 1, j) {
                    let ka = keys[sorted[a]], kb = keys[sorted[b]]
                    guard let mode = modeOf(ka.mode, kb.mode),
                          !(ka.flags.contains(.allowConflict) && kb.flags.contains(.allowConflict)) else { continue }
                    report("Key binding", mode, keyLocs[sorted[a]], keyLocs[sorted[b]])
                }
            }
            i = j
        }
        let mice = config.mouseBindings
        for i in mice.indices {
            for j in mice.indices where j > i && mice[i].mods == mice[j].mods && mice[i].button == mice[j].button {
                if let mode = modeOf(mice[i].mode, mice[j].mode) { report("mousebind", mode, mouseLocs[i], mouseLocs[j]) }
            }
        }
        // not in mango: ALLDIR is a nil direction that is not isUndir, UNDIR a nil one that is
        func sameDir(_ a: Direction?, _ aUndir: Bool, _ b: Direction?, _ bUndir: Bool) -> Bool {
            (a == nil && !aUndir) || (b == nil && !bUndir) || (a == b && aUndir == bUndir)
        }
        let axes = config.axisBindings
        for i in axes.indices {
            for j in axes.indices where j > i && axes[i].mods == axes[j].mods
                && sameDir(axes[i].direction, axes[i].isUndir, axes[j].direction, axes[j].isUndir) {
                if let mode = modeOf(axes[i].mode, axes[j].mode) { report("axisbind", mode, axisLocs[i], axisLocs[j]) }
            }
        }
        let gestures = config.gestureBindings
        for i in gestures.indices {
            for j in gestures.indices where j > i && gestures[i].mods == gestures[j].mods
                && gestures[i].fingers == gestures[j].fingers
                && sameDir(gestures[i].direction, gestures[i].isUndir, gestures[j].direction, gestures[j].isUndir) {
                if let mode = modeOf(gestures[i].mode, gestures[j].mode) {
                    report("gesturebind", mode, gestureLocs[i], gestureLocs[j])
                }
            }
        }
    }

    /// Not in mango: keeps a note of the port's (ConfigPort) on a line.
    mutating func note(_ file: String, _ line: Int, _ kind: ConfigNote.Kind, _ name: String, _ reason: String) {
        notes.append(ConfigNote(file: file, line: line, kind: kind, name: name, reason: reason))
    }

    /// Not in mango: the port's note on a binding's dispatcher (ConfigPort).
    mutating func noteDispatch(_ d: Dispatch, _ file: String, _ line: Int) {
        if let (kind, why) = ConfigParser.port?.dispatcherNote(d.name) { note(file, line, kind, d.name, why) }
    }

    // not in mango: keeps the line's mango_error messages as ConfigErrors, the last followed by
    // report_config_line_error when the line failed
    mutating func recordConfigLineError(_ file: String, _ line: Int, failed: Bool) {
        var messages = lineErrors
        lineErrors = []
        if failed && messages.isEmpty { messages = [""] }
        for (i, m) in messages.enumerated() {
            let e = ConfigError(file: file, line: line, message: m, reportsLine: failed && i == messages.count - 1)
            errors.append(e)
            if emits { e.emit() }
        }
    }

    // not in mango: a line parsed with its own messages, which are kept when it is done
    mutating func withLineErrors(_ file: String, _ line: Int, _ parse: (inout ParserState) -> Bool) {
        let outer = lineErrors
        lineErrors = []
        let ok = parse(&self)
        recordConfigLineError(file, line, failed: !ok)
        lineErrors = outer
    }

    func resolveConfigPath(_ path: String) -> URL {
        if path.hasPrefix("./") {
            return baseDirectory.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
        }
        if path == "~" { return URL(fileURLWithPath: ConfigOptions.homeDirectory(), isDirectory: true) }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: ConfigOptions.homeDirectory() + String(path.dropFirst(1))).standardizedFileURL
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
        return baseDirectory.appendingPathComponent(path).standardizedFileURL
    }

    // not in mango: `from`, the source line's text for the message; `text`, the file's text given instead of read
    @discardableResult
    mutating func parseConfigFile(_ url: URL?, mustExist: Bool, from: String?,
                                  text given: (String, name: String)? = nil) -> Bool {
        let path = given?.name ?? url?.path ?? ""
        if given == nil, let url, !sourcedFiles.contains(url) { sourcedFiles.append(url) }

        // not in mango: a file that sources itself is reported, not read for ever (a mango bug, docs/afvigelser.md §6).
        if includeStack.contains(path) {
            lineErrors.append("Recursive source of \(path) ignored")
            return false
        }

        let text: String
        if let given {
            text = given.0
        } else {
            var isDir: ObjCBool = false
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                if mustExist { lineErrors.append("Failed to open config file: \(mangoHighlight(from ?? path))") }
                return !mustExist
            }
            // a directory opens and reads as nothing
            text = isDir.boolValue ? "" : FileManager.default.contents(atPath: path)
                .map { String(data: $0, encoding: .utf8) ?? String(decoding: $0, as: UTF8.self) } ?? ""
        }

        includeStack.append(path)
        let ok: Bool
        switch ConfigParser.detectConfigFormat(fileName: path, text: text) {
        case .conf: ok = parseConfStream(text, fileName: path)
        case .toml: ok = parseTomlStream(text, fileName: path)
        }
        includeStack.removeLast()
        return ok
    }

    @discardableResult
    mutating func parseConfStream(_ text: String, fileName: String) -> Bool {
        var parseCorrect = true
        var lineNumber = 0
// not in mango: Swift reads "\r\n" as one Character, so CRLF is normalised first.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawSub in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let raw = String(rawSub)
            if raw.isEmpty || raw.hasPrefix("#") { continue }
            withLineErrors(fileName, lineNumber) { state in
                let ok = state.parseConfigLine(raw, file: fileName, line: lineNumber)
                if !ok { parseCorrect = false }
                return ok
            }
        }
        return parseCorrect
    }

    mutating func parseConfigLine(_ line: String, file: String, line lineNumber: Int) -> Bool {
        let processed = ConfigParser.removeComment(line)
        guard let eq = processed.firstIndex(of: "="), eq != processed.startIndex,
              processed.index(after: eq) != processed.endIndex else {
            lineErrors.append("Invalid line format: \(mangoHighlight(line + "\n"))")
            return false
        }
        if processed[processed.index(after: eq)...].utf8.count > ConfigParser.maxValueBytes {
            lineErrors.append("Configuration value exceeds \(ConfigParser.maxValueBytes) bytes: \(mangoHighlight(line + "\n"))")
            return false
        }
        let key = ConfigParser.trimWhitespace(processed[..<eq])
        let value = ConfigParser.stripQuotes(ConfigParser.trimWhitespace(processed[processed.index(after: eq)...]))
        return applyOptionExpanded(key, value, file: file, line: lineNumber)
    }

    mutating func applyOptionExpanded(_ key: String, _ value: String, file: String, line: Int) -> Bool {
        parseOption(key: key, value: ConfigParser.expandConfigVariables(value, vars: vars), file: file, line: line)
    }

    /// mango parse_option (option_defs.c)
    // not in mango: the file and line for the port's notes; the options are ConfigOptions.parseOption's
    mutating func parseOption(key: String, value: String, file: String, line: Int) -> Bool {
        if key == "key_mode" {
            keyMode = String(decoding: value.utf8.prefix(27), as: UTF8.self)
            return true
        }
        if key == "var" {
            guard let comma = value.firstIndex(of: ",") else {
                lineErrors.append("Invalid variable format (expected \u{1B}[1mname,value\u{1B}[0m): \(mangoHighlight(value))")
                return false
            }
            let name = ConfigParser.trimWhitespace(value[..<comma])
            let v = ConfigParser.trimWhitespace(value[value.index(after: comma)...])
            guard ConfigParser.isValidVarName(name) else {
                lineErrors.append("Invalid variable name (allowed: [A-Za-z_][A-Za-z0-9_]*): \(mangoHighlight(name))")
                return false
            }
            vars[name] = v
            return true
        }
        if key == "window_rule" || key == "window_rule_once" {
            let (rule, ok) = RuleParser.parseWindowRule(value, once: key == "window_rule_once", errors: &lineErrors)
            if let rule { config.windowRules.append(rule) }
            for (field, _) in RuleParser.tokens(value) {
                if let (kind, n) = ConfigParser.port?.windowRuleNote(field) { note(file, line, kind, "window_rule \(field)", n) }   // not in mango: the port's side
            }
            return ok
        }
        if key == "tag_rule" {
            let (rule, ok) = RuleParser.parseTagRule(value, errors: &lineErrors)
            config.tagRules.append(rule)
            return ok
        }
        if BindingParser.isKeyBindKeyword(key) {
            guard let b = BindingParser.parseKeyBinding(keyword: key, value: value, mode: keyMode, errors: &lineErrors) else {
                return false
            }
            guard !b.keyCodes.isEmpty else { return true }
            config.keyBindings.append(b); keyLocs.append(BindingLocation(file: file, line: line))
            noteDispatch(b.dispatch, file, line)
            return true
        }
        if key.hasPrefix("mousebind") {
            guard let b = BindingParser.parseMouseBinding(value: value, mode: keyMode, errors: &lineErrors) else { return false }
            config.mouseBindings.append(b); mouseLocs.append(BindingLocation(file: file, line: line))
            noteDispatch(b.dispatch, file, line)
            return true
        }
        if key.hasPrefix("axisbind") {
            guard let b = BindingParser.parseAxisBinding(value: value, mode: keyMode, errors: &lineErrors) else { return false }
            config.axisBindings.append(b); axisLocs.append(BindingLocation(file: file, line: line))
            noteDispatch(b.dispatch, file, line)
            return true
        }
        if key.hasPrefix("switchbind") {
            note(file, line, .noEffect, key, ConfigParser.port?.optionNote(key, applied: false)?.1 ?? "")   // not in mango: the port's side
            return true
        }
        if key.hasPrefix("gesturebind") {
            guard let b = BindingParser.parseGestureBinding(value: value, mode: keyMode, errors: &lineErrors) else { return false }
            config.gestureBindings.append(b); gestureLocs.append(BindingLocation(file: file, line: line))
            noteDispatch(b.dispatch, file, line)
            return true
        }
        if key.hasPrefix("source") {
            parseConfigFile(value.isEmpty ? nil : resolveConfigPath(value), mustExist: !key.hasPrefix("source_optional"), from: value)
            return true
        }

        switch ConfigOptions.parseOption(key: key, value: value, to: &config) {
        case .applied:
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: true) { note(file, line, kind, key, n) }   // not in mango: the port's side
            return true
        case .ignored:
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: false) { note(file, line, kind, key, n) }   // not in mango: the port's side
            return true
        case .unknown:
            lineErrors.append("Unknown keyword: \(mangoHighlight(key))")
            return false
        case .invalid(let msg, let earlier):
            lineErrors += earlier + [msg]
            return false
        }
    }
}

public enum BindingParser {
/// Not in mango: parse_option's binding branches, apart for its two callers; `errors`, where
/// mango_error prints, and nil where mango returns false.
    public static func isKeyBindKeyword(_ keyword: String) -> Bool {
        guard keyword.hasPrefix("bind") else { return false }
        return keyword.dropFirst(4).allSatisfy { "s|lrpc".contains($0) }
    }

    public static func parseBindFlags(forKeyword keyword: String) -> KeyBindingFlags {
        var f: KeyBindingFlags = []
        for c in keyword.dropFirst(4) {
            switch c {
            case "s": f.insert(.keysym)
            case "l": f.insert(.locked)
            case "r": f.insert(.release)
            case "p": f.insert(.passthrough)
            case "c": f.insert(.allowConflict)
            default: break
            }
        }
        return f
    }

    static func parseKeyBinding(keyword: String, value: String, mode: String, errors: inout [String]) -> KeyBinding? {
        guard sscanfCount(value) >= 3 else {
            errors.append("Invalid bind format: \(mangoHighlight(value))")
            return nil
        }
        let fields = splitFields(value)
        let keyName = fields[1]
        let codes = ConfigParser.port?.keyCodes(keyName) ?? []   // the boundary: xkb's keymap is the port's
        let keyKnown = !codes.isEmpty || keyName.lowercased().hasPrefix("xf86")
        if !keyKnown { errors.append("Unknown key: \(mangoHighlight(keyName))") }
        let mods = Modifiers.parse(fields[0]) { errors.append($0) }
        var dispatch: Dispatch?
        switch parseBindDispatch(Array(fields[2...])) {
        case .success(let d): dispatch = d
        case .failure(let msg): errors.append(msg)
        }
        guard let mods, let dispatch, keyKnown else { return nil }
        return KeyBinding(mode: mode, mods: mods, keyName: keyName, keyCodes: codes,
                          flags: parseBindFlags(forKeyword: keyword), dispatch: dispatch)
    }

    static func parseMouseBinding(value: String, mode: String, errors: inout [String]) -> MouseBinding? {
        guard sscanfCount(value) >= 3 else {
            errors.append("Invalid mousebind format: \(mangoHighlight(value))")
            return nil
        }
        let fields = splitFields(value)
        let mods = Modifiers.parse(fields[0]) { errors.append($0) }
        let button = parseButton(fields[1]) { errors.append($0) }
        var dispatch: Dispatch?
        switch parseBindDispatch(Array(fields[2...]), in: "mousebind") {
        case .success(let d): dispatch = d
        case .failure(let msg): errors.append(msg)
        }
        guard let mods, let button, let dispatch else { return nil }
        return MouseBinding(mode: mode, mods: mods, button: button, dispatch: dispatch)
    }

    static func parseAxisBinding(value: String, mode: String, errors: inout [String]) -> AxisBinding? {
        guard sscanfCount(value) >= 3 else {
            errors.append("Invalid axisbind format: \(mangoHighlight(value))")
            return nil
        }
        let fields = splitFields(value)
        let mods = Modifiers.parse(fields[0]) { errors.append($0) }
        let dir = Direction(mangoName: fields[1])
        let undir = dir == nil && fields[1].lowercased() != "alldir"
        var dispatch: Dispatch?
        switch parseBindDispatch(Array(fields[2...]), in: "axisbind") {
        case .success(let d): dispatch = d
        case .failure(let msg): errors.append(msg)
        }
        guard let mods, let dispatch else { return nil }
        var b = AxisBinding(mode: mode, mods: mods, direction: dir, dispatch: dispatch)
        b.isUndir = undir
        return b
    }

    static func parseGestureBinding(value: String, mode: String, errors: inout [String]) -> GestureBinding? {
        guard sscanfCount(value) >= 4 else {
            errors.append("Invalid gesturebind format: \(mangoHighlight(value))")
            return nil
        }
        let fields = splitFields(value)
        let mods = Modifiers.parse(fields[0]) { errors.append($0) }
        let dir = Direction(mangoName: fields[1])
        let undir = dir == nil && fields[1].lowercased() != "alldir"
        let fingers = ValueParse.atoi(fields[2])
        var dispatch: Dispatch?
        switch parseBindDispatch(Array(fields[3...]), in: "axisbind") {
        case .success(let d): dispatch = d
        case .failure(let msg): errors.append(msg)
        }
        guard let mods, let dispatch else { return nil }
        var b = GestureBinding(mode: mode, mods: mods, direction: dir, fingers: fingers, dispatch: dispatch)
        b.isUndir = undir
        return b
    }

    /// Not in mango: option_defs.c's sscanf fields after func_name and parse_func_name's NULL; the Arg is made at dispatch.
    // not in mango: `kind`, the keyword its "Unknown dispatch in …" names
    public static func parseBindDispatch(_ fields: [String], in kind: String = "bind") -> Result<Dispatch, String> {
        guard let first = fields.first else { return .failure("Missing dispatcher") }
        let name = first.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure("Missing dispatcher") }
        guard Dispatch.isKnown(name) else {
            return .failure("Unknown dispatch in \(kind): \(mangoHighlight(name))")
        }

        var args: [String] = []
        for f in fields.dropFirst() {
            let t = f.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { break }
            args.append(t)
        }

        switch name {
        case "spawn", "spawn_shell":
            let parts = args.prefix { $0 != "0" }
            args = parts.isEmpty ? [] : [parts.joined(separator: ",")]
        case "spawn_on_empty":
            if args.count >= 2 {
                args = [args.dropLast().joined(separator: ","), args.last!]
            }
        case "toggle_named_scratchpad":
            if args.count > 3 {
                args = Array(args[0..<2]) + [args[2...].joined(separator: ",")]
            }
        case "setoption":
            if args.count > 2 {
                args = [args[0], args[1...].joined(separator: ",")]
            }
        default:
            if args.count > 5 {
                args = Array(args[0..<4]) + [args[4...].joined(separator: ",")]
            }
        }
        return .success(Dispatch(name: name, args: args))
    }

    /// Not in mango: comma split standing for sscanf fields.
    static func splitFields(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: false).map { ConfigParser.trimWhitespace($0) }
    }

    /// Not in mango: sscanf's count for "%255[^,],%255[^,],…": the fields before the first empty one.
    static func sscanfCount(_ value: String) -> Int {
        value.split(separator: ",", omittingEmptySubsequences: false).prefix { !$0.isEmpty }.count
    }
}
