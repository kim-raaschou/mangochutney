import Foundation

public enum TagMask {
    public static let special: UInt32 = 1 << 31
    public static let all: UInt32 = 0xFFFF_FFFF

    // not in mango: TAGMASK, which update_global_var keeps, worked out where it is used
    public static func mask(forTagNum n: Int) -> UInt32 {
        n >= 31 ? 0x7FFF_FFFF : (UInt32(1) << UInt32(n)) - 1
    }

    public static func parseTagMask(_ s: String) -> UInt32 {
        var m: UInt32 = 0
        for part in s.split(separator: "|") {
            let token = part.trimmingCharacters(in: .whitespaces)
            let n = ValueParse.atoi(token)
            if n == 0 && token == "0" { m |= special } else if n > 0 && n <= 31 { m |= UInt32(1) << UInt32(n - 1) }
        }
        if m & special != 0 && m & ~special != 0 { m = special }
        return m != 0 ? m : UInt32(truncatingIfNeeded: ValueParse.atoi(s))
    }

    public static func tagsMaskToArray(_ mask: UInt32, tagNum: Int = 31) -> [Int] {
        var out: [Int] = []
        if mask & special != 0 { out.append(0) }
        for i in 0..<min(max(tagNum, 0), 31) where mask & (UInt32(1) << UInt32(i)) != 0 { out.append(i + 1) }
        return out
    }

    public static func getTagsFirstTagNum(_ mask: UInt32) -> Int? {
        if mask == 0 { return nil }
        if mask & special != 0 { return 0 }
        return (mask & 0x7FFF_FFFF).trailingZeroBitCount + 1
    }
}

/// Not in mango: `name` is matched against the display's localized name.
public struct MonitorSpec: Equatable, Hashable, Sendable {
    public var name: String?
    public var make: String?
    public var model: String?
    public var serial: String?

    public init(name: String? = nil, make: String? = nil, model: String? = nil, serial: String? = nil) {
        self.name = name; self.make = make; self.model = model; self.serial = serial
    }

    public init(mango: String) {
        let s = mango.trimmingCharacters(in: .whitespaces)
        if !s.contains(":") { name = s.isEmpty ? nil : s; return }
        for part in s.components(separatedBy: "&&") {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let k = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let v = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch k {
            case "name": name = v
            case "make": make = v
            case "model": model = v
            case "serial": serial = v
            default: break
            }
        }
    }

    public func matchMonitorSpec(name n: String, make mk: String = "", model md: String = "", serial sn: String = "") -> Bool {
        if let name, !(n.range(of: name, options: .regularExpression) != nil) { return false }
        if let make, make != mk { return false }
        if let model, model != md { return false }
        if let serial, serial != sn { return false }
        return true
    }
}

/// Not in mango: `app_id` is matched against the bundle id and the app's name.
public struct WindowRule: Equatable, Sendable {
    public var appId: String?
    public var title: String?
    public var once = false
    public var isOnceApplied = false

    public var isFloating: Bool?
    public var isFullscreen: Bool?
    public var isFakeFullscreen: Bool?
    public var isGlobal: Bool?
    public var isOverlay: Bool?
    public var isOpenSilent: Bool?
    public var isTagSilent: Bool?
    public var isNamedScratchpad: Bool?
    public var isUnmanagedGlobal: Bool?
    public var isTerm: Bool?
    public var noSwallow: Bool?

    public var tags: UInt32?
    public var monitor: MonitorSpec?
    public var width: Double?
    public var height: Double?
    public var offsetX: Int?
    public var offsetY: Int?
    public var noForceCenter: Bool?
    public var noSizeHint: Bool?

    public var noBorder: Bool?
    public var noShadow: Bool?
    public var noRadius: Bool?
    public var noBlur: Bool?
    public var noAnimation: Bool?
    public var noFadeIn: Bool?
    public var noFadeOut: Bool?
    public var focusedOpacity: Double?
    public var unfocusedOpacity: Double?
    public var allowCsd: Bool?
    public var animationTypeOpen: AnimationType?
    public var animationTypeClose: AnimationType?

    public var scrollerProportion: Double?
    public var scrollerProportionSingle: Double?

    public var noFocus: Bool?
    public var confinePointer: Bool?
    public var ignoreMaximize: Bool?
    public var ignoreMinimize: Bool?
    public var forceTiledState: Bool?
    public var globalKeyBinding: String?

    public init() {}

    public func isWindowRuleMatches(appId id: String, appName: String, title t: String) -> Bool {
        var matched = false
        if let appId {
            let hit = id.range(of: appId, options: .regularExpression) != nil
                || appName.range(of: appId, options: .regularExpression) != nil   // not in mango: the app's name too (macOS app ids are bundle ids)
            if !hit { return false }
            matched = true
        }
        if let title {
            if t.range(of: title, options: .regularExpression) == nil { return false }
            matched = true
        }
        return matched
    }
}

public struct TagRule: Equatable, Sendable {
    public var id: Int?
    public var layoutName: String?
    public var monitorName: String?
    public var monitorMake: String?
    public var monitorModel: String?
    public var monitorSerial: String?
    public var noRenderBorder: Bool?
    public var openAsFloating: Bool?
    public var noHide: Bool?
    public var masterCount: Int?
    public var masterFactor: Double?
    public var scrollerDefaultProportion: Double?
    public var scrollerDefaultProportionSingle: Double?
    public var scrollerIgnoreProportionSingle: Bool?

    public init() {}

    public func tagRuleMatchesMonitor(_ m: Screen) -> Bool {
        if let monitorName, m.name.range(of: monitorName, options: .regularExpression) == nil { return false }
        if let monitorMake, m.make == nil || monitorMake != m.make { return false }
        if let monitorModel, m.model == nil || monitorModel != m.model { return false }
        if let monitorSerial, m.serial == nil || monitorSerial != m.serial { return false }
        return true
    }
}
