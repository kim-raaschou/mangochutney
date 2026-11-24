import Foundation

extension ValueParse {
    // Helper function to trim whitespace from start and end of a string
    static func trimWhitespace(_ str: some StringProtocol) -> String {
        str.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
    }

    static func stripQuotes(_ str: String) -> String {
        guard str.utf8.count >= 2, let f = str.first, let l = str.last,
              (f == "\"" && l == "\"") || (f == "'" && l == "'") else { return str }
        return trimWhitespace(str.dropFirst().dropLast())
    }

    // remove comment, support double quote inside "#xxx" or '#xxx' not be treated
    // as comment
    static func removeComment(_ str: String) -> String {
        var quoteChar: Character?
        var prev: Character?
        var p = str.startIndex
        while p < str.endIndex {
            let c = str[p]
            if quoteChar == nil {
                if c == "'" || c == "\"" {
                    quoteChar = c
                } else if c == "#", let prev, " \t\n\r\u{0B}\u{0C}".contains(prev) {
                    return String(str[..<p])
                }
            } else {
                if c == quoteChar {
                    quoteChar = nil
                }
            }
            prev = c
            p = str.index(after: p)
        }
        return str
    }

    // not in mango: mango_error's message returned beside the count
    static func parseDoubleArray(_ input: String, _ output: inout [Double], _ maxCount: Int) -> (Int, String?) {
        var count = 0

        // Clear the whole array first.
        output = Array(repeating: 0, count: maxCount)

        for token in input.split(separator: ",") where count < maxCount {
            let t = trimWhitespace(token)
            guard let (number, rest) = strtod(t), rest.isEmpty else {
                return (-1, "Invalid number in array: \(mangoHighlight(t))")
            }
            let val = finite(number)
            if val < 0.0 {
                return (-1, "Invalid number in array (must be non-negative): \(mangoHighlight(t))")
            }
            output[count] = val // Assign at the current count position.
            count += 1          // Then increment.
        }

        return (count, nil)
    }

    // Removes invisible characters from the string (including \r, \n, spaces).
    static func sanitizeString(_ str: some StringProtocol) -> String {
        let bytes = Array(str.utf8)
        let isprint = { (c: UInt8) in c >= 0x20 && c <= 0x7E }
        guard let start = bytes.firstIndex(where: isprint), let end = bytes.lastIndex(where: isprint) else { return "" }
        return String(decoding: bytes[start...end], as: UTF8.self)
    }

    static func convertHexToRgba(_ hex: UInt32) -> RGBA {
        RGBA(r: Double((hex >> 24) & 0xFF) / 255, g: Double((hex >> 16) & 0xFF) / 255,
             b: Double((hex >> 8) & 0xFF) / 255, a: Double(hex & 0xFF) / 255)
    }

    static func parseNumType(_ str: String) -> UInt32 {
        switch str.first {
        case "-":
            return NUM_TYPE_MINUS
        case "+":
            return NUM_TYPE_PLUS
        default:
            return NUM_TYPE_DEFAULT
        }
    }

    // not in mango: nil for ANIM_TYPE_UNSET, .slide for ANIM_TYPE_UNKNOWN (AnimationType)
    static func animationTypeFromString(_ value: String) -> AnimationType? {
        if value.isEmpty {
            return nil
        }
        return AnimationType(rawValue: value) ?? .slide
    }

    static func parseCircleDirection(_ str: String) -> Int32 {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(9), as: UTF8.self).lowercased()

        // Returns the matching enum value from the lowercased string.
        if lowerStr == "next" {
            return NEXT
        } else {
            return PREV
        }
    }

    static func parseOvercircleDirection(_ str: String) -> Int32 {
        let lowerStr = String(decoding: str.utf8.prefix(15), as: UTF8.self).lowercased()

        if lowerStr == "next" {
            return OVERCIRCLE_NEXT
        }
        if lowerStr == "current_next" {
            return OVERCIRCLE_CURRENT_NEXT
        }
        if lowerStr == "current_prev" {
            return OVERCIRCLE_CURRENT_PREV
        }
        return OVERCIRCLE_PREV
    }

    static func parseDirection(_ str: String) -> Int32 {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(9), as: UTF8.self).lowercased()

        // Returns the matching enum value from the lowercased string.
        if lowerStr == "up" {
            return UP
        } else if lowerStr == "down" {
            return DOWN
        } else if lowerStr == "left" {
            return LEFT
        } else if lowerStr == "right" {
            return RIGHT
        } else if lowerStr == "alldir" {
            return ALLDIR
        } else {
            return UNDIR
        }
    }

    static func parseMonitorArg(_ str: String) -> Int32 {
        let dir = parseDirection(str)

        let lowerStr = String(decoding: str.utf8.prefix(9), as: UTF8.self).lowercased()

        if lowerStr == "next" {
            return MON_NEXT
        } else if lowerStr == "prev" {
            return MON_PREV
        }
        return dir
    }

    static func parseColor(_ hexStr: String) -> Int64 {
        let hexNum: Int
        if let (v, rest) = strtol(Substring(hexStr), base: 16) {
            if !rest.isEmpty {
                return -1
            }
            hexNum = v
        } else {
            if !hexStr.isEmpty {
                return -1
            }
            hexNum = 0
        }
        return Int64(hexNum)
    }

    static func parseForce(_ str: String) -> Int32 {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(9), as: UTF8.self).lowercased()

        // Returns the matching enum value from the lowercased string.
        if lowerStr == "unforce" {
            return UNFORCE
        } else if lowerStr == "force" {
            return FORCE
        } else {
            return UNFORCE
        }
    }

    static func parseFoldState(_ str: String) -> Int32 {
        // Converts the input string to lowercase.
        let lowerStr = String(decoding: str.utf8.prefix(9), as: UTF8.self).lowercased()

        // Returns the matching enum value from the lowercased string.
        if lowerStr == "fold" {
            return FOLD
        } else if lowerStr == "unfold" {
            return UNFOLD
        } else {
            return INVALIDFOLD
        }
    }

    static func parseTagMask(_ str: String) -> UInt32 {
        var mask: UInt32 = 0

        for part in str.split(separator: "|") {
            let token = trimWhitespace(part)
            let num = atoi(token)
            if num == 0 && token == "0" {
                mask |= TAG0_MASK
            } else if num > 0 && num <= Int(tag_num_MAX) {
                mask |= UInt32(1) << UInt32(num - 1)
            }
        }

        // tag0 and normal tags are exclusive; keep tag0 when mixed
        // not in mango: TAGMASK is every tag but tag0 here, as the parse has no server; the same for every tag up to tag_num
        if (mask & TAG0_MASK) != 0 && (mask & ~TAG0_MASK) != 0 {
            mask = TAG0_MASK
        }

        var result: UInt32 = 0

        if mask != 0 {
            result = mask
        } else {
            result = UInt32(truncatingIfNeeded: atoi(str))
        }

        return result
    }
}

