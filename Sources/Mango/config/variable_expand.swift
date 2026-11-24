import Foundation

extension ParserState {
    private func findConfigVar(_ name: String) -> String? {
        config.vars[name]
    }

    static func isValidVarName(_ name: String) -> Bool {
        guard let f = name.unicodeScalars.first else {
            return false
        }
        if !(f.isASCII && CharacterSet.letters.contains(f)) && f != "_" {
            return false
        }
        for p in name.unicodeScalars.dropFirst() {
            if !(p.isASCII && CharacterSet.alphanumerics.contains(p)) && p != "_" {
                return false
            }
        }
        return true
    }

    mutating func setConfigVar(_ name: String, _ value: String) {
        config.vars[name] = value
    }

    func expandConfigVariables(_ value: String) -> String {
        func isalpha(_ c: Character) -> Bool { c.isASCII && c.isLetter }
        func isalnum(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        let chars = Array(value)
        var out = ""

        var p = 0
        while p < chars.count {
            var name: String?
            var next = p

            if chars[p] == "$" && p + 1 < chars.count && chars[p + 1] == "{" {
                if let close = chars[(p + 2)...].firstIndex(of: "}") {
                    name = String(chars[(p + 2)..<close])
                    next = close + 1
                }
            } else if chars[p] == "$" && p + 1 < chars.count && (isalpha(chars[p + 1]) || chars[p + 1] == "_") {
                var q = p + 1
                while q < chars.count && (isalnum(chars[q]) || chars[q] == "_") {
                    q += 1
                }
                name = String(chars[(p + 1)..<q])
                next = q
            }

            if let name, !name.isEmpty, name.utf8.count < 128 {
                if let v = findConfigVar(name) {
                    out += v
                    p = next
                    continue
                }
                out += String(chars[p..<next])
                p = next
                continue
            }

            out.append(chars[p])
            p += 1
        }
        return out
    }
}
