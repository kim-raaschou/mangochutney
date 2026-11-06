import CoreGraphics
import Foundation
import IOKit

/// not in mango: wlroots reads make, model and serial from the EDID; macOS keeps them in the
/// IORegistry's DisplayAttributes (Apple silicon). make is the PNP ID, as wlroots falls back to
/// when its PNP table does not know the vendor (docs/afvigelser.md §3).
enum DisplayIdentity {
    struct Identity { var make: String?; var model: String?; var serial: String? }

    static func of(_ id: CGDirectDisplayID) -> Identity? {
        let vendor = Int(CGDisplayVendorNumber(id)), product = Int(CGDisplayModelNumber(id))
        let serialNumber = Int(CGDisplaySerialNumber(id))
        let hits = productAttributes().filter {
            $0["LegacyManufacturerID"] as? Int == vendor && $0["ProductID"] as? Int == product
                && ($0["SerialNumber"] as? Int ?? 0) == serialNumber
        }
        guard let a = hits.first else { return nil }
        let make = a["ManufacturerID"] as? String
        // di_info_get_model: the product name, else the product code.
        let model = (a["ProductName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? String(format: "0x%04X", product)
        // di_info_get_serial: the serial string, else the serial number when not 0.
        // Two identical screens with no serial cannot be told apart: no serial then.
        var serial = (a["AlphanumericSerialNumber"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (serialNumber != 0 ? String(format: "0x%08X", serialNumber) : nil)
        if hits.count > 1 { serial = nil }
        return Identity(make: make, model: model, serial: serial)
    }

    private static func productAttributes() -> [[String: Any]] {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &it)
                == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(it) }
        var out: [[String: Any]] = []
        while case let s = IOIteratorNext(it), s != 0 {
            defer { IOObjectRelease(s) }
            guard let attrs = IORegistryEntryCreateCFProperty(s, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
                  let product = attrs["ProductAttributes"] as? [String: Any] else { continue }
            out.append(product)
        }
        return out
    }
}