/// mango report_config_line_error (value_parse.c)
public func reportConfigLineError(_ fullPath: String, _ lineNumber: Int, _ line: String) {
    mangoErrorUntagged(.info,
                       "\u{1B}[1;31m╰─\u{1B}[1;33m[Index]\u{1B}[0m "
                       + "\u{1B}[1;36m\(fullPath)\u{1B}[0m:\u{1B}[1;35m\(lineNumber)\u{1B}[0m\n"
                       + "   \u{1B}[1;36m╰─\u{1B}[0;33m\(line)\u{1B}[0m\n\n")
}

// not in mango: parse_color and convert_hex_to_rgba as one, nil where parse_color gives -1
public func parseColor(_ hexStr: String) -> RGBA? {
    let color = ValueParse.parseColor(hexStr)
    if color == -1 { return nil }
    return ValueParse.convertHexToRgba(UInt32(truncatingIfNeeded: color))
}

// not in mango: \033[1m\033[31m%s\033[0m, which mango's config errors put round a value
func mangoHighlight(_ s: String) -> String { "\u{1B}[1m\u{1B}[31m\(s)\u{1B}[0m" }

// not in mango: libc's atoi, atof, strtol, strtoul and sscanf's %f, which mango's parsing calls
package enum ValueParse {
    /// atoi: glibc's (int)strtol.
    static func atoi(_ s: some StringProtocol) -> Int {
        guard let (v, _) = strtol(Substring(s)) else { return 0 }
        return Int(Int32(truncatingIfNeeded: v))
    }

    static func atof(_ s: String, keepingInf: Bool = false) -> Double {
        finite(strtod(s)?.0 ?? 0, keepingInf: keepingInf)
    }

    /// sscanf's %f: nil where no number is read.
    static func scanDouble(_ s: String, keepingInf: Bool = false) -> Double? {
        strtod(s).map { finite($0.0, keepingInf: keepingInf) }
    }

    // not in mango: inf and nan, which strtod reads, are 0, as Swift traps where mango's C converts
    // them to an int (default_master_factor=nan, then tile); `keepingInf` for a value clamped before
    // it is used, where mango's clamp makes inf a bound
    static func finite(_ d: Double, keepingInf: Bool = false) -> Double {
        d.isFinite || (keepingInf && d.isInfinite) ? d : 0
    }

    /// strtod: the number and the text after it, nil where no number is read (endptr == str).
    static func strtod(_ s: String) -> (Double, Substring)? {
        s.withCString { p -> (Double, Substring)? in
            var end: UnsafeMutablePointer<CChar>?
            let d = Darwin.strtod(p, &end)
            guard let end, end != UnsafeMutablePointer(mutating: p) else { return nil }
            return (d, Substring(String(cString: end)))
        }
    }

    /// strtol: the number and the text after it, nil where no digit is read (endptr == str).
    static func strtol(_ s: Substring, base: Int = 10) -> (Int, Substring)? {
        guard let (v, negative, rest) = digits(s, base: base) else { return nil }
        let max = UInt64(Int64.max)
        if negative { return (v > max ? Int(Int64.min) : -Int(v), rest) }
        return (Int(min(v, max)), rest)
    }

    /// strtoul: as strtol, a minus sign wrapping the number round.
    static func strtoul(_ s: Substring) -> (UInt64, Substring)? {
        guard let (v, negative, rest) = digits(s, base: 10) else { return nil }
        return (negative && v != UInt64.max ? 0 &- v : v, rest)
    }

    private static func digits(_ s: Substring, base: Int) -> (UInt64, Bool, Substring)? {
        var it = s.drop { " \t\n\r\u{0B}\u{0C}".contains($0) }
        var negative = false
        if let f = it.first, f == "+" || f == "-" { negative = f == "-"; it = it.dropFirst() }
        if base == 16, it.hasPrefix("0x") || it.hasPrefix("0X"),
           it.dropFirst(2).first?.hexDigitValue != nil {
            it = it.dropFirst(2)
        }
        var v: UInt64 = 0
        var read = false
        while let c = it.first, let d = c.hexDigitValue, d < base, c.isASCII {
            let (m, o1) = v.multipliedReportingOverflow(by: UInt64(base))
            let (r, o2) = m.addingReportingOverflow(UInt64(d))
            v = o1 || o2 ? UInt64.max : r
            read = true
            it = it.dropFirst()
        }
        return read ? (v, negative, it) : nil
    }
}
