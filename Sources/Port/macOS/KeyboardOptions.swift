import Foundation
import IOKit
import IOKit.hid
import Mango

/// mango's xkb_rules_options on macOS: the options that move keys are done with the
/// keyboard's own key mapping (hidutil's UserKeyMapping, kept until the next restart of
/// macOS or until mango changes it). caps:hyper turns Caps Lock into F18, which the event
/// tap holds as mango's hyper (InputRouter); the others are plain key moves. Options that
/// do not move a key (layouts, compose, …) are macOS keyboard settings.
package enum KeyboardOptions {
    /// HID usages (keyboard page 7).
    static let capsLock: UInt64 = 0x7_0000_0039
    static let escape: UInt64 = 0x7_0000_0029
    static let f18: UInt64 = 0x7_0000_006D
    static let leftControl: UInt64 = 0x7_0000_00E0
    static let leftAlt: UInt64 = 0x7_0000_00E2
    static let leftGUI: UInt64 = 0x7_0000_00E3
    static let rightAlt: UInt64 = 0x7_0000_00E6
    static let rightGUI: UInt64 = 0x7_0000_00E7
    /// The macOS key code of F18 (kVK_F18): the hyper key's events.
    static let hyperKeyCode: UInt16 = 79

    struct Mapping: Equatable {
        var src: UInt64
        var dst: UInt64
    }

    /// The key moves for these xkb options (xkb's names); the first option that moves a key
    /// wins for it.
    static func mappings(_ options: [String]) -> [Mapping] {
        var out: [Mapping] = []
        func add(_ src: UInt64, _ dst: UInt64) {
            if !out.contains(where: { $0.src == src }) { out.append(Mapping(src: src, dst: dst)) }
        }
        for o in options {
            switch o {
            case "caps:hyper": add(capsLock, f18)
            case "caps:escape": add(capsLock, escape)
            case "caps:swapescape": add(capsLock, escape); add(escape, capsLock)
            case "caps:ctrl_modifier", "ctrl:nocaps": add(capsLock, leftControl)
            case "ctrl:swapcaps": add(capsLock, leftControl); add(leftControl, capsLock)
            case "caps:super": add(capsLock, leftGUI)
            case "altwin:swap_alt_win": add(leftAlt, leftGUI); add(leftGUI, leftAlt); add(rightAlt, rightGUI); add(rightGUI, rightAlt)
            default: break
            }
        }
        return out
    }

    /// A key chutney_hyper_key can make Hyper (port extension: not in mango), as Raycast's
    /// Hyper Key offers them: its HID usage, its name in a menu, its key cap, and for a key that
    /// is no modifier the key code a quick press sends as the key itself.
    package struct HyperKey {
        package let name: String
        let usage: UInt64
        package let label: String
        package let symbol: String
        package let original: UInt16?
    }

    /// kVK_CapsLock: a quick press of Caps Lock as itself turns its lock on or off.
    static let capsLockKeyCode: UInt16 = 57

    package static let hyperKeys: [HyperKey] = {
        var keys = [HyperKey(name: "caps_lock", usage: capsLock, label: "Caps Lock", symbol: "⇪", original: capsLockKeyCode)]
        for (side, base) in [("left", UInt64(0)), ("right", UInt64(4))] {
            for (name, offset, symbol) in [("control", UInt64(0), "⌃"), ("shift", 1, "⇧"), ("option", 2, "⌥"), ("command", 3, "⌘")] {
                keys.append(HyperKey(name: "\(side)_\(name)", usage: leftControl + base + offset,
                                     label: "\(side.capitalized) \(symbol)", symbol: symbol, original: nil))
            }
        }
        // kVK_F1 … kVK_F12.
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in codes.enumerated() {
            keys.append(HyperKey(name: "f\(i + 1)", usage: 0x7_0000_003A + UInt64(i), label: "F\(i + 1)",
                                 symbol: "F\(i + 1)", original: code))
        }
        return keys
    }()

    package static func hyperKey(_ name: String) -> HyperKey? { hyperKeys.first { $0.name == name } }

    /// chutney_hyper_key: the key that becomes F18, held as Hyper as caps:hyper's Caps Lock is.
    static func hyperKeyMapping(_ name: String) -> Mapping? {
        hyperKey(name).map { Mapping(src: $0.usage, dst: f18) }
    }

    /// Caps Lock's lock turned over: a quick press of the Caps Lock key that is Hyper, as itself
    /// (chutney_hyper_tap original).
    static func toggleCapsLock() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), !on)
    }

    /// hidutil's argument for these mappings.
    static func hidutilJSON(_ m: [Mapping]) -> String {
        let items = m.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}" }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    /// The mapping moves Caps Lock and puts no key in its place: nothing can turn its lock
    /// off any more (caps:hyper, caps:escape, ctrl:nocaps, caps:super).
    static func takesCapsLock(_ m: [Mapping]) -> Bool {
        m.contains { $0.src == capsLock } && !m.contains { $0.dst == capsLock }
    }

    /// Caps Lock's lock off: it was on when its key was moved (or another remapper, such as
    /// Karabiner, left it on), and every letter would stay a capital.
    static func capsLockOff() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        var on = false
        IOHIDGetModifierLockState(connect, Int32(kIOHIDCapsLockState), &on)
        guard on else { return }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), false)
        Log.info("xkb_rules_options: Caps Lock's key is moved; its lock turned off")
    }

    /// Sets the keyboard's key mapping (macOS's own hidutil).
    static func apply(_ m: [Mapping]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", hidutilJSON(m)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            Log.error("hidutil failed: \(error)")
        }
    }
}
