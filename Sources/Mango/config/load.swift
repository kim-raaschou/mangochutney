import Foundation

// not in mango: a String as a Result's error
extension String: @retroactive Error {}

// not in mango: a mango_error or report_config_line_error of the config, kept as well as printed, for
// mango -p and the tests
public struct ConfigError: Error, CustomStringConvertible, Equatable {
    public var file: String
    public var line: Int
    public var message: String
    /// mango_error's verbosity: WLR_ERROR, or WLR_INFO for a binding conflict.
    public var verbosity: WlrLogImportance
    /// Followed by report_config_line_error for the line.
    public var reportsLine: Bool

    public init(file: String, line: Int, message: String, verbosity: WlrLogImportance = .error, reportsLine: Bool = true) {
        self.file = file; self.line = line; self.message = message
        self.verbosity = verbosity; self.reportsLine = reportsLine
    }

    public var description: String {
        line > 0 ? "\(file):\(line): \(message)" : "\(file): \(message)"
    }
}

// not in mango: what one parse_config leaves, for the server, mango -p and the tests
public struct ParsedConfig {
    public var config: Config
    public var errors: [ConfigError]
    /// Not in mango: the port's notes on lines it cannot honour or that are its own
    /// (ConfigPort), carried for `mango -p`.
    public var notes: [ConfigNote] = []
    /// mango's file_paths.
    public var sourcedFiles: [URL]

    public init(config: Config, errors: [ConfigError], sourcedFiles: [URL]) {
        self.config = config; self.errors = errors; self.sourcedFiles = sourcedFiles
    }
}

