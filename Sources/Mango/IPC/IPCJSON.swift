import Foundation
import CoreGraphics

/// Not in mango: an insertion-ordered JSON value, as cJSON keeps the order (Foundation does not).
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        a.serialized == b.serialized
    }

    public var serialized: String {
        var out = ""
        write(into: &out)
        return out
    }

    /// Not in mango: JSON encoding for the IPC replies.
    func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += JSONValue.formatNumber(d)
        case .string(let s): JSONValue.escape(s, into: &out)
        case .array(let items):
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case .object(let pairs):
            out += "{"
            for (i, (k, v)) in pairs.enumerated() {
                if i > 0 { out += "," }
                JSONValue.escape(k, into: &out)
                out += ":"
                v.write(into: &out)
            }
            out += "}"
        }
    }

    /// Not in mango: JSON encoding for the IPC replies.
    static func formatNumber(_ d: Double) -> String {
        if d.isNaN || d.isInfinite { return "null" }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        let s15 = String(format: "%1.15g", d)
        if Double(s15) == d { return s15 }
        return String(format: "%1.17g", d)
    }

    /// Not in mango: JSON encoding for the IPC replies.
    public static func escape(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    /// Not in mango: JSON encoding for the IPC replies.
    public static func escaped(_ s: String) -> String {
        var out = ""
        escape(s, into: &out)
        return out
    }
}

public enum IPCJSON {
    /// Not in mango: the error object of the IPC replies.
    public static func error(_ message: String) -> JSONValue {
        .object([("error", .string(message))])
    }

    public static let success: JSONValue = .object([("success", .bool(true))])

    public static let monitorNotFound = error("monitor not found")
    public static let noFocusedClient = error("no focused client")
    public static let clientNotFound = error("client not found")
    public static let noClientFound = error("no client found")
    public static let unknownFunction = error("unknown function")
    public static let unknownCommand = error("unknown command")

    public static let nullClientRef: JSONValue = .object([
        ("id", .null), ("title", .null), ("appid", .null),
    ])

/// not in mango: no libinput on macOS; always empty.
    public static let allDevices: JSONValue = .object([("devices", .array([]))])
/// not in mango: no layer-shell on macOS; always empty.
    public static let allLayers: JSONValue = .object([("layers", .array([]))])
    public static let nullDevice: JSONValue = .object([("name", .null), ("type", .null)])
}

