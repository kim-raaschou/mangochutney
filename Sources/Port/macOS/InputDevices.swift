import Foundation
import IOKit
import IOKit.hid
import Mango

/// Mango's input devices (server.input_devices) from IOKit's HID devices: what libinput and
/// wlroots give mango on Linux. Each HID interface gives a device per kind it has (as libinput
/// gives a keyboard and a pointer for one node with both); interfaces at one location (USB port,
/// Bluetooth device) are one physical device (libinput's device group).
enum InputDevices {
    static func all() -> [InputDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        var found: [(id: UInt64, devices: [InputDevice])] = []
        for d in set {
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(d), &id)
            let devices = devices(d, id)
            if !devices.isEmpty { found.append((id, devices)) }
        }
        return found.sorted { $0.id < $1.id }.flatMap(\.devices)
    }

    private static func devices(_ d: IOHIDDevice, _ registryID: UInt64) -> [InputDevice] {
        func int(_ key: String) -> Int { (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0 }
        let pairs = (IOHIDDeviceGetProperty(d, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []).map {
            (page: ($0[kIOHIDDeviceUsagePageKey] as? NSNumber)?.intValue ?? 0,
             usage: ($0[kIOHIDDeviceUsageKey] as? NSNumber)?.intValue ?? 0)
        }
        func has(_ page: Int, _ usages: Set<Int>) -> Bool { pairs.contains { $0.page == page && usages.contains($0.usage) } }
        let desktop = kHIDPage_GenericDesktop, digitizer = kHIDPage_Digitizer
        let touchpad = has(digitizer, [kHIDUsage_Dig_TouchPad])
        var types: [(WlrInputDeviceType, Int)] = []
        if has(desktop, [kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad]) { types.append((.keyboard, 0)) }
        if touchpad || has(desktop, [kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer]) {
            types.append((.pointer, touchpad ? 3 : 0))
        }
        if has(digitizer, [kHIDUsage_Dig_TouchScreen]) { types.append((.touch, 0)) }
        if has(digitizer, [kHIDUsage_Dig_Digitizer, kHIDUsage_Dig_Pen]) { types.append((.tablet, 0)) }
        guard !types.isEmpty else { return [] }

        let name = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? ""
        let location = int(kIOHIDLocationIDKey)
        let group = location != 0 ? UInt64(UInt32(truncatingIfNeeded: location)) : registryID | 1 << 63
        return types.map { type, fingers in
            InputDevice(name: name, type: type, vendor: Int32(truncatingIfNeeded: int(kIOHIDVendorIDKey)),
                        product: Int32(truncatingIfNeeded: int(kIOHIDProductIDKey)), deviceGroup: group,
                        tapFingerCount: fingers)
        }
    }
}
