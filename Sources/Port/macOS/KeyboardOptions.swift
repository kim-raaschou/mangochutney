import Foundation
import IOKit
import IOKit.hid
import Mango

/// mango's xkb_rules_options on macOS: the options that move keys are done with the
/// keyboard's own key mapping (hidutil's UserKeyMapping, kept until the next restart of
/// macOS or until mango changes it). caps:hyper turns Caps Lock into F18, which the event
/// tap holds as mango's hyper (InputRouter); the others are plain key moves. Options that
/// do not move a key (layouts, compose, …) are macOS keyboard settings.
enum KeyboardOptions {
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

    /// chutney_hyper_key (port extension: not in mango): the key that becomes F18, held as
    /// Hyper as caps:hyper's Caps Lock is.
    static func hyperKeyMapping(_ key: String) -> Mapping? {
        switch key {
        case "caps_lock": return Mapping(src: capsLock, dst: f18)
        case "right_command": return Mapping(src: rightGUI, dst: f18)
        case "right_option": return Mapping(src: rightAlt, dst: f18)
        default: return nil
        }
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
