import Foundation
import Mango

/// xkb's work on macOS: mango's key names to macOS key codes in the system's keyboard layout.
public enum KeySyms {
    public static let systemKeyBase: UInt16 = 0x1000

    public static func parseKey(forName rawName: String, layout given: LayoutTable? = nil) -> [UInt16] {
        let layoutTable = given ?? layout()
        let name = rawName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return [] }
        let lower = name.lowercased()

        if lower.hasPrefix("code:") {
            let digits = lower.dropFirst(5)
            if let n = Int(digits), n >= 0, n <= Int(UInt16.max) { return [UInt16(n)] }
            let prefix = digits.prefix { $0.isNumber }
            if let n = Int(prefix), n <= Int(UInt16.max) { return [UInt16(n)] }
            return []
        }

        if let ch = characterNames[lower], let code = layoutTable.chars[ch] { return [code] }

        if let code = namedKeys[lower] { return [code] }

        if name.count == 1, let ch = name.first {
            let key: Character = ch.isLetter ? Character(ch.lowercased()) : ch
            if let code = layoutTable.chars[key] { return [code] }
            if let code = layoutTable.chars[ch] { return [code] }
            if let code = ansiUSFallback[key] { return [code] }
            return []
        }

        if let ch = characterNames[lower], let code = ansiUSFallback[ch] { return [code] }
        return []
    }

    static let namedKeys: [String: UInt16] = {
        let t: [String: UInt16] = [
            "return": 36, "enter": 36, "kp_enter": 76,
            "tab": 48, "iso_left_tab": 48,
            "space": 49,
            "escape": 53, "esc": 53,
            "backspace": 51,
            "delete": 117, "kp_delete": 65,
            "insert": 114, "help": 114,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "home": 115, "end": 119,
            "prior": 116, "page_up": 116, "pageup": 116,
            "next": 121, "page_down": 121, "pagedown": 121,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
            "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
            "minus": 27, "equal": 24, "bracketleft": 33, "bracketright": 30, "backslash": 42,
            "semicolon": 41, "apostrophe": 39, "quote": 39, "quoteright": 39, "grave": 50,
            "quoteleft": 50, "comma": 43, "period": 47, "slash": 44,
            "section": 10, "plusminus": 10,
            "super_l": 55, "super_r": 54, "meta_l": 55, "meta_r": 54, "command": 55,
            "alt_l": 58, "alt_r": 61, "option": 58,
            "control_l": 59, "control_r": 62,
            "shift_l": 56, "shift_r": 60,
            "caps_lock": 57, "capslock": 57,
            "function": 63, "fn": 63,
            "kp_0": 82, "kp_1": 83, "kp_2": 84, "kp_3": 85, "kp_4": 86, "kp_5": 87, "kp_6": 88,
            "kp_7": 89, "kp_8": 91, "kp_9": 92,
            "kp_insert": 82, "kp_end": 83, "kp_down": 84, "kp_next": 85, "kp_page_down": 85,
            "kp_left": 86, "kp_begin": 87, "kp_right": 88, "kp_home": 89, "kp_up": 91,
            "kp_prior": 92, "kp_page_up": 92,
            "kp_decimal": 65, "kp_separator": 65, "kp_multiply": 67, "kp_add": 69, "kp_clear": 71,
            "clear": 71, "num_lock": 71, "kp_divide": 75, "kp_subtract": 78, "kp_equal": 81,
            "yen": 93, "jis_yen": 93, "underscore": 94, "jis_underscore": 94, "kp_comma": 95,
            "eisu_toggle": 102, "kana_lock": 104, "hiragana_katakana": 104,
// not in mango: a PC keyboard's Print Screen, Scroll Lock and Pause arrive as F13-F15, Menu as the contextual-menu key.
            "print": 105, "sys_req": 105, "scroll_lock": 107, "pause": 113, "break": 113,
            "menu": 110,
            "xf86audioraisevolume": systemKeyBase + 0,
            "xf86audiolowervolume": systemKeyBase + 1,
            "xf86monbrightnessup": systemKeyBase + 2,
            "xf86monbrightnessdown": systemKeyBase + 3,
            "xf86poweroff": systemKeyBase + 6, "xf86sleep": systemKeyBase + 6,
            "xf86audiomute": systemKeyBase + 7,
            "xf86launcha": systemKeyBase + 13,
            "xf86eject": systemKeyBase + 14,
            "xf86display": systemKeyBase + 15,
            "xf86audioplay": systemKeyBase + 16, "xf86audiopause": systemKeyBase + 16,
            "xf86audionext": systemKeyBase + 17,
            "xf86audioprev": systemKeyBase + 18,
            "xf86audioforward": systemKeyBase + 19,
            "xf86audiorewind": systemKeyBase + 20,
            "xf86kbdbrightnessup": systemKeyBase + 21,
            "xf86kbdbrightnessdown": systemKeyBase + 22,
            "xf86kbdlightonoff": systemKeyBase + 23,
            "volumeup": 72, "volumedown": 73, "mute": 74,
        ]
        return t
    }()

    package static let namedKeyReverse: [UInt16: String] = {
        let preferred: [UInt16: String] = [
            36: "Return", 76: "KP_Enter", 48: "Tab", 49: "space", 53: "Escape", 51: "BackSpace",
            117: "Delete", 114: "Insert", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
            115: "Home", 119: "End", 116: "Prior", 121: "Next",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            110: "Menu", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            55: "Super_L", 54: "Super_R", 58: "Alt_L", 61: "Alt_R", 59: "Control_L", 62: "Control_R",
            56: "Shift_L", 60: "Shift_R", 57: "Caps_Lock", 63: "Function",
            82: "KP_0", 83: "KP_1", 84: "KP_2", 85: "KP_3", 86: "KP_4", 87: "KP_5", 88: "KP_6",
            89: "KP_7", 91: "KP_8", 92: "KP_9", 65: "KP_Decimal", 67: "KP_Multiply", 69: "KP_Add",
            71: "KP_Clear", 75: "KP_Divide", 78: "KP_Subtract", 81: "KP_Equal",
            72: "VolumeUp", 73: "VolumeDown", 74: "Mute",
            systemKeyBase + 0: "XF86AudioRaiseVolume", systemKeyBase + 1: "XF86AudioLowerVolume",
            systemKeyBase + 2: "XF86MonBrightnessUp", systemKeyBase + 3: "XF86MonBrightnessDown",
            systemKeyBase + 7: "XF86AudioMute", systemKeyBase + 14: "XF86Eject",
            systemKeyBase + 16: "XF86AudioPlay", systemKeyBase + 17: "XF86AudioNext",
            systemKeyBase + 18: "XF86AudioPrev", systemKeyBase + 21: "XF86KbdBrightnessUp",
            systemKeyBase + 22: "XF86KbdBrightnessDown",
        ]
        return preferred
    }()

    static let characterNames: [String: Character] = [
        "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
        "ampersand": "&", "apostrophe": "'", "quoteright": "'", "parenleft": "(", "parenright": ")",
        "asterisk": "*", "plus": "+", "comma": ",", "minus": "-", "period": ".", "slash": "/",
        "colon": ":", "semicolon": ";", "less": "<", "equal": "=", "greater": ">", "question": "?",
        "at": "@", "bracketleft": "[", "backslash": "\\", "bracketright": "]", "asciicircum": "^",
        "underscore": "_", "grave": "`", "quoteleft": "`", "braceleft": "{", "bar": "|",
        "braceright": "}", "asciitilde": "~",
        "section": "§", "degree": "°", "ae": "æ", "oslash": "ø", "aring": "å",
        "adiaeresis": "ä", "odiaeresis": "ö", "udiaeresis": "ü", "ssharp": "ß", "eacute": "é",
        "egrave": "è", "agrave": "à", "ugrave": "ù", "ccedilla": "ç", "ntilde": "ñ",
        "sterling": "£", "eurosign": "€", "yen": "¥", "mu": "µ", "plusminus": "±",
    ]

    public struct LayoutTable {
        public var chars: [Character: UInt16] = [:]
        public var reverse: [UInt16: Character] = [:]
        public init(chars: [Character: UInt16] = [:], reverse: [UInt16: Character] = [:]) {
            self.chars = chars; self.reverse = reverse
        }
    }

    nonisolated(unsafe) public static var layout: () -> LayoutTable = { LayoutTable(chars: ansiUSFallback, reverse: ansiUSReverse) }

    package static let ansiUSFallback: [Character: UInt16] = {
        var t: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "§": 10, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
            "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
            "m": 46, ".": 47, "`": 50,
        ]
        let shifted: [Character: Character] = [
            "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
            "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";",
            "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`", "±": "§",
        ]
        for (s, base) in shifted { t[s] = t[base] }
        return t
    }()

    package static let ansiUSReverse: [UInt16: Character] = {
        var r: [UInt16: Character] = [:]
        for (ch, code) in ansiUSFallback where r[code] == nil || ch.isLetter || ch.isNumber {
            if let existing = r[code], existing.isLetter || existing.isNumber { continue }
            r[code] = ch
        }
        return r
    }()
}
