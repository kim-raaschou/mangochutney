import Foundation
import IOKit
import IOKit.hid
import Mango

package enum KeyboardOptions {
    static let capsLock: UInt64 = 0x7_0000_0039
    static let escape: UInt64 = 0x7_0000_0029
    static let f18: UInt64 = 0x7_0000_006D
    static let leftControl: UInt64 = 0x7_0000_00E0
    static let leftAlt: UInt64 = 0x7_0000_00E2
    static let leftGUI: UInt64 = 0x7_0000_00E3
    static let rightAlt: UInt64 = 0x7_0000_00E6
    static let rightGUI: UInt64 = 0x7_0000_00E7
    static let hyperKeyCode: UInt16 = 79

    struct Mapping: Equatable {
        var src: UInt64
        var dst: UInt64
    }

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

    package struct HyperKey {
        package let name: String
        let usage: UInt64
        package let label: String
        package let symbol: String
        package let isModifier: Bool
    }

    package static let hyperKeys: [HyperKey] = {
        var keys = [HyperKey(name: "caps_lock", usage: capsLock, label: "Caps Lock", symbol: "⇪", isModifier: false)]
        for (side, base) in [("left", UInt64(0)), ("right", UInt64(4))] {
            for (name, offset, symbol) in [("control", UInt64(0), "⌃"), ("shift", 1, "⇧"), ("option", 2, "⌥"), ("command", 3, "⌘")] {
                keys.append(HyperKey(name: "\(side)_\(name)", usage: leftControl + base + offset,
                                     label: "\(side.capitalized) \(symbol)", symbol: symbol, isModifier: true))
            }
        }
        for i in 0..<12 {
            keys.append(HyperKey(name: "f\(i + 1)", usage: 0x7_0000_003A + UInt64(i), label: "F\(i + 1)",
                                 symbol: "F\(i + 1)", isModifier: false))
        }
        return keys
    }()

    package static func hyperKey(_ name: String) -> HyperKey? { hyperKeys.first { $0.name == name } }

    static func hyperKeyMapping(_ name: String) -> Mapping? {
        hyperKey(name).map { Mapping(src: $0.usage, dst: f18) }
    }

    static func hidutilJSON(_ m: [Mapping]) -> String {
        let items = m.map { "{\"HIDKeyboardModifierMappingSrc\":\($0.src),\"HIDKeyboardModifierMappingDst\":\($0.dst)}" }
        return "{\"UserKeyMapping\":[\(items.joined(separator: ","))]}"
    }

    static func takesCapsLock(_ m: [Mapping]) -> Bool {
        m.contains { $0.src == capsLock } && !m.contains { $0.dst == capsLock }
    }

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
        wlrLog(.info, "xkb_rules_options: Caps Lock's key is moved; its lock turned off")
    }

    static func apply(_ m: [Mapping]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--set", hidutilJSON(m)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 { wlrLog(.error, "hidutil failed: exit status \(p.terminationStatus)") }
        } catch {
            wlrLog(.error, "hidutil failed: \(error)")
        }
    }

    static func current() -> [Mapping]? {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = ["property", "--get", "UserKeyMapping"]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return parseUserKeyMapping(String(decoding: data, as: UTF8.self))
        } catch {
            wlrLog(.error, "hidutil failed: \(error)")
            return nil
        }
    }

    static func parseUserKeyMapping(_ text: String) -> [Mapping] {
        var blocks: [[Mapping]] = [[]]
        var dst: UInt64?, src: UInt64?
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.contains("UserKeyMapping") { blocks.append([]); dst = nil; src = nil }
            func value(_ key: String) -> UInt64? {
                guard t.hasPrefix(key + " = ") else { return nil }
                return UInt64(t.dropFirst(key.count + 3).trimmingCharacters(in: CharacterSet(charactersIn: ";")))
            }
            if let v = value("HIDKeyboardModifierMappingDst") { dst = v }
            if let v = value("HIDKeyboardModifierMappingSrc") { src = v }
            if let d = dst, let s = src {
                blocks[blocks.count - 1].append(Mapping(src: s, dst: d))
                dst = nil; src = nil
            }
        }
        return blocks.first { !$0.isEmpty } ?? []
    }

    static func merged(user: [Mapping], mango: [Mapping]) -> [Mapping] {
        user.filter { u in !mango.contains { $0.src == u.src } } + mango
    }
}