@MainActor
package extension MangoServer {
    func buildTagsJson(_ m: Monitor) -> JSONValue {
        let active = getMonitorActiveTagset(m)
        return .array((1...config.tagNum).map { i in
            let bit: UInt32 = 1 << UInt32(i - 1)
            let onTag = clients.filter { $0.mon === m && $0.tags & bit != 0 }
            return .object([
                ("index", .int(i)),
                ("is_active", .bool(active & bit != 0)),
                ("is_urgent", .bool(onTag.contains { $0.isUrgent })),
                ("layout", .string(m.pertag[i].layout.symbol)),
                ("client_count", .int(onTag.count)),
            ])
        })
    }

    func monitorActiveClient(_ m: Monitor) -> JSONValue {
        guard let c = m.sel.flatMap({ clientByIdAll($0) }) else { return IPCJSON.nullClientRef }
        return .object([("id", .int(Int(c.id))), ("title", .string(c.title)), ("appid", .string(c.appid))])
    }

    func monitorActiveTags(_ m: Monitor) -> JSONValue {
        if overviewState?.monitor === m { return .array([.int(0)]) }
        return .array(TagMask.tagsMaskToArray(getMonitorActiveTagset(m), tagNum: config.tagNum).map { .int($0) })
    }

    func buildAllTagsResponse() -> JSONValue {
        .object([("all_tags", .array(monitors.map { m in
            .object([("monitor", .string(m.screen.name)), ("tags", buildTagsJson(m))])
        }))])
    }

    func buildMonitorTagsResponse(_ m: Monitor) -> JSONValue {
        .object([
            ("monitor", .string(m.screen.name)),
            ("tags", buildTagsJson(m)),
            ("active_tags", monitorActiveTags(m)),
        ])
    }

    func buildLayoutsResponse() -> JSONValue {
        .object([("layouts", .array(LayoutKind.allCases.map {
            .object([("symbol", .string($0.symbol)), ("name", .string($0.name))])
        }))])
    }

    func buildClientJson(_ c: Client) -> JSONValue {
        let f = c.geom ?? c.frame
        let group = c.isGroupMember
        return .object([
            ("id", .int(Int(c.id))),
            ("pid", .int(Int(c.pid))),
            ("foreign_toplevel_id", .string(String(c.id))),
            ("title", .string(c.title)),
            ("appid", .string(c.appid)),
            ("monitor", .string(c.mon?.screen.name ?? "")),
            ("tags", .array(TagMask.tagsMaskToArray(c.tags, tagNum: config.tagNum).map { .int($0) })),
            ("is_xwayland", .bool(false)),
            ("is_swallowing", .bool(false)),
            ("is_swallowedby", .bool(false)),
            ("is_group", .bool(group)),
            ("is_group_focus", .bool(group && c.isGroupFocus)),
            ("is_visible", .bool(c.mon.map { c.isVisible(on: $0) } ?? false)),
            ("is_focused", .bool(c.mon === selectedMonitor && selectedMonitor.sel == c.id)),
            ("is_fullscreen", .bool(c.isFullscreen)),
            ("is_floating", .bool(c.isFloating)),
            ("is_maximized", .bool(c.isMaximizeScreen)),
            ("is_global", .bool(c.isGlobal)),
            ("is_unglobal", .bool(c.isUnglobal)),
            ("is_overlay", .bool(c.isOverlay)),
            ("is_fakefullscreen", .bool(c.isFakeFullscreen)),
            ("is_minimized", .bool(c.isMinimized)),
            ("is_urgent", .bool(c.isUrgent)),
            ("is_scratchpad", .bool(c.isInScratchpad)),
            ("is_namedscratchpad", .bool(c.isNamedScratchpad)),
            ("x", .int(Int(f.minX))),
            ("y", .int(Int(f.minY))),
            ("width", .int(Int(f.width))),
            ("height", .int(Int(f.height))),
            ("scroller_proportion", .double(Double(Float(c.scrollerProportion ?? c.mon?.current.settings.scrollerDefaultProportion ?? 0)))),
        ])
    }

    func buildAllClientsArray() -> JSONValue {
        var out: [JSONValue] = []
        for c in clients {
            out.append(buildClientJson(c))
            guard c.isGroupMember else { continue }
            var it: Client? = clientGroupHead(c)
            while let x = it {
                if x.groupParked { out.append(buildClientJson(x)) }
                it = x.groupNext
            }
        }
        return .array(out)
    }

    func buildMonitorJson(_ m: Monitor) -> JSONValue {
        let f = m.screen.frame
        return .object([
            ("name", .string(m.screen.name)),
            ("active", .bool(m === selectedMonitor)),
            ("is_hdr", .bool(false)),
            ("is_vrr", .bool(false)),
            ("x", .int(Int(f.minX))),
            ("y", .int(Int(f.minY))),
            ("width", .int(Int(f.width))),
            ("height", .int(Int(f.height))),
            ("scale", .double(Double(Float(m.screen.scale)))),
            ("layout_index", .int(m.layout.rawValue)),
            ("layout_symbol", .string(m.layout.symbol)),
            ("last_open_surface", .string("")),
            ("tag_num", .int(config.tagNum)),
            ("hide_clients", .int(overviewState != nil ? 1 : 0)),
            ("tags", buildTagsJson(m)),
            ("active_tags", monitorActiveTags(m)),
            ("active_client", monitorActiveClient(m)),
            ("keymode", .string(keyMode)),
            ("keyboardlayout", .string(system.keyboardLayout)),
        ])
    }

    func monitorByName(_ name: String) -> Monitor? { monitors.first { $0.screen.name == name } }

    func ipcFocusingClient() -> Client? { focused ?? selectedMonitor.sel.flatMap { clientByIdAll($0) } }

    // not in mango: the watcher's line, which mango's ipc_notify_* functions build each
    func watchPayload(_ w: IPCWatch) -> JSONValue? {
        switch w.kind {
        case .monitor:
            return w.monitorName.flatMap(monitorByName).map(buildMonitorJson)
        case .lastOpenSurface:
            let m = w.monitorName.map(monitorByName) ?? selectedMonitor
            return m.map { .object([("monitor", .string($0.screen.name)), ("last_open_surface", .string(""))]) }
        case .focusingClient:
            return ipcFocusingClient().map(buildClientJson) ?? IPCJSON.nullClientRef
        case .client:
            return clientByIdAll(w.clientID).map(buildClientJson)
        case .tags:
            return w.monitorName.flatMap(monitorByName).map(buildMonitorTagsResponse)
        case .allMonitors:
            return .object([("monitors", .array(monitors.map(buildMonitorJson)))])
        case .allTags:
            return buildAllTagsResponse()
        case .allClients:
            return .object([("clients", buildAllClientsArray())])
        case .allDevices:
            return IPCJSON.nullDevice
        case .keymode:
            return .object([("keymode", .string(keyMode))])
        case .keyboardLayout:
            return .object([("layout", .string(system.keyboardLayout))])
        }
    }
}