// not in mango: parse_config and parse_option for callers without the server (mango -p, setoption, the tests)
public enum ConfigParser {
    // not in mango: parse_config's choice of the user's file, without its SYSCONFDIR fallback; without
    // HOME, where mango reads none, the file is under /
    public static func defaultConfigURL() -> URL {
        let dir = URL(fileURLWithPath: ConfigOptions.homeDirectory() ?? "/", isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mango", isDirectory: true)
        let conf = dir.appendingPathComponent("config.conf", isDirectory: false)
        let toml = dir.appendingPathComponent("config.toml", isDirectory: false)
        let fm = FileManager.default
        return !fm.fileExists(atPath: conf.path) && fm.fileExists(atPath: toml.path) ? toml : conf
    }

    /// mango parse_config (load.c), the config's part
    // not in mango: `text`, the file's text given instead of read, named `name`; `emits`, the
    // errors printed as they are found (mango's server), or only kept (mango -p, the tests)
    public static func parseConfig(fileAt url: URL, text: (String, name: String)? = nil, emits: Bool = false) -> ParsedConfig {
        var state = ParserState(baseDirectory: url.deletingLastPathComponent())
        state.emits = emits
        // not in mango: set_value_default's values are Config's own (parse.swift)
        state.parseConfigFile(url.path, true, text: text)
        // not in mango: no resolve_bindings_to_configured_layouts, the port's key codes are read as the
        // binding is parsed (docs/afvigelser.md §3); no set_default_key_bindings, chvt has no macOS part
        state.config.overrideConfig()

        state.checkKeyBindingConflicts()
        state.checkMouseBindingConflicts()
        state.checkAxisBindingConflicts()
        state.checkSwitchBindingConflicts()
        state.checkGestureBindingConflicts()

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
        state.currentLine = lineNumber
        let ok = state.parseOption(key, value, lineNumber)
        config = state.config
        return ok
    }

    /// Not in mango: parsing config text without a file.
    public static func parse(text: String, baseDirectory: URL?, fileName: String) -> ParsedConfig {
        let base = baseDirectory ?? defaultConfigURL().deletingLastPathComponent()
        return parseConfig(fileAt: base.appendingPathComponent(fileName), text: (text, fileName))
    }

    /// mango ConfigFileFormat (config/internal.h)
    public enum Format: Equatable { case conf, toml }

    /// mango detect_config_format (load.c)
    // not in mango: the file's text given, where mango reads it from the file
    public static func detectConfigFormat(fileName fullPath: String, text: String) -> Format {
        if let dot = fullPath.lastIndex(of: ".") {
            let ext = fullPath[dot...].lowercased()
            if ext == ".toml" { return .toml }
            if ext == ".conf" { return .conf }
        }

        var inComment = false
        for c in text {
            if inComment { if c == "\n" || c == "\r\n" { inComment = false }; continue }
            if c == "#" {
                inComment = true
                continue
            }
            if " \t\n\r\u{0B}\u{0C}".contains(c) || c == "\r\n" {
                continue
            }
            return c == "[" ? .toml : .conf
        }
        return .conf
    }
}

// not in mango: a binding's file_index and line_number, kept beside it
package struct BindingLocation {
    var file: String
    var line: Int
}

// not in mango: mango's globals for one parse (config, file_paths, current_file_index) and what the
// port and mango -p keep of it
package struct ParserState {
    var config = Config()
    var errors: [ConfigError] = []
    var notes: [ConfigNote] = []
    var sourcedFiles: [URL] = []
    var emits = false
    // not in mango: server.cli_config_path's directory
    let baseDirectory: URL
    var includeStack: [String] = []
    // not in mango: the file and line being parsed, where a mango_error is kept
    var currentFile = ""
    var currentLine = 0

    var keyLocs: [BindingLocation] = []
    var mouseLocs: [BindingLocation] = []
    var axisLocs: [BindingLocation] = []
    var switchLocs: [BindingLocation] = []
    var gestureLocs: [BindingLocation] = []

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // not in mango: mango_error(false, verbosity, message) of the config, kept as well as printed
    mutating func configError(_ message: String, verbosity: WlrLogImportance = .error, file: String? = nil, line: Int? = nil) {
        errors.append(ConfigError(file: file ?? currentFile, line: line ?? currentLine, message: message,
                                  verbosity: verbosity, reportsLine: false))
        if emits { mangoError(false, verbosity, message + "\n") }
    }

    // not in mango: report_config_line_error, kept with the line's last message as well as printed
    mutating func reportConfigLineError(_ fullPath: String, _ lineNumber: Int, _ line: String) {
        if let last = errors.last, last.file == fullPath, last.line == lineNumber, !last.reportsLine,
           last.verbosity == .error {
            errors[errors.count - 1].reportsLine = true
        } else {
            errors.append(ConfigError(file: fullPath, line: lineNumber, message: "", reportsLine: true))
        }
        if emits { Mango.reportConfigLineError(fullPath, lineNumber, line) }
    }

    /// Not in mango: keeps a note of the port's (ConfigPort) on a line.
    mutating func note(_ kind: ConfigNote.Kind, _ name: String, _ reason: String) {
        notes.append(ConfigNote(file: currentFile, line: currentLine, kind: kind, name: name, reason: reason))
    }

    /// Not in mango: the port's note on a binding's dispatcher (ConfigPort).
    mutating func noteDispatch(_ d: Dispatch) {
        if let (kind, why) = ConfigParser.port?.dispatcherNote(d.name) { note(kind, d.name, why) }
    }

    mutating func parseConfigLine(_ line: String, _ lineNumber: Int) -> Bool {
        let processedLine = ValueParse.removeComment(String(decoding: line.utf8.prefix(511), as: UTF8.self))

        guard let eq = processedLine.firstIndex(of: "="), eq != processedLine.startIndex,
              processedLine[..<eq].utf8.count <= 255,
              let first = processedLine[processedLine.index(after: eq)...].utf8.first, first != UInt8(ascii: "\n") else {
            configError("Invalid line format: \(mangoHighlight(line))")
            return false
        }

        if processedLine[processedLine.index(after: eq)...].utf8.prefix(while: { $0 != UInt8(ascii: "\n") }).count >= 256 {
            configError("Configuration value exceeds 255 bytes: \(mangoHighlight(line))")
            return false
        }

        let key = ValueParse.trimWhitespace(processedLine[..<eq])
        var value = ValueParse.trimWhitespace(processedLine[processedLine.index(after: eq)...])
        value = ValueParse.stripQuotes(value)

        return applyOptionExpanded(key, value, lineNumber)
    }

    // not in mango: the file's text, where mango reads its FILE
    @discardableResult
    mutating func parseConfStream(_ text: String, _ fullPath: String) -> Bool {
        var parseCorrect = true
        var lineCount = 0

        let bytes = Array(text.utf8)
        var next = 0
        // not in mango: fgets(line, sizeof(line), file) over the text
        while next < bytes.count {
            let start = next
            while next < bytes.count && next - start < 511 {
                next += 1
                if bytes[next - 1] == UInt8(ascii: "\n") { break }
            }
            let line = String(decoding: bytes[start..<next], as: UTF8.self)
            lineCount += 1
            if bytes[start] == UInt8(ascii: "#") || bytes[start] == UInt8(ascii: "\n") {
                continue
            }
            // not in mango: an empty line of a CRLF file is skipped as an empty line (a mango bug, docs/afvigelser.md §6)
            if bytes[start..<next].elementsEqual("\r\n".utf8) {
                continue
            }

            currentFile = fullPath
            currentLine = lineCount
            if !parseConfigLine(line, lineCount) {
                parseCorrect = false
                reportConfigLineError(fullPath, lineCount, line)
            }
        }

        return parseCorrect
    }

    mutating func resolveConfigPath(_ filePath: String) -> String? {
        if filePath.hasPrefix("./") {
            let rel = filePath.dropFirst(2)
            return "\(baseDirectory.path)/\(rel)"
        } else if filePath == "~" || filePath.hasPrefix("~/") {
            guard let home = ConfigOptions.homeDirectory() else {
                configError("HOME environment variable not set.")
                return nil
            }
            return home + filePath.dropFirst(1)
        } else if !filePath.hasPrefix("/") {
            // not in mango: a bare relative path is read from the config's directory (docs/afvigelser.md §3)
            return "\(baseDirectory.path)/\(filePath)"
        } else {
            return filePath
        }
    }

    // not in mango: `text`, the file's text given instead of read, with the name it is reported under
    @discardableResult
    mutating func parseConfigFile(_ filePath: String, _ mustExist: Bool, text given: (String, name: String)? = nil) -> Bool {
        guard let fullPath = given?.name ?? resolveConfigPath(filePath) else {
            return false
        }

        // Saves the current file index to restore after recursion.
        let savedFile = currentFile, savedLine = currentLine
        defer { currentFile = savedFile; currentLine = savedLine }

        // Adds the file path to the global list.
        if given == nil { sourcedFiles.append(URL(fileURLWithPath: fullPath)) }

        // not in mango: a file that sources itself is reported, not read for ever (a mango bug, docs/afvigelser.md §6).
        if includeStack.contains(fullPath) {
            configError("Recursive source of \(fullPath) ignored")
            return false
        }

        let text: String
        if let given {
            text = given.0
        } else {
            var isDir: ObjCBool = false
            let exists = !fullPath.isEmpty && FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir)
            // not in mango: a directory opens and reads as nothing, as fopen's does
            let file = !exists ? nil : isDir.boolValue ? Data() : FileManager.default.contents(atPath: fullPath)
            guard let file else {
                if mustExist {
                    configError("Failed to open config file: \(mangoHighlight(filePath))")
                    return false
                } else {
                    return true
                }
            }
            text = String(data: file, encoding: .utf8) ?? String(decoding: file, as: UTF8.self)
        }

        includeStack.append(fullPath)
        defer { includeStack.removeLast() }
        let format = ConfigParser.detectConfigFormat(fileName: fullPath, text: text)
        let parseCorrect = format == .toml ? parseTomlStream(text, fullPath) : parseConfStream(text, fullPath)

        return parseCorrect
    }

    // not in mango: resolve_keybinding_layout and resolve_bindings_to_configured_layouts: a key's codes
    // are the port's, read as the binding is parsed (parse_key, docs/afvigelser.md §3)

    // not in mango: set_default_key_bindings (CHVT(1)…CHVT(12)): chvt has no macOS part, and no Mac key
    // gives XF86Switch_VT_n
}

package extension MangoServer {
    /// mango parse_config (load.c), the server's part
    // not in mango: the config is read by ConfigParser.parseConfig, apart for its other callers; no
    // result, which no caller reads
    func parseConfig() {
        configErrorStoreBegin()

        let parsed = ConfigParser.parseConfig(fileAt: configURL, emits: true)
        config = parsed.config
        updateGlobalVar()   // not in mango: override_config's last step, which needs the server
        configErrors = parsed.errors
        configFiles = parsed.sourcedFiles

        configErrorStoreEnd()
        configErrorNagUpdate()
    }

    func configGetFilePaths() -> [String] {
        configFiles.map(\.path)
    }

    // not in mango: config_current_file_index and config_file_path_at: a binding keeps its file's name
    // (BindingLocation)
}
