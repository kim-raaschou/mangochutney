import Foundation

package struct TomlSection {
    var name = ""
    var keymode = ""
    var savedKeymode = ""
    var bindtype = ""
    var keyword = ""
    var pairs = ""
    var lineNumber = 0
    var kind = TOML_SECTION_NONE
    var active = false
    var skip = false
}

let TOML_SECTION_NONE = 0
let TOML_SECTION_GLOBAL = 1
let TOML_SECTION_ENV = 2
let TOML_SECTION_VAR = 3
let TOML_SECTION_BIND = 4
let TOML_SECTION_RULE = 5

package extension ParserState {
    static func removeTomlComment(_ str: String) -> String {
        var quote: Character?
        var escaped = false
        for (p, c) in zip(str.indices, str) {
            if quote == "\"" {
                if escaped {
                    escaped = false
                    continue
                }
                if c == "\\" {
                    escaped = true
                    continue
                }
                if c == "\"" {
                    quote = nil
                }
            } else if quote == "'" {
                if c == "'" {
                    quote = nil
                }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                return String(str[..<p])
            }
        }
        return str
    }

    // not in mango: the value returned, where mango writes it to `out`
    static func tomlScalar(_ raw: String, mapBool: Bool) -> String {
        let s = ValueParse.trimWhitespace(raw)

        if s.count >= 2, s.first == "\"", s.last == "\"" {
            var out = ""
            var chars = Array(s.dropFirst().dropLast())[...]
            while let c = chars.popFirst() {
                guard c == "\\", let esc = chars.popFirst() else {
                    out.append(c)
                    continue
                }
                switch esc {
                case "n":
                    out.append("\n")
                case "t":
                    out.append("\t")
                case "r":
                    out.append("\r")
                case "\"", "\\":
                    out.append(esc)
                default:
                    out.append("\\")
                    out.append(esc)
                }
            }
            return out
        }

        if s.count >= 2, s.first == "'", s.last == "'" {
            return String(s.dropFirst().dropLast())
        }

        if mapBool {
            if s == "true" {
                return "1"
            }
            if s == "false" {
                return "0"
            }
        }

        return s
    }

    static func tomlValueToString(_ raw: String) -> String {
        tomlScalar(raw, mapBool: true)
    }

    static func tomlValueAsString(_ raw: String) -> String {
        tomlScalar(raw, mapBool: false)
    }

    // not in mango: `p` is the array from its "[", where mango's starts after it; `fn` a closure, where
    // mango's takes a context
    static func tomlForeachArrayElement(_ p: String, _ fn: (String) -> Bool) -> Bool {
        var s = Substring(ValueParse.trimWhitespace(p))
        if s.first == "[" { s = s.dropFirst() }
        var elem = ""
        var depth = 0
        var quote: Character?
        var escaped = false

        for c in s {
            if let q = quote {
                elem.append(c)
                // not in mango: an escaped quote does not end the string; mango's does, and splits
                // the string at its next comma (a mango bug, docs/afvigelser.md §6)
                if q == "\"" && escaped {
                    escaped = false
                    continue
                }
                if q == "\"" && c == "\\" {
                    escaped = true
                    continue
                }
                if c == q {
                    quote = nil
                }
                continue
            }

            if c == "\"" || c == "'" {
                quote = c
                elem.append(c)
            } else if c == "[" {
                depth += 1
                elem.append(c)
            } else if c == "]" {
                if depth == 0 {
                    return fn(elem)
                }
                depth -= 1
                elem.append(c)
            } else if c == "," && depth == 0 {
                if !fn(elem) {
                    return false
                }
                elem = ""
            } else {
                elem.append(c)
            }
        }

        if !elem.isEmpty {
            return fn(elem)
        }
        return true
    }

    // not in mango: TomlApplyCtx's key and line_number as parameters
    private mutating func tomlApplyElement(_ key: String, _ lineNumber: Int, _ elem: String) -> Bool {
        let value = Self.tomlValueToString(elem)
        if value.isEmpty {
            return true
        }
        return applyOptionExpanded(key, value, lineNumber)
    }

    // not in mango: TomlApplyCtx's joined as a parameter
    private static func tomlJoinElement(_ joined: inout String, _ elem: String) -> Bool {
        let value = tomlValueToString(elem)
        if value.isEmpty {
            return true
        }

        if joined.utf8.count + value.utf8.count + 2 >= 4096 {
            return false
        }
        if !joined.isEmpty {
            joined += ","
        }
        joined += value
        return true
    }

    static func tomlKeyJoinsArray(_ key: String) -> Bool {
        key.hasPrefix("animation_curve_") || key == "scroller_proportion_preset" || key == "circle_layout"
    }

    private mutating func tomlApplyValue(_ key: String, _ raw: String, _ lineNumber: Int) -> Bool {
        let p = raw.drop { " \t\n\r\u{0B}\u{0C}".contains($0) }

        if p.hasPrefix("[") {
            if Self.tomlKeyJoinsArray(key) {
                var joined = ""
                if !Self.tomlForeachArrayElement(String(p), { Self.tomlJoinElement(&joined, $0) }) {
                    return false
                }
                return applyOptionExpanded(key, joined, lineNumber)
            }
            return Self.tomlForeachArrayElement(String(p)) { tomlApplyElement(key, lineNumber, $0) }
        }

        let value = Self.tomlValueToString(raw)
        if value.isEmpty {
            return true
        }
        return applyOptionExpanded(key, value, lineNumber)
    }

    static func tomlIsRuleType(_ name: String) -> Bool {
        name == "monitor_rule" || name == "tag_rule" || name == "layer_rule" || name == "window_rule"
            || name == "window_rule_once" || name == "device_rule"
    }

    private mutating func tomlSectionAdd(_ section: inout TomlSection, _ subkey: String, _ rawValue: String) -> Bool {
        let value = Self.tomlValueToString(rawValue)
        if value.isEmpty {
            return true
        }

        let v = expandConfigVariables(value)

        if section.pairs.utf8.count + subkey.utf8.count + v.utf8.count + 2 >= 8192 {
            configError("Toml section is too long: \(mangoHighlight(section.name))")
            return false
        }

        if !section.pairs.isEmpty {
            section.pairs += ","
        }
        section.pairs += "\(subkey):\(v)"

        return true
    }

    static func tomlBindFlagChar(_ word: String) -> Character? {
        if word == "sym" {
            return "s"
        }
        if word == "lock" {
            return "l"
        }
        if word == "release" {
            return "r"
        }
        if word == "pass" {
            return "p"
        }
        if word == "conflict" {
            return "c"
        }
        return nil
    }

    private mutating func tomlSectionBegin(_ section: inout TomlSection, _ name: String, _ lineNumber: Int,
                                           _ fullPath: String, _ stmt: String) -> Bool {
        var base: String?
        var suffix: Substring?

        section = TomlSection()
        section.lineNumber = lineNumber
        section.active = true

        if name == "global" || name == "rule" {
            section.kind = TOML_SECTION_GLOBAL
            return true
        }
        if name == "env" {
            section.kind = TOML_SECTION_ENV
            return true
        }
        if name == "var" {
            section.kind = TOML_SECTION_VAR
            return true
        }

        for (prefix, b) in [("keybind", "bind"), ("bind", "bind"), ("mousebind", "mousebind"), ("axisbind", "axisbind"),
                            ("gesturebind", "gesturebind"), ("switchbind", "switchbind")]
            where base == nil && (name == prefix || name.hasPrefix(prefix + ".")) {
            base = b
            suffix = name == prefix ? "" : name.dropFirst(prefix.count + 1)
        }
        if base == nil {
            if name.hasPrefix("rule.") {
                let type = String(name.dropFirst(5))
                if !Self.tomlIsRuleType(type) {
                    configError("Unknown toml rule type: \(mangoHighlight(type))")
                    reportConfigLineError(fullPath, lineNumber, stmt)
                    section.skip = true
                    return false
                }
                section.kind = TOML_SECTION_RULE
                section.name = type
            } else if Self.tomlIsRuleType(name) {
                section.kind = TOML_SECTION_RULE
                section.name = name
            } else {
                configError("Unknown toml section: \(mangoHighlight(name))")
                reportConfigLineError(fullPath, lineNumber, stmt)
                section.skip = true
                return false
            }
        }

        guard let base else {
            return true
        }

        section.kind = TOML_SECTION_BIND
        section.bindtype = base
        section.keymode = "default"

        var letters = ""

        var depth = 0
        for raw in (suffix ?? "").split(separator: ".") {
            let tok = ValueParse.trimWhitespace(raw)
            if tok.isEmpty {
                continue
            }

            if depth == 0 {
                section.keymode = String(decoding: tok.utf8.prefix(27), as: UTF8.self)
            } else {
                guard let flag = Self.tomlBindFlagChar(tok) else {
                    configError("Unknown bind flag: \(mangoHighlight(tok))")
                    reportConfigLineError(fullPath, lineNumber, stmt)
                    section.skip = true
                    return false
                }
                if letters.count + 1 < 8 {
                    letters.append(flag)
                }
            }
            depth += 1
        }

        if depth == 0 {
            configError("Bind keymode is required, e.g. \(mangoHighlight("[\(base).default]"))")
            reportConfigLineError(fullPath, lineNumber, stmt)
            section.skip = true
            return false
        }

        section.keyword = base + letters
        section.savedKeymode = config.keymode
        config.keymode = section.keymode
        return true
    }

    // not in mango: TomlBindCtx's keyword, prefix and line_number as parameters
    private mutating func tomlBindElement(_ keyword: String, _ prefix: String, _ lineNumber: Int, _ elem: String) -> Bool {
        let action = Self.tomlValueToString(elem)
        if action.isEmpty {
            return true
        }
        return applyOptionExpanded(keyword, prefix + action, lineNumber)
    }

    // not in mango: the prefix returned, nil for false
    static func tomlBindPrefix(_ base: String, _ combo: String) -> String? {
        var segs: [String] = []
        for tok in combo.split(separator: "+") where segs.count < 16 {
            let t = ValueParse.trimWhitespace(tok)
            if !t.isEmpty {
                segs.append(t)
            }
        }
        if segs.isEmpty {
            return nil
        }

        if base == "switchbind" {
            return "\(segs[0]),"
        }

        if base == "gesturebind" {
            if segs.count < 3 {
                return nil
            }
            return "\(segs[0]),\(segs[1]),\(segs[2]),"
        }

        var mod = ""
        if segs.count >= 2 {
            mod = segs.dropLast().joined(separator: "+")
        } else {
            mod = "none"
        }
        return "\(mod),\(segs[segs.count - 1]),"
    }

    private mutating func tomlSectionLeaf(_ section: inout TomlSection, _ key: String, _ rawValue: String,
                                          _ lineNumber: Int) -> Bool {
        if section.kind == TOML_SECTION_ENV {
            let value = Self.tomlValueAsString(rawValue)
            if value.isEmpty {
                return true
            }
            return applyOptionExpanded("env", "\(key),\(value)", lineNumber)
        }
        if section.kind == TOML_SECTION_VAR {
            let value = Self.tomlValueAsString(rawValue)
            return applyOptionExpanded("var", "\(key),\(value)", lineNumber)
        }
        if section.kind == TOML_SECTION_RULE {
            return tomlSectionAdd(&section, key, rawValue)
        }
        if section.kind == TOML_SECTION_BIND {
            let keyword = section.keyword

            let expandedKey = expandConfigVariables(key)
            guard let prefix = Self.tomlBindPrefix(section.bindtype, expandedKey) else {
                return false
            }

            let p = rawValue.drop { " \t\n\r\u{0B}\u{0C}".contains($0) }
            if p.hasPrefix("[") {
                return Self.tomlForeachArrayElement(String(p)) { tomlBindElement(keyword, prefix, lineNumber, $0) }
            }

            let action = Self.tomlValueToString(rawValue)
            if action.isEmpty {
                return true
            }
            return applyOptionExpanded(keyword, prefix + action, lineNumber)
        }
        return tomlApplyValue(key, rawValue, lineNumber)
    }

    private mutating func tomlSectionFlush(_ section: inout TomlSection, _ fullPath: String) -> Bool {
        if !section.active {
            return true
        }

        var ok = true
        if section.kind == TOML_SECTION_RULE && !section.pairs.isEmpty {
            currentLine = section.lineNumber
            if !parseOption(section.name, section.pairs, section.lineNumber) {
                ok = false
                reportConfigLineError(fullPath, section.lineNumber, section.name)
            }
        }

        // not in mango: a section skipped for a bad flag or a missing keymode leaves the keymode as
        // it was; mango sets it to "" and no later binding fires (a mango bug, docs/afvigelser.md §6)
        if section.kind == TOML_SECTION_BIND && !section.skip {
            config.keymode = String(decoding: section.savedKeymode.utf8.prefix(27), as: UTF8.self)
        }

        section.active = false
        section.pairs = ""
        return ok
    }

    static func tomlStatementComplete(_ stmt: String) -> Bool {
        if stmt.first == "[" {
            let n = stmt.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
            return !n.isEmpty && n.last == "]"
        }

        guard let eq = stmt.firstIndex(of: "=") else {
            return true
        }

        var depth = 0
        var quote: Character?
        var escaped = false
        for c in stmt[stmt.index(after: eq)...] {
            if let q = quote {
                if q == "\"" && escaped {
                    escaped = false
                    continue
                }
                if q == "\"" && c == "\\" {
                    escaped = true
                    continue
                }
                if c == q {
                    quote = nil
                }
                continue
            }
            if c == "\"" || c == "'" {
                quote = c
            } else if c == "[" {
                depth += 1
            } else if c == "]" && depth > 0 {
                depth -= 1
            }
        }
        return depth == 0 && quote == nil
    }

    private mutating func tomlProcessStatement(_ stmt: String, _ lineNumber: Int, _ fullPath: String,
                                               _ section: inout TomlSection) -> Bool {
        currentLine = lineNumber
        if stmt.first == "[" {
            let ok = tomlSectionFlush(&section, fullPath)
            currentLine = lineNumber

            var begin = Substring(stmt)
            while begin.first == "[" {
                begin = begin.dropFirst()
            }
            while begin.last == "]" {
                begin = begin.dropLast()
            }

            let name = ValueParse.trimWhitespace(String(decoding: begin.utf8.prefix(255), as: UTF8.self))

            let begun = tomlSectionBegin(&section, name, lineNumber, fullPath, stmt)
            return ok && begun
        }

        if section.skip {
            return true
        }

        guard let eq = stmt.firstIndex(of: "=") else {
            configError("Invalid toml line format: \(mangoHighlight(stmt))")
            reportConfigLineError(fullPath, lineNumber, stmt)
            return false
        }

        var key = ValueParse.trimWhitespace(String(decoding: stmt[..<eq].utf8.prefix(255), as: UTF8.self))

        if key.utf8.count >= 2, let f = key.first, f == "\"" || f == "'", key.last == f {
            key = String(key.dropFirst().dropLast())
        }

        let value = String(stmt[stmt.index(after: eq)...].drop { " \t\n\r\u{0B}\u{0C}".contains($0) })

        if section.active {
            let ok = tomlSectionLeaf(&section, key, value, lineNumber)
            if !ok && section.kind != TOML_SECTION_RULE {
                reportConfigLineError(fullPath, lineNumber, stmt)
            }
            return ok
        }

        if !tomlApplyValue(key, value, lineNumber) {
            reportConfigLineError(fullPath, lineNumber, stmt)
            return false
        }
        return true
    }

    // not in mango: the file's text, where mango reads its FILE
    @discardableResult
    mutating func parseTomlStream(_ text: String, _ fullPath: String) -> Bool {
        var stmt = ""
        var lineCount = 0
        var stmtLine = 0
        var parseCorrect = true
        var section = TomlSection()

        currentFile = fullPath
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            lineCount += 1
            let raw = ValueParse.trimWhitespace(Self.removeTomlComment(String(rawLine)))
            if raw.isEmpty {
                continue
            }

            if stmt.isEmpty {
                stmtLine = lineCount
            }

            if stmt.utf8.count + raw.utf8.count + 2 >= 8192 {
                configError("Config line too long in \(mangoHighlight(fullPath))", line: lineCount)
                return false
            }
            if !stmt.isEmpty {
                stmt += " "
            }
            stmt += raw

            if !Self.tomlStatementComplete(stmt) {
                continue
            }

            if !tomlProcessStatement(stmt, stmtLine, fullPath, &section) {
                parseCorrect = false
            }
            stmt = ""
        }

        if !stmt.isEmpty && !tomlProcessStatement(stmt, stmtLine, fullPath, &section) {
            parseCorrect = false
        }

        if !tomlSectionFlush(&section, fullPath) {
            parseCorrect = false
        }

        return parseCorrect
    }
}
