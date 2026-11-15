import Foundation

package extension ParserState {
    enum TOMLSectionKind { case none, global, env, vars, bind, rule }

    struct TOMLSection {
        var kind: TOMLSectionKind = .none
        var active = false
        var skip = false
        var line = 0
        var name = ""
        var bindType = ""
        var keyword = ""
        var savedKeyMode = "default"
        var pairs: [String] = []
    }

    @discardableResult
    mutating func parseTomlStream(_ text: String, fileName file: String) -> Bool {
        var section = TOMLSection()
        var stmt = ""
        var stmtLine = 0
        var lineNumber = 0
        var parseCorrect = true
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = ConfigParser.trimWhitespace(Self.removeTomlComment(String(raw)))
            if line.isEmpty { continue }
            if stmt.isEmpty { stmtLine = lineNumber } else { stmt += " " }
            stmt += line
            guard Self.tomlStatementComplete(stmt) else { continue }
            if !tomlProcessStatement(stmt, line: stmtLine, file: file, section: &section) { parseCorrect = false }
            stmt = ""
        }
        if !stmt.isEmpty, !tomlProcessStatement(stmt, line: stmtLine, file: file, section: &section) {
            parseCorrect = false
        }
        if !tomlSectionFlush(&section, file: file) { parseCorrect = false }
        return parseCorrect
    }

    // not in mango: each report_config_line_error here is recordConfigLineError, after the messages it follows
    private mutating func tomlProcessStatement(_ stmt: String, line: Int, file: String, section: inout TOMLSection) -> Bool {
        if stmt.hasPrefix("[") {
            let ok = tomlSectionFlush(&section, file: file)
            var name = Substring(stmt)
            while name.first == "[" { name = name.dropFirst() }
            while name.last == "]" { name = name.dropLast() }
            var begun = true
            withLineErrors(file, line) { state in
                begun = state.tomlSectionBegin(&section, name: ConfigParser.trimWhitespace(name), line: line)
                return begun
            }
            return ok && begun
        }
        if section.skip { return true }
        guard let eq = stmt.firstIndex(of: "=") else {
            withLineErrors(file, line) { state in
                state.lineErrors.append("Invalid toml line format: \(mangoHighlight(stmt))")
                return false
            }
            return false
        }
        var key = ConfigParser.trimWhitespace(stmt[..<eq])
        if key.count >= 2, let f = key.first, f == "\"" || f == "'", key.last == f {
            key = String(key.dropFirst().dropLast())
        }
        let value = String(stmt[stmt.index(after: eq)...].drop { $0.isWhitespace })
        var ok = true
        withLineErrors(file, line) { state in
            if section.active {
                ok = state.tomlSectionLeaf(&section, key: key, raw: value, line: line, file: file)
                return ok || section.kind == .rule
            }
            ok = state.tomlApplyValue(key, raw: value, line: line, file: file)
            return ok
        }
        return ok
    }

    private mutating func tomlSectionBegin(_ section: inout TOMLSection, name: String, line: Int) -> Bool {
        section = TOMLSection()
        section.line = line
        section.active = true

        switch name {
        case "global", "rule": section.kind = .global; return true
        case "env": section.kind = .env; return true
        case "var": section.kind = .vars; return true
        default: break
        }

        var base: String?
        var suffix = ""
        for (prefix, b) in [("keybind", "bind"), ("bind", "bind"), ("mousebind", "mousebind"),
                            ("axisbind", "axisbind"), ("gesturebind", "gesturebind"), ("switchbind", "switchbind")] {
            if name == prefix || name.hasPrefix(prefix + ".") {
                base = b
                suffix = name == prefix ? "" : String(name.dropFirst(prefix.count + 1))
                break
            }
        }
        guard let base else {
            let type = name.hasPrefix("rule.") ? String(name.dropFirst(5)) : name
            guard Self.tomlRuleTypes.contains(type) else {
                section.skip = true
                lineErrors.append(name.hasPrefix("rule.") ? "Unknown toml rule type: \(mangoHighlight(type))" : "Unknown toml section: \(mangoHighlight(name))")
                return false
            }
            section.kind = .rule
            section.name = type
            return true
        }

        section.kind = .bind
        section.bindType = base
        let parts = suffix.split(separator: ".").map { ConfigParser.trimWhitespace($0) }.filter { !$0.isEmpty }
        guard let mode = parts.first else {
            section.skip = true
            lineErrors.append("Bind keymode is required, e.g. \(mangoHighlight("[\(base).default]"))")
            return false
        }
        var letters = ""
        for flag in parts.dropFirst() {
            guard let l = Self.tomlBindFlags[flag] else {
                section.skip = true
                lineErrors.append("Unknown bind flag: \(mangoHighlight(flag))")
                return false
            }
            letters.append(l)
        }
        section.keyword = base + letters
        section.savedKeyMode = keyMode
        keyMode = String(decoding: mode.utf8.prefix(27), as: UTF8.self)
        return true
    }

    private mutating func tomlSectionLeaf(_ section: inout TOMLSection, key: String, raw: String, line: Int, file: String) -> Bool {
        switch section.kind {
        case .env:
            let value = Self.tomlScalar(raw, mapBool: false)
            if value.isEmpty { return true }
            return applyOptionExpanded("env", "\(key),\(value)", file: file, line: line)
        case .vars:
            return applyOptionExpanded("var", "\(key),\(Self.tomlScalar(raw, mapBool: false))", file: file, line: line)
        case .rule:
            let value = Self.tomlScalar(raw, mapBool: true)
            if value.isEmpty { return true }
            section.pairs.append("\(key):\(ConfigParser.expandConfigVariables(value, vars: vars))")
            return true
        case .bind:
            let combo = ConfigParser.expandConfigVariables(key, vars: vars)
            guard let prefix = Self.tomlBindPrefix(base: section.bindType, combo: combo) else { return false }
            if raw.hasPrefix("[") {
                return Self.tomlForeachArrayElement(raw) { elem in
                    let action = Self.tomlScalar(elem, mapBool: true)
                    if action.isEmpty { return true }
                    return applyOptionExpanded(section.keyword, prefix + action, file: file, line: line)
                }
            }
            let action = Self.tomlScalar(raw, mapBool: true)
            if action.isEmpty { return true }
            return applyOptionExpanded(section.keyword, prefix + action, file: file, line: line)
        case .global, .none:
            return tomlApplyValue(key, raw: raw, line: line, file: file)
        }
    }

    private mutating func tomlApplyValue(_ key: String, raw: String, line: Int, file: String) -> Bool {
        guard raw.hasPrefix("[") else {
            let value = Self.tomlScalar(raw, mapBool: true)
            if value.isEmpty { return true }
            return applyOptionExpanded(key, value, file: file, line: line)
        }
        if Self.tomlKeyJoinsArray(key) {
            var joined: [String] = []
            _ = Self.tomlForeachArrayElement(raw) { elem in
                let value = Self.tomlScalar(elem, mapBool: true)
                if !value.isEmpty { joined.append(value) }
                return true
            }
            return applyOptionExpanded(key, joined.joined(separator: ","), file: file, line: line)
        }
        return Self.tomlForeachArrayElement(raw) { elem in
            let value = Self.tomlScalar(elem, mapBool: true)
            if value.isEmpty { return true }
            return applyOptionExpanded(key, value, file: file, line: line)
        }
    }

    private mutating func tomlSectionFlush(_ section: inout TOMLSection, file: String) -> Bool {
        guard section.active else { return true }
        var ok = true
        if section.kind == .rule && !section.pairs.isEmpty {
            withLineErrors(file, section.line) { state in
                ok = state.parseOption(key: section.name, value: section.pairs.joined(separator: ","), file: file, line: section.line)
                return ok
            }
        }
        // not in mango: a section skipped for a bad flag or a missing keymode leaves the keymode as
        // it was; mango sets it to "" and no later binding fires (a mango bug, docs/afvigelser.md §6)
        if section.kind == .bind && !section.skip { keyMode = section.savedKeyMode }
        section = TOMLSection()
        return ok
    }

    static let tomlRuleTypes: Set<String> = [
        "monitor_rule", "tag_rule", "layer_rule", "window_rule", "window_rule_once", "device_rule",
    ]

    static let tomlBindFlags: [String: Character] = ["sym": "s", "lock": "l", "release": "r", "pass": "p", "conflict": "c"]

    static func tomlKeyJoinsArray(_ key: String) -> Bool {
        key.hasPrefix("animation_curve_") || key == "scroller_proportion_preset" || key == "circle_layout"
    }

    static func removeTomlComment(_ s: String) -> String {
        var quote: Character?
        var escaped = false
        for (i, c) in zip(s.indices, s) {
            if quote == "\"" {
                if escaped { escaped = false; continue }
                if c == "\\" { escaped = true; continue }
                if c == "\"" { quote = nil }
            } else if quote == "'" {
                if c == "'" { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "#" {
                return String(s[..<i])
            }
        }
        return s
    }

    static func tomlScalar(_ raw: String, mapBool: Bool) -> String {
        let s = ConfigParser.trimWhitespace(raw)
        if s.count >= 2, s.first == "\"", s.last == "\"" {
            var out = ""
            var chars = Array(s.dropFirst().dropLast())[...]
            while let c = chars.popFirst() {
                guard c == "\\", let esc = chars.popFirst() else { out.append(c); continue }
                switch esc {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"", "\\": out.append(esc)
                default: out.append("\\"); out.append(esc)
                }
            }
            return out
        }
        if s.count >= 2, s.first == "'", s.last == "'" { return String(s.dropFirst().dropLast()) }
        if mapBool {
            if s == "true" { return "1" }
            if s == "false" { return "0" }
        }
        return s
    }

    /// mango toml_foreach_array_element (toml_parse.c): stops at the first element `fn` fails
    static func tomlForeachArrayElement(_ raw: String, _ fn: (String) -> Bool) -> Bool {
        var s = Substring(ConfigParser.trimWhitespace(raw))
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
                if q == "\"" && escaped { escaped = false; continue }
                if q == "\"" && c == "\\" { escaped = true; continue }
                if c == q { quote = nil }
                continue
            }
            switch c {
            case "\"", "'":
                quote = c
                elem.append(c)
            case "[":
                depth += 1
                elem.append(c)
            case "]":
                if depth == 0 { return fn(elem) }
                depth -= 1
                elem.append(c)
            case "," where depth == 0:
                if !fn(elem) { return false }
                elem = ""
            default:
                elem.append(c)
            }
        }
        if !elem.isEmpty { return fn(elem) }
        return true
    }

    static func tomlStatementComplete(_ stmt: String) -> Bool {
        if stmt.hasPrefix("[") { return stmt.trimmingCharacters(in: .whitespaces).hasSuffix("]") }
        guard let eq = stmt.firstIndex(of: "=") else { return true }
        var depth = 0
        var quote: Character?
        var escaped = false
        for c in stmt[stmt.index(after: eq)...] {
            if let q = quote {
                if q == "\"" && escaped { escaped = false; continue }
                if q == "\"" && c == "\\" { escaped = true; continue }
                if c == q { quote = nil }
                continue
            }
            if c == "\"" || c == "'" { quote = c }
            else if c == "[" { depth += 1 }
            else if c == "]" && depth > 0 { depth -= 1 }
        }
        return depth == 0 && quote == nil
    }

    static func tomlBindPrefix(base: String, combo: String) -> String? {
        let segs = combo.split(separator: "+").map { ConfigParser.trimWhitespace($0) }.filter { !$0.isEmpty }
        guard let last = segs.last else { return nil }
        switch base {
        case "switchbind":
            return "\(segs[0]),"
        case "gesturebind":
            guard segs.count >= 3 else { return nil }
            return "\(segs[0]),\(segs[1]),\(segs[2]),"
        default:
            let mods = segs.count >= 2 ? segs.dropLast().joined(separator: "+") : "none"
            return "\(mods),\(last),"
        }
    }
}
