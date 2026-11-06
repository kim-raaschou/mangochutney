import Foundation

extension String: @retroactive Error {}

// not in mango: an error kept for after the parse (mango prints each as the line is read)
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
        mangoError(false, verbosity, message + "\n")
        guard reportsLine, line > 0 else { return }
        var text = ""
        if let data = FileManager.default.contents(atPath: file) {
            let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
            if line <= lines.count { text = lines[line - 1] + (line < lines.count ? "\n" : "") }
        }
        reportConfigLineError(file, line, text)
    }
}

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

    public static func defaultConfigURL() -> URL {
        let dir = URL(fileURLWithPath: ConfigOptions.homeDirectory(), isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mango", isDirectory: true)
        let conf = dir.appendingPathComponent("config.conf", isDirectory: false)
        let toml = dir.appendingPathComponent("config.toml", isDirectory: false)
        let fm = FileManager.default
        return !fm.fileExists(atPath: conf.path) && fm.fileExists(atPath: toml.path) ? toml : conf
    }

    // not in mango: `text`, the file's text given instead of read, named `name`
    public static func parseConfig(fileAt url: URL, text: (String, name: String)? = nil) -> ParsedConfig {
        var state = ParserState(baseDirectory: url.deletingLastPathComponent())
        state.parseConfigFile(url.standardizedFileURL, mustExist: true, from: nil, text: text)
        // not in mango: HYPER is chutney_hyper_modifier, known once the file is read
        for ref in state.hyperRefs {
            guard let mods = Modifiers.parse(ref.mods, hyperModifier: state.config.hyperModifier) else { continue }
            switch ref.kind {
            case .key: state.config.keyBindings[ref.index].mods = mods
            case .mouse: state.config.mouseBindings[ref.index].mods = mods
            case .axis: state.config.axisBindings[ref.index].mods = mods
            case .gesture: state.config.gestureBindings[ref.index].mods = mods
            }
        }
        state.config.overrideConfig()
        state.checkKeyBindingConflicts()
        var parsed = ParsedConfig(config: state.config, errors: state.errors, sourcedFiles: state.sourcedFiles)
        parsed.notes = state.notes
        return parsed
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
        return String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
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

package struct BindingLocation {
    var file: String
    var line: Int
}

package struct ParserState {
    var config = Config()
    var errors: [ConfigError] = []
    var notes: [ConfigNote] = []
    var sourcedFiles: [URL] = []
    var vars: [String: String] = [:]
    var keyMode: String {
        get { config.keymode }
        set { config.keymode = newValue }
    }
    let baseDirectory: URL
    var includeStack: [String] = []

    var keyLocs: [BindingLocation] = []
    var mouseLocs: [BindingLocation] = []
    var axisLocs: [BindingLocation] = []
    var gestureLocs: [BindingLocation] = []

    enum BindingKind { case key, mouse, axis, gesture }
    var hyperRefs: [(kind: BindingKind, index: Int, mods: String)] = []

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // not in mango: the mouse, axis and gesture checks (check_*_binding_conflicts) here too
    mutating func checkKeyBindingConflicts() {
        func report(_ kind: String, _ mode: String, _ a: BindingLocation, _ b: BindingLocation) {
            errors.append(ConfigError(file: b.file, line: b.line,
                                      message: "\(kind) conflict in keymode \(mode):\n"
                                          + "  File \"\(a.file)\", line \(a.line)\n"
                                          + "  File \"\(b.file)\", line \(b.line)",
                                      verbosity: .info, reportsLine: false))
        }
        func modeOf(_ a: String, _ b: String) -> String? {
            a == "common" || b == "common" ? "common" : (a == b ? a : nil)
        }
        let keys = config.keyBindings
        for i in keys.indices {
            let b = keys[i]
            guard let code = b.keyCodes.first else { continue }
            let isSym = b.flags.contains(.keysym)
            for j in keys[..<i].indices {
                let other = keys[j]
                guard other.mods == b.mods && other.keyCodes.first == code && other.flags.contains(.keysym) == isSym,
                      let mode = modeOf(other.mode, b.mode),
                      !(other.flags.contains(.allowConflict) && b.flags.contains(.allowConflict)) else { continue }
                report("Key binding", mode, keyLocs[j], keyLocs[i])
            }
        }
        let mice = config.mouseBindings
        for i in mice.indices {
            let b = mice[i]
            for j in mice[..<i].indices where mice[j].mods == b.mods && mice[j].button == b.button {
                if let mode = modeOf(mice[j].mode, b.mode) { report("mousebind", mode, mouseLocs[j], mouseLocs[i]) }
            }
        }
        let axes = config.axisBindings
        for i in axes.indices {
            let b = axes[i]
            for j in axes[..<i].indices where axes[j].mods == b.mods && axes[j].isUndir == b.isUndir
                && (axes[j].direction == nil || b.direction == nil || axes[j].direction == b.direction) {
                if let mode = modeOf(axes[j].mode, b.mode) { report("axisbind", mode, axisLocs[j], axisLocs[i]) }
            }
        }
        let gestures = config.gestureBindings
        for i in gestures.indices {
            let b = gestures[i]
            for j in gestures[..<i].indices where gestures[j].mods == b.mods && gestures[j].fingers == b.fingers
                && (gestures[j].direction == nil || b.direction == nil || gestures[j].direction == b.direction) {
                if let mode = modeOf(gestures[j].mode, b.mode) { report("gesturebind", mode, gestureLocs[j], gestureLocs[i]) }
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

    mutating func recordConfigLineError(_ file: String, _ line: Int, _ message: String) {
        errors.append(ConfigError(file: file, line: line, message: message))
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

    // not in mango: `from`, the source line for the errors; `text`, the file's text given instead of read
    mutating func parseConfigFile(_ url: URL, mustExist: Bool, from: (String, Int, String)?,
                                  text given: (String, name: String)? = nil) {
        let path = given?.name ?? url.path
        if given == nil && !sourcedFiles.contains(url) { sourcedFiles.append(url) }

        let reportFile = from?.0 ?? path
        let reportLine = from?.1 ?? 0

        // not in mango: a file that sources itself is reported, not read for ever (a mango bug, docs/afvigelser.md §6).
        if includeStack.contains(path) {
            recordConfigLineError(reportFile, reportLine, "Recursive source of \(path) ignored")
            return
        }

        let text: String
        if let given {
            text = given.0
        } else {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
                  let data = FileManager.default.contents(atPath: path) else {
                if mustExist {
                    recordConfigLineError(reportFile, reportLine, "Failed to open config file: \(from?.2 ?? path)")
                }
                return
            }
            text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        }

        includeStack.append(path)
        switch ConfigParser.detectConfigFormat(fileName: path, text: text) {
        case .conf: parseConfStream(text, fileName: path)
        case .toml: parseTomlStream(text, fileName: path)
        }
        includeStack.removeLast()
    }

    mutating func parseConfStream(_ text: String, fileName: String) {
        var lineNumber = 0
// not in mango: Swift reads "\r\n" as one Character, so CRLF is normalised first.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawSub in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let raw = String(rawSub)
            if raw.isEmpty || raw.hasPrefix("#") { continue }
            parseConfigLine(raw, file: fileName, line: lineNumber)
        }
    }

    mutating func parseConfigLine(_ raw: String, file: String, line: Int) {
        let processed = ConfigParser.removeComment(raw)
        guard let eq = processed.firstIndex(of: "="), eq != processed.startIndex,
              processed.index(after: eq) != processed.endIndex else {
            recordConfigLineError(file, line, "Invalid line format: \(raw.trimmingCharacters(in: .whitespaces))")
            return
        }
        let key = processed[..<eq].trimmingCharacters(in: .whitespaces)
        var value = processed[processed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            recordConfigLineError(file, line, "Invalid line format: \(raw.trimmingCharacters(in: .whitespaces))")
            return
        }
        if value.utf8.count > ConfigParser.maxValueBytes {
            recordConfigLineError(file, line, "Configuration value exceeds \(ConfigParser.maxValueBytes) bytes: \(key)")
            return
        }
        value = ConfigParser.stripQuotes(value)
        applyOptionExpanded(key, value, file: file, line: line)
    }

    mutating func applyOptionExpanded(_ key: String, _ value: String, file: String, line: Int) {
        parseOption(key: key, value: ConfigParser.expandConfigVariables(value, vars: vars), file: file, line: line)
    }

    // not in mango: parse_option for a file's line, with the line for its errors and notes (ConfigOptions.parseOption the rest)
    mutating func parseOption(key: String, value: String, file: String, line: Int) {
        switch key {
        case "key_mode":
            keyMode = value.isEmpty ? "default" : value
            return

        case "var":
            guard let comma = value.firstIndex(of: ",") else {
                recordConfigLineError(file, line, "Invalid variable format (expected name,value): \(value)")
                return
            }
            let name = value[..<comma].trimmingCharacters(in: .whitespaces)
            let v = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            guard ConfigParser.isValidVarName(name) else {
                recordConfigLineError(file, line, "Invalid variable name (allowed: [A-Za-z_][A-Za-z0-9_]*): \(name)")
                return
            }
            vars[name] = v
            return

        case "source", "source_optional":
            guard !value.isEmpty else {
                recordConfigLineError(file, line, "Missing path for \(key)")
                return
            }
            parseConfigFile(resolveConfigPath(value), mustExist: key == "source", from: (file, line, value))
            return

        case "mousebind":
            switch BindingParser.parseMouseBinding(value: value, mode: keyMode, hyperModifier: config.hyperModifier) {
            case .failure(let msg): recordConfigLineError(file, line, msg)
            case .success(let b):
                let loc = BindingLocation(file: file, line: line)
                noteHyper(.mouse, value, index: config.mouseBindings.count)
                config.mouseBindings.append(b); mouseLocs.append(loc)
                noteDispatch(b.dispatch, file, line)
            }
            return

        case "axisbind":
            switch BindingParser.parseAxisBinding(value: value, mode: keyMode, hyperModifier: config.hyperModifier) {
            case .failure(let msg): recordConfigLineError(file, line, msg)
            case .success(let b):
                let loc = BindingLocation(file: file, line: line)
                noteHyper(.axis, value, index: config.axisBindings.count)
                config.axisBindings.append(b); axisLocs.append(loc)
                noteDispatch(b.dispatch, file, line)
            }
            return

        case "gesturebind":
            switch BindingParser.parseGestureBinding(value: value, mode: keyMode, hyperModifier: config.hyperModifier) {
            case .failure(let msg): recordConfigLineError(file, line, msg)
            case .success(let b):
                let loc = BindingLocation(file: file, line: line)
                noteHyper(.gesture, value, index: config.gestureBindings.count)
                config.gestureBindings.append(b); gestureLocs.append(loc)
                noteDispatch(b.dispatch, file, line)
            }
            return

        case "switchbind":
            note(file, line, .noEffect, key, ConfigParser.port?.optionNote(key, applied: false)?.1 ?? "")
            return

        case "window_rule", "window_rule_once":
            let (rule, problems, keep) = RuleParser.parseWindowRuleChecked(value, once: key == "window_rule_once")
            if keep { config.windowRules.append(rule) }
            for p in problems { recordConfigLineError(file, line, p) }
            for (field, _) in RuleParser.tokens(value) {
                if let (kind, n) = ConfigParser.port?.windowRuleNote(field) { note(file, line, kind, "window_rule \(field)", n) }
            }
            return

        case "tag_rule":
            let (rule, problems) = RuleParser.parseTagRuleLenient(value)
            config.tagRules.append(rule)
            for p in problems { recordConfigLineError(file, line, p) }
            return

        default:
            break
        }

        if BindingParser.isKeyBindKeyword(key) {
            switch BindingParser.parseKeyBinding(keyword: key, value: value, mode: keyMode,
                                                 hyperModifier: config.hyperModifier) {
            case .failure(let msg):
                recordConfigLineError(file, line, msg)
            case .success(let b):
                guard !b.keyCodes.isEmpty else { return }
                let loc = BindingLocation(file: file, line: line)
                noteHyper(.key, value, index: config.keyBindings.count)
                config.keyBindings.append(b); keyLocs.append(loc)
                noteDispatch(b.dispatch, file, line)
            }
            return
        }

        switch ConfigOptions.parseOption(key: key, value: value, to: &config) {
        case .applied:
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: true) { note(file, line, kind, key, n) }
        case .ignored:
            if let (kind, n) = ConfigParser.port?.optionNote(key, applied: false) { note(file, line, kind, key, n) }
        case .unknown: recordConfigLineError(file, line, "Unknown keyword: \(key)")
        case .invalid(let msg): recordConfigLineError(file, line, msg)
        }
    }

    /// Not in mango: HYPER resolved after the port's chutney_hyper_modifier.
    mutating func noteHyper(_ kind: BindingKind, _ value: String, index: Int) {
        guard let mods = BindingParser.splitFields(value).first, mods.lowercased().contains("hyper") else { return }
        hyperRefs.append((kind, index, mods))
    }

    /// Not in mango: file:line text for conflict messages.
}

public enum BindingParser {
/// Not in mango: parse_option's binding branches, apart for its two callers.
    public static func isKeyBindKeyword(_ keyword: String) -> Bool {
        guard keyword.hasPrefix("bind") else { return false }
        return keyword.dropFirst(4).allSatisfy { "slrpc".contains($0) }
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

    public static func parseKeyBinding(keyword: String, value: String, mode: String,
                                       hyperModifier: String) -> Result<KeyBinding, String> {
        guard isKeyBindKeyword(keyword) else { return .failure("Unknown keyword: \(keyword)") }
        let fields = splitFields(value)
        guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty, !fields[2].isEmpty else {
            return .failure("Invalid bind format: \(value)")
        }
        guard let mods = Modifiers.parse(fields[0], hyperModifier: hyperModifier) else {
            return .failure("Unknown modifier: \(fields[0])")
        }
        let keyName = fields[1]
        let codes = ConfigParser.port?.keyCodes(keyName) ?? []   // the boundary: xkb's keymap is the port's
        if codes.isEmpty && !keyName.lowercased().hasPrefix("xf86") {
            return .failure("Unknown key: \(keyName)")
        }
        let dispatch: Dispatch
        switch parseFuncName(Array(fields[2...])) {
        case .success(let d): dispatch = d
        case .failure(let msg): return .failure(msg)
        }
        return .success(KeyBinding(mode: mode, mods: mods, keyName: keyName, keyCodes: codes,
                                   flags: parseBindFlags(forKeyword: keyword), dispatch: dispatch))
    }

    public static func parseMouseBinding(value: String, mode: String, hyperModifier: String) -> Result<MouseBinding, String> {
        let fields = splitFields(value)
        guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty, !fields[2].isEmpty else {
            return .failure("Invalid mousebind format: \(value)")
        }
        guard let mods = Modifiers.parse(fields[0], hyperModifier: hyperModifier) else {
            return .failure("Unknown modifier: \(fields[0])")
        }
        guard let button = parseButton(fields[1]) else {
            return .failure("Unknown button: \(fields[1])")
        }
        return parseFuncName(Array(fields[2...])).map {
            MouseBinding(mode: mode, mods: mods, button: button, dispatch: $0)
        }
    }

    public static func parseAxisBinding(value: String, mode: String, hyperModifier: String) -> Result<AxisBinding, String> {
        let fields = splitFields(value)
        guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty, !fields[2].isEmpty else {
            return .failure("Invalid axisbind format: \(value)")
        }
        guard let mods = Modifiers.parse(fields[0], hyperModifier: hyperModifier) else {
            return .failure("Unknown modifier: \(fields[0])")
        }
        let dir = Direction(mangoName: fields[1])
        let undir = dir == nil && fields[1].lowercased() != "alldir"
        return parseFuncName(Array(fields[2...])).map {
            var b = AxisBinding(mode: mode, mods: mods, direction: dir, dispatch: $0)
            b.isUndir = undir
            return b
        }
    }

    public static func parseGestureBinding(value: String, mode: String, hyperModifier: String) -> Result<GestureBinding, String> {
        let fields = splitFields(value)
        guard fields.count >= 4, fields[0...3].allSatisfy({ !$0.isEmpty }) else {
            return .failure("Invalid gesturebind format: \(value)")
        }
        guard let mods = Modifiers.parse(fields[0], hyperModifier: hyperModifier) else {
            return .failure("Unknown modifier: \(fields[0])")
        }
        let dir = Direction(mangoName: fields[1])
        let undir = dir == nil && fields[1].lowercased() != "alldir"
        let fingers = ValueParse.atoi(fields[2])
        return parseFuncName(Array(fields[3...])).map {
            var b = GestureBinding(mode: mode, mods: mods, direction: dir, fingers: fingers, dispatch: $0)
            b.isUndir = undir
            return b
        }
    }

    public static func parseFuncName(_ fields: [String]) -> Result<Dispatch, String> {
        guard let first = fields.first else { return .failure("Missing dispatcher") }
        let name = first.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure("Missing dispatcher") }
        guard Dispatch.isKnown(name) else {
            return .failure("Unknown dispatch: \(name)")
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
        value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
