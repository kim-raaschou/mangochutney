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

    mutating func parseTomlStream(_ text: String, fileName file: String) {
        var section = TOMLSection()
        var stmt = ""
        var stmtLine = 0
        var lineNumber = 0
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let line = Self.removeTomlComment(String(raw)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if stmt.isEmpty { stmtLine = lineNumber } else { stmt += " " }
            stmt += line
            guard Self.tomlStatementComplete(stmt) else { continue }
            tomlProcessStatement(stmt, line: stmtLine, file: file, section: &section)
            stmt = ""
        }
        if !stmt.isEmpty { tomlProcessStatement(stmt, line: stmtLine, file: file, section: &section) }
        tomlSectionFlush(&section, file: file)
    }

    private mutating func tomlProcessStatement(_ stmt: String, line: Int, file: String, section: inout TOMLSection) {
        if stmt.hasPrefix("[") {
            tomlSectionFlush(&section, file: file)
            var name = Substring(stmt)
            while name.first == "[" { name = name.dropFirst() }
            while name.last == "]" { name = name.dropLast() }
            tomlSectionBegin(&section, name: name.trimmingCharacters(in: .whitespaces), line: line, file: file)
            return
        }
        if section.skip { return }
        guard let eq = stmt.firstIndex(of: "=") else {
            recordConfigLineError(file, line, "Invalid toml line format: \(mangoHighlight(stmt))")
            return
        }
        var key = stmt[..<eq].trimmingCharacters(in: .whitespaces)
        if key.count >= 2, let f = key.first, f == "\"" || f == "'", key.last == f {
            key = String(key.dropFirst().dropLast())
        }
        let value = stmt[stmt.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if section.active {
            tomlSectionLeaf(&section, key: key, raw: value, line: line, file: file)
        } else {
            tomlApplyValue(key, raw: value, line: line, file: file)
        }
    }

    private mutating func tomlSectionBegin(_ section: inout TOMLSection, name: String, line: Int, file: String) {
        section = TOMLSection()
        section.line = line
        section.active = true

        switch name {
        case "global", "rule": section.kind = .global; return
        case "env": section.kind = .env; return
        case "var": section.kind = .vars; return
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
        if base == nil {
            let type = name.hasPrefix("rule.") ? String(name.dropFirst(5)) : name
            guard Self.tomlRuleTypes.contains(type) else {
                section.skip = true
                recordConfigLineError(file, line, name.hasPrefix("rule.") ? "Unknown toml rule type: \(mangoHighlight(type))" : "Unknown toml section: \(mangoHighlight(name))")
                return
            }
            section.kind = .rule
            section.name = type
            return
        }

        guard let base else { return }
        section.kind = .bind
        section.bindType = base
        let parts = suffix.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let mode = parts.first else {
            section.skip = true
            recordConfigLineError(file, line, "Bind keymode is required, e.g. \(mangoHighlight("[\(base).default]"))")
            return
        }
        var letters = ""
        for flag in parts.dropFirst() {
            guard let l = Self.tomlBindFlags[flag] else {
                section.skip = true
                recordConfigLineError(file, line, "Unknown bind flag: \(mangoHighlight(flag))")
                return
            }
            letters.append(l)
        }
        section.keyword = base + letters
        section.savedKeyMode = keyMode
        keyMode = mode
    }

    private mutating func tomlSectionLeaf(_ section: inout TOMLSection, key: String, raw: String, line: Int, file: String) {
        switch section.kind {
        case .env:
            let value = Self.tomlScalar(raw, mapBool: false)
            if value.isEmpty { return }
            applyOptionExpanded("env", "\(key),\(value)", file: file, line: line)
        case .vars:
            applyOptionExpanded("var", "\(key),\(Self.tomlScalar(raw, mapBool: false))", file: file, line: line)
        case .rule:
            let value = Self.tomlScalar(raw, mapBool: true)
            if value.isEmpty { return }
            section.pairs.append("\(key):\(ConfigParser.expandConfigVariables(value, vars: vars))")
        case .bind:
            let combo = ConfigParser.expandConfigVariables(key, vars: vars)
            guard let prefix = Self.tomlBindPrefix(base: section.bindType, combo: combo) else {
                recordConfigLineError(file, line, "")   // mango: toml_bind_prefix fails without a message of its own
                return
            }
            let actions = raw.hasPrefix("[") ? Self.tomlForeachArrayElement(raw) : [raw]
            for a in actions {
                let action = Self.tomlScalar(a, mapBool: true)
                if action.isEmpty { continue }
                applyOptionExpanded(section.keyword, prefix + action, file: file, line: line)
            }
        case .global, .none:
            tomlApplyValue(key, raw: raw, line: line, file: file)
        }
    }

    private mutating func tomlApplyValue(_ key: String, raw: String, line: Int, file: String) {
        guard raw.hasPrefix("[") else {
            let value = Self.tomlScalar(raw, mapBool: true)
            if !value.isEmpty { applyOptionExpanded(key, value, file: file, line: line) }
            return
        }
        let elements = Self.tomlForeachArrayElement(raw).map { Self.tomlScalar($0, mapBool: true) }.filter { !$0.isEmpty }
        if Self.tomlKeyJoinsArray(key) {
            applyOptionExpanded(key, elements.joined(separator: ","), file: file, line: line)
        } else {
            for v in elements { applyOptionExpanded(key, v, file: file, line: line) }
        }
    }

    private mutating func tomlSectionFlush(_ section: inout TOMLSection, file: String) {
        guard section.active else { return }
        if section.kind == .rule && !section.pairs.isEmpty {
            parseOption(key: section.name, value: section.pairs.joined(separator: ","), file: file, line: section.line)
        }
        if section.kind == .bind && !section.skip { keyMode = section.savedKeyMode }
        section = TOMLSection()
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
        let s = raw.trimmingCharacters(in: .whitespaces)
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

    static func tomlForeachArrayElement(_ raw: String) -> [String] {
        var s = Substring(raw.trimmingCharacters(in: .whitespaces))
        if s.first == "[" { s = s.dropFirst() }
        var out: [String] = []
        var elem = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        for c in s {
            if let q = quote {
                elem.append(c)
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
                if depth == 0 { out.append(elem); return out }
                depth -= 1
                elem.append(c)
            case "," where depth == 0:
                out.append(elem)
                elem = ""
            default:
                elem.append(c)
            }
        }
        if !elem.isEmpty { out.append(elem) }
        return out
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
        let segs = combo.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
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
