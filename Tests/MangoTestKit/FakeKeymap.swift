@testable import Mango

/// xkb's keymap as mango has it with no xkb_rules (us): a key's name and its evdev key code, the code a
/// virtual keyboard sends mango. The config's binds get these codes, so the tests press keys as
/// mango's own keyboard sends them. It is the boundary's ConfigPort for the key names only.
package struct FakeKeymap: ConfigPort {
    package static let codes: [String: UInt16] = {
        var codes: [String: UInt16] = [
            "escape": 1, "minus": 12, "equal": 13, "backspace": 14, "tab": 15, "bracketleft": 26,
            "bracketright": 27, "return": 28, "control_l": 29, "semicolon": 39, "apostrophe": 40,
            "grave": 41, "shift_l": 42, "backslash": 43, "comma": 51, "period": 52, "slash": 53,
            "shift_r": 54, "alt_l": 56, "space": 57, "f11": 87, "f12": 88, "control_r": 97, "alt_r": 100,
            "home": 102, "up": 103, "prior": 104, "page_up": 104, "left": 105, "right": 106, "end": 107,
            "down": 108, "next": 109, "page_down": 109, "delete": 111, "super_l": 125, "super_r": 126,
        ]
        for (i, row) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            for (j, ch) in row.enumerated() { codes[String(ch)] = UInt16([16, 30, 44][i] + j) }
        }
        for (j, ch) in "1234567890".enumerated() { codes[String(ch)] = UInt16(2 + j) }
        for n in 1...10 { codes["f\(n)"] = UInt16(58 + n) }
        return codes
    }()

    /// The modifier a modifier key carries; super, shift, ctrl and alt name their left key.
    package static let modifiers: [UInt16: Modifiers] = [
        125: .superKey, 126: .superKey, 42: .shift, 54: .shift, 29: .ctrl, 97: .ctrl, 56: .alt, 100: .alt,
    ]

    package static func code(_ name: String) -> UInt16? {
        let name = name.lowercased()
        return codes[["super": "super_l", "shift": "shift_l", "ctrl": "control_l", "alt": "alt_l"][name] ?? name]
    }

    package init() {}

    package func keyCodes(_ name: String) -> [UInt16] { FakeKeymap.code(name).map { [$0] } ?? [] }
    package func modifier(_ name: String) -> Modifiers? { nil }
    package func setter(_ key: String) -> ConfigOptions.Setter? { nil }
    package var keys: Set<String> { [] }
    package func isIgnored(_ key: String) -> Bool { false }
    package func optionNote(_ key: String, applied: Bool) -> (ConfigNote.Kind, String)? { nil }
    package func windowRuleNote(_ field: String) -> (ConfigNote.Kind, String)? { nil }
    package func knowsWindowRuleField(_ field: String) -> Bool { false }
    package func dispatcherNote(_ name: String) -> (ConfigNote.Kind, String)? { nil }
    package func knowsDispatcher(_ name: String) -> Bool { false }
}
