extension ValueParse {
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
}
