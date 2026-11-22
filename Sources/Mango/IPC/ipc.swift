import Foundation
import Darwin

/// mango enum ipc_watch_type (ipc/ipc.h)
public struct IPCWatchType: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let monitor = IPCWatchType(rawValue: 1 << 0)
    public static let client = IPCWatchType(rawValue: 1 << 1)
    public static let tags = IPCWatchType(rawValue: 1 << 2)
    public static let allMonitors = IPCWatchType(rawValue: 1 << 3)
    public static let allTags = IPCWatchType(rawValue: 1 << 4)
    public static let allClients = IPCWatchType(rawValue: 1 << 5)
    public static let keymode = IPCWatchType(rawValue: 1 << 6)
    public static let kbLayout = IPCWatchType(rawValue: 1 << 7)
    public static let lastOpenSurface = IPCWatchType(rawValue: 1 << 8)
    public static let focusingClient = IPCWatchType(rawValue: 1 << 9)
    public static let device = IPCWatchType(rawValue: 1 << 10)

    /// IPC_WATCH_ARRANGGE
    public static let arrangge: IPCWatchType = [.monitor, .client, .tags, .allMonitors, .allTags, .allClients,
                                                .lastOpenSurface, .focusingClient]
}

/// mango struct ipc_watch_client's type and target (ipc/ipc.h)
public struct IPCWatch: Equatable, Sendable {
    public var type: IPCWatchType
    public var monitorName: String?
    public var clientID: ClientID = 0

    public init(type: IPCWatchType, monitorName: String? = nil, clientID: ClientID = 0) {
        self.type = type; self.monitorName = monitorName; self.clientID = clientID
    }

    // not in mango: handle_watch_command's parsing, apart
    public static func parse(_ cmd: String) -> IPCWatch? {
        if cmd.hasPrefix("watch monitor ") {
            return IPCWatch(type: .monitor, monitorName: String(cmd.dropFirst(14)))
        } else if cmd == "watch focusing-client" {
            return IPCWatch(type: .focusingClient)
        } else if cmd.hasPrefix("watch client ") {
            return IPCWatch(type: .client, clientID: IPCRequest.clientID(atoi: cmd.dropFirst(13)))
        } else if cmd.hasPrefix("watch tags ") {
            return IPCWatch(type: .tags, monitorName: String(cmd.dropFirst(11)))
        } else if cmd == "watch all-monitors" {
            return IPCWatch(type: .allMonitors)
        } else if cmd == "watch all-tags" {
            return IPCWatch(type: .allTags)
        } else if cmd == "watch all-clients" {
            return IPCWatch(type: .allClients)
        } else if cmd == "watch all-devices" {
            return IPCWatch(type: .device)
        } else if cmd == "watch keymode" {
            return IPCWatch(type: .keymode)
        } else if cmd == "watch keyboardlayout" {
            return IPCWatch(type: .kbLayout)
        } else if cmd == "watch last_open_surface" {
            return IPCWatch(type: .lastOpenSurface, monitorName: nil)
        } else if cmd.hasPrefix("watch last_open_surface ") {
            let arg = String(cmd.dropFirst(24))
            return IPCWatch(type: .lastOpenSurface, monitorName: arg.isEmpty ? nil : arg)
        }
        return nil
    }

    // not in mango: wc->target, the name kept in its char[64]
    var target: IPCWatch {
        var t = self
        if let name = monitorName, name.utf8.count > 63 {
            t.monitorName = String(decoding: name.utf8.prefix(63), as: UTF8.self)
        }
        return t
    }
}

// not in mango: a line of the socket parsed, apart from ipc_handle_client_data and handle_command
public enum IPCRequest: Equatable, Sendable {
    case get(String)
    case dispatch(Dispatch, target: ClientID?)
    case watch(IPCWatch)
    case unknown

    // not in mango: the line parsed into a request, apart from ipc_handle_client_data
    public static func parse(_ rawLine: String) -> IPCRequest {
        var raw = rawLine
        if raw.hasSuffix("\n") { raw.removeLast() }

        if let w = IPCWatch.parse(raw) { return .watch(w) }
        let cmd = String(decoding: raw.utf8.prefix(1023).map { $0 == 44 ? 32 : $0 }, as: UTF8.self)
        if cmd.hasPrefix("dispatch ") {
            let (d, target) = parseDispatch(String(raw.dropFirst(9)))
            return .dispatch(d, target: target)
        }
        if cmd.hasPrefix("get ") { return .get(cmd) }
        return .unknown
    }

    /// Not in mango: C's atoi in Swift.
    static func cAtoi(_ s: Substring) -> Int {
        var it = s.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{0B}" || $0 == "\u{0C}" })
        var negative = false
        if let f = it.first, f == "+" || f == "-" { negative = f == "-"; it = it.dropFirst() }
        var value = 0
        for ch in it {
            guard ch.isASCII, let d = ch.wholeNumberValue else { break }
            let (mul, o1) = value.multipliedReportingOverflow(by: 10)
            let (add, o2) = mul.addingReportingOverflow(d)
            if o1 || o2 { return negative ? Int.min : Int.max }
            value = add
        }
        return negative ? -value : value
    }

    /// Not in mango: C's (uint32_t)atoi for client ids.
    static func clientID(atoi s: Substring) -> ClientID {
        ClientID(truncatingIfNeeded: Int32(truncatingIfNeeded: cAtoi(s)))
    }

    // not in mango: handle_command's dispatch parsing, apart
    public static func parseDispatch(_ remainder: String) -> (Dispatch, ClientID?) {
        let bytes = Array(remainder.utf8)
        let space: UInt8 = 32, tab: UInt8 = 9, comma: UInt8 = 44
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        var clientID = -1
        var fieldStart = true
        let prefix = Array("client,".utf8)

        while i < bytes.count {
            while i < bytes.count && (bytes[i] == space || bytes[i] == tab) {
                out.append(bytes[i]); i += 1; fieldStart = true
            }
            if i >= bytes.count { break }

            if fieldStart && bytes.count - i >= prefix.count && Array(bytes[i..<(i + prefix.count)]) == prefix {
                var j = i + prefix.count
                while j < bytes.count && (bytes[j] == space || bytes[j] == tab || bytes[j] == 10 || bytes[j] == 13 || bytes[j] == 11 || bytes[j] == 12) { j += 1 }
                var negative = false
                if j < bytes.count && (bytes[j] == 43 || bytes[j] == 45) { negative = bytes[j] == 45; j += 1 }
                let digitsStart = j
                var id = 0
                while j < bytes.count && bytes[j] >= 48 && bytes[j] <= 57 {
                    let (m, o1) = id.multipliedReportingOverflow(by: 10)
                    let (a, o2) = m.addingReportingOverflow(Int(bytes[j] - 48))
                    id = o1 || o2 ? Int.max : a
                    j += 1
                }
                if negative { id = -id }
                if id > 0 && j > digitsStart && (j == bytes.count || bytes[j] == comma) {
                    clientID = Int(Int32(truncatingIfNeeded: id))
                    i = j
                    if i < bytes.count && bytes[i] == comma { i += 1 }
                    continue
                }
            }
            fieldStart = bytes[i] == comma
            out.append(bytes[i]); i += 1
        }

        var rest = Substring(String(decoding: out, as: UTF8.self))
        func trimmed<S: StringProtocol>(_ s: S) -> String {
            String(s).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        }
        func nextToken() -> String? {
            while rest.first == "," { rest = rest.dropFirst() }
            if rest.isEmpty { return nil }
            if let c = rest.firstIndex(of: ",") {
                let t = rest[..<c]
                rest = rest[rest.index(after: c)...]
                return trimmed(t)
            }
            let t = rest
            rest = rest[rest.endIndex...]
            return trimmed(t)
        }
        func remainderArg() -> String? {
            let r = trimmed(rest)
            rest = rest[rest.endIndex...]
            return r.isEmpty ? nil : r
        }

        let name = nextToken() ?? ""
        var args: [String] = []
        while args.count < 4, let t = nextToken() { args.append(t) }
        if args.count == 4, let r = remainderArg() { args.append(r) }
        let target: ClientID? = (clientID > 0 && clientID <= Int(ClientID.max)) ? ClientID(clientID) : nil
        return (Dispatch(name: name, args: args), target)
    }
}

// not in mango: ipc_init's failures, thrown to the caller
public enum IPCServerError: Error, CustomStringConvertible {
    case socketPathTooLong(String)
    case alreadyRunning(String)
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)

    public var description: String {
        switch self {
        case .socketPathTooLong(let p): return "IPC socket path too long for sun_path: \(p)"
        case .alreadyRunning(let p): return "another mango instance is listening on \(p)"
        case .socketFailed(let e): return "socket(): \(String(cString: strerror(e)))"
        case .bindFailed(let e): return "bind(): \(String(cString: strerror(e)))"
        case .listenFailed(let e): return "listen(): \(String(cString: strerror(e)))"
        }
    }
}

// not in mango: ipc.c's statics (the socket, its event source and the watch clients) as an object
@MainActor
public final class IPCServer {
    public static let environmentVariable = "MANGO_INSTANCE_SIGNATURE"

    // not in mango: /tmp/mango-<user>.sock, where mmsg looks; macOS has no XDG_RUNTIME_DIR
    nonisolated public static func defaultSocketPath() -> String {
        "/tmp/mango-\(NSUserName()).sock"
    }

    /// mango struct ipc_client_state (ipc/ipc.h)
    final class IPCClientState {
        let fd: Int32
        var buf: [UInt8] = []
        var source: EventSource?
        init(fd: Int32) { self.fd = fd }
    }

    /// mango struct ipc_watch_client (ipc/ipc.h)
    final class IPCWatchClient {
        let fd: Int32
        let watch: IPCWatch
        var source: EventSource?
        // not in mango: the last line sent, so an unchanged one is not sent again (docs/afvigelser.md §2)
        var lastPayload: String?
        init(fd: Int32, watch: IPCWatch) { self.fd = fd; self.watch = watch }
    }

    public let socketPath: String
    weak var server: MangoServer?
    // not in mango: the event loop (wl_event_loop), the port's
    let loop: EventLoop
    var ipcSocketFd: Int32 = -1
    var ipcEventSource: EventSource?
    var ipcWatchClients: [IPCWatchClient] = []
    // not in mango: the types of the turn's printstatus calls (docs/afvigelser.md §2)
    var pendingType: IPCWatchType = []

    public init(server: MangoServer, loop: EventLoop, socketPath: String = IPCServer.defaultSocketPath()) {
        self.server = server
        self.loop = loop
        self.socketPath = socketPath
    }

    public var isRunning: Bool { ipcSocketFd >= 0 }   // not in mango: whether ipc_init made the socket

    public var watcherCount: Int { ipcWatchClients.count }   // not in mango: for the tests
}

func ipcDeviceTypeStr(_ dev: InputDevice?) -> String {
    guard let dev else { return "unknown" }

    switch dev.type {
    case .keyboard:
        return "keyboard"
    case .pointer:
        return dev.tapFingerCount > 0
            ? "trackpad"
            : "pointer"
    case .touch:
        return "touch"
    case .switchDevice:
        return "switch"
    case .tablet:
        return "tablet"
    case .tabletPad:
        return "pad"
    }
}

/* ---------- Utils ---------- */
@MainActor
package extension MangoServer {
    func monitorByName(_ name: String) -> Monitor? {
        monitors.first { $0.screen.name == name }
    }

    func clientById(_ id: ClientID) -> Client? {
        clients.first { $0.id == id }
    }

    func clientByIdAll(_ id: ClientID) -> Client? {
        for c in clients {
            if c.id == id {
                return c
            }
            if !c.isGroupMember {
                continue
            }
            var it: Client? = clientGroupHead(c)
            while let x = it {
                if x.id == id {
                    return x
                }
                it = x.groupNext
            }
        }
        return nil
    }

    func ipcGetLayoutStr() -> String {
        system.ipcGetLayoutStr()   // not in mango: the port's side (xkb's layout name)
    }

    func buildTagsJson(_ m: Monitor) -> JSONValue {
        var tagsArray: [JSONValue] = []

        let activeTagset = getMonitorActiveTagset(m)
        for tag in 1...config.tagNum {
            var numclients = 0
            var isActive = false, isUrgent = false
            let tagBit: UInt32 = 1 << UInt32(tag - 1)
            if tagBit & activeTagset != 0 {
                isActive = true
            }
            for c in clients {
                if c.mon !== m {
                    continue
                }
                if c.tags & tagBit & TAGMASK == 0 {
                    continue
                }
                if c.isurgent {
                    isUrgent = true
                }
                numclients += 1
            }
            tagsArray.append(.object([
                ("index", .int(tag)),
                ("is_active", .bool(isActive)),
                ("is_urgent", .bool(isUrgent)),
                ("layout", .string(m.pertag.ltidxs[tag].symbol)),
                ("client_count", .int(numclients)),
            ]))
        }
        return .array(tagsArray)
    }

    func monitorActiveClient(_ m: Monitor) -> JSONValue {
        guard let c = m.sel.flatMap({ clientByIdAll($0) }) else {
            return .object([("id", .null), ("title", .null), ("appid", .null)])
        }
        return .object([("id", .int(Int(c.id))), ("title", .string(c.title)), ("appid", .string(c.appid))])
    }

    func buildAllTagsEntry(_ m: Monitor) -> JSONValue {
        .object([("monitor", .string(m.screen.name)), ("tags", buildTagsJson(m))])
    }

    func buildAllTagsResponse() -> JSONValue {
        .object([("all_tags", .array(monitors.map(buildAllTagsEntry)))])
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

    // not in mango: no layer_enum_str, macOS has no layer shell
    func buildLayersResponse() -> JSONValue {
        .object([("layers", .array([]))])   // not in mango: no layer surfaces on macOS
    }
}

@MainActor
extension IPCServer {
    func sendStaticJson(_ fd: Int32, _ json: String) {
        let data = Array(json.utf8)
        _ = data.withUnsafeBufferPointer { send(fd, $0.baseAddress, $0.count, 0) }
    }

    /* ---------- Watch mode support ---------- */
    func ipcNotifyJsonToFd(_ wc: IPCWatchClient, _ json: JSONValue) {
        let str = json.serialized
        // not in mango: an unchanged line is not sent again (docs/afvigelser.md §2)
        if str == wc.lastPayload { return }
        wc.lastPayload = str
        let msg = Array((str + "\n").utf8)
        if msg.withUnsafeBufferPointer({ send(wc.fd, $0.baseAddress, $0.count, 0) }) < 0 {
            ipcRemoveWatchClient(wc)
        }
    }

    // not in mango: no ipc_notify_device_event, macOS's key and pointer events do not say which
    // device they came from (docs/afvigelser.md §3)

    func ipcRemoveWatchClient(_ wc: IPCWatchClient) {
        ipcWatchClients.removeAll { $0 === wc }
        wc.source?.remove()
        wc.source = nil
        Darwin.close(wc.fd)
    }

    func ipcWatchDataHandler(_ wc: IPCWatchClient) {
        var buf = [UInt8](repeating: 0, count: 64)
        let n = recv(wc.fd, &buf, buf.count, 0)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            ipcRemoveWatchClient(wc)
        }
    }

    /* ---------- Socket event handling ---------- */
    func ipcHandleClientData(_ client: IPCClientState) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = recv(client.fd, &chunk, chunk.count, 0)
        if n <= 0 {
            cleanup()
            return
        }

        client.buf.append(contentsOf: chunk[0..<n])

        guard let nl = client.buf.firstIndex(of: 10) else {
            if client.buf.count > 1024 * 1024 {
                cleanup()
            }
            return
        }
        let cmd = String(decoding: client.buf[..<nl], as: UTF8.self)

        let isWatch = handleWatchCommand(client.fd, cmd, client)
        if isWatch {
            return
        }

        handleCommand(client.fd, cmd)
        cleanup()

        func cleanup() {
            Darwin.close(client.fd)
            client.source?.remove()
            client.source = nil
        }
    }

    func ipcHandleConnection() {
        let clientFd = accept(ipcSocketFd, nil, nil)
        if clientFd < 0 {
            return
        }

        // Sets O_NONBLOCK
        var flags = fcntl(clientFd, F_GETFL, 0)
        if flags == -1 || fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) == -1 {
            mangoError(true, .error, "failed to set O_NONBLOCK on IPC client socket")
            Darwin.close(clientFd)
            return
        }
        // Sets FD_CLOEXEC
        flags = fcntl(clientFd, F_GETFD, 0)
        if flags == -1 || fcntl(clientFd, F_SETFD, flags | FD_CLOEXEC) == -1 {
            mangoError(true, .error, "failed to set FD_CLOEXEC on IPC client socket")
            Darwin.close(clientFd)
            return
        }
        // not in mango: no SIGPIPE from a client gone (macOS has no MSG_NOSIGNAL), and a buffer that
        // takes a whole reply (macOS's is 8 KB; a send that does not fit is not waited out)
        var one: Int32 = 1
        _ = setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var size: Int32 = 1 << 20
        _ = setsockopt(clientFd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))

        let client = IPCClientState(fd: clientFd)
        client.source = loop.addFd(clientFd) { [weak self, client] in self?.ipcHandleClientData(client) }
    }

    func ipcNotifyClient(_ c: Client, _ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .client && c.id == wc.watch.clientID {
            ipcNotifyJsonToFd(wc, server.buildClientJson(c))
        }
    }

    func ipcNotifyTags(_ m: Monitor, _ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .tags && m.screen.name == wc.watch.monitorName {
            ipcNotifyJsonToFd(wc, server.buildMonitorTagsResponse(m))
        }
    }

    func ipcNotifyAllTags(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .allTags {
            ipcNotifyJsonToFd(wc, server.buildAllTagsResponse())
        }
    }

    // not in mango: printstatus's signal (print_status_signal), run once after the events waiting,
    // with the turn's types together (docs/afvigelser.md §2)
    public func notifyChanged(_ type: IPCWatchType) {
        guard isRunning, !ipcWatchClients.isEmpty else { return }
        let scheduled = !pendingType.isEmpty
        pendingType.formUnion(type)
        guard !scheduled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let type = pendingType
            pendingType = []
            handlePrintStatus(type)
        }
    }

    func handlePrintStatus(_ type: IPCWatchType) {
        guard isRunning, let server else { return }

        if type.contains(.keymode) {
            ipcNotifyKeymode(server)
        }
        if type.contains(.kbLayout) {
            ipcNotifyKbLayout(server)
        }
        if type.contains(.focusingClient) {
            ipcNotifyFocusingClient(server)
        }
        if type.contains(.allTags) {
            ipcNotifyAllTags(server)
        }
        if type.contains(.allClients) {
            ipcNotifyAllClients(server)
        }
        if !type.isDisjoint(with: [.allMonitors, .keymode, .kbLayout, .focusingClient, .tags]) {
            ipcNotifyAllMonitors(server)
        }

        if type.contains(.client) {
            for c in server.clients {
                if c.iskilling {
                    continue
                }
                ipcNotifyClient(c, server)
            }
        }

        for m in server.monitors {
            if type.contains(.monitor) {
                ipcNotifyMonitor(m, server)
            }
            if type.contains(.tags) {
                ipcNotifyTags(m, server)
            }

            if type.contains(.lastOpenSurface) {
                ipcNotifyLastSurfaceWsName(m, server)
            }

            // not in mango: no mango_ext_workspace_printstatus, macOS has no ext-workspace
        }
    }

    /* ---------- Init & cleanup ---------- */
    public func ipcCleanup() {
        ipcEventSource?.remove()
        ipcEventSource = nil
        if ipcSocketFd >= 0 {
            Darwin.close(ipcSocketFd)
        }
        ipcSocketFd = -1
        unlink(socketPath)
        // not in mango: the variable is unset only while it is this socket's
        if let current = getenv(IPCServer.environmentVariable), String(cString: current) == socketPath {
            unsetenv(IPCServer.environmentVariable)
        }

        for wc in ipcWatchClients {
            ipcRemoveWatchClient(wc)
        }
    }
}

@MainActor
package extension MangoServer {
    /// mango printstatus (ipc/ipc.c)
    func printstatus(_ type: IPCWatchType) {
        publishGlobalKeys()   // not in mango: the event tap's global keys, which follow the focus (input/keyboard.swift)
        ipc?.notifyChanged(type)
        onStateChange?()   // the boundary, not in mango: the port's status change
    }

    func tagsMaskToArray(_ tagMask: UInt32) -> JSONValue {
        var arr: [JSONValue] = []
        if tagMask & TAG0_MASK != 0 {
            arr.append(.int(0))
        }
        for i in 0..<config.tagNum {
            if tagMask & (1 << UInt32(i)) != 0 {
                arr.append(.int(i + 1))
            }
        }
        return .array(arr)
    }

    func monitorActiveTags(_ m: Monitor) -> JSONValue {
        var arr: [JSONValue] = []
        if m.isoverview {
            arr.append(.int(0))
            return .array(arr)
        }
        let tagset = getMonitorActiveTagset(m)
        for i in 0..<config.tagNum {
            if tagset & (1 << UInt32(i)) != 0 {
                arr.append(.int(i + 1))
            }
        }
        return .array(arr)
    }

    func clientOutputName(_ c: Client) -> String {
        if let m = c.mon {
            return m.screen.name
        }
        let active = clientGroupActive(c)
        return active?.mon?.screen.name ?? ""
    }

    func buildClientJson(_ c: Client) -> JSONValue {
        .object([
            ("id", .int(Int(c.id))),
            ("pid", .int(Int(c.pid))),
            ("foreign_toplevel_id", .string(String(c.id))),   // not in mango: no ext-foreign-toplevel, the id
            ("title", .string(c.title)),
            ("appid", .string(c.appid)),
            ("monitor", .string(clientOutputName(c))),
            ("tags", tagsMaskToArray(c.tags)),
            ("is_xwayland", .bool(false)),   // not in mango: no X11 clients
            ("is_swallowing", .bool(false)),   // not in mango: no swallowing (MangoCompat)
            ("is_swallowedby", .bool(false)),
            ("is_group", .bool(c.isGroupMember)),
            ("is_group_focus", .bool(c.isGroupMember && c.isGroupFocus)),
            ("is_visible", .bool(c.mon.map { VISIBLEON(c, $0) } ?? false)),
            ("is_focused", .bool(c.mon === selectedMonitor && selectedMonitor.sel == c.id)),   // not in mango: no isfocusing, the selected monitor's sel
            ("is_fullscreen", .bool(c.isfullscreen)),
            ("is_floating", .bool(c.isfloating)),
            ("is_maximized", .bool(c.ismaximizescreen)),
            ("is_global", .bool(c.isglobal)),
            ("is_unglobal", .bool(c.isunglobal)),
            ("is_overlay", .bool(c.isoverlay)),
            ("is_fakefullscreen", .bool(c.isfakefullscreen)),
            ("is_minimized", .bool(c.isminimized)),
            ("is_urgent", .bool(c.isurgent)),
            ("is_scratchpad", .bool(c.isInScratchpad)),
            ("is_namedscratchpad", .bool(c.isnamedscratchpad)),
            ("x", .int(Int(c.geom.minX))),
            ("y", .int(Int(c.geom.minY))),
            ("width", .int(Int(c.geom.width))),
            ("height", .int(Int(c.geom.height))),
            ("scroller_proportion", .double(Double(c.scrollerProportion))),
        ])
    }

    func buildAllClientsArray() -> JSONValue {
        var arr: [JSONValue] = []
        for c in clients {
            arr.append(buildClientJson(c))
            if !c.isGroupMember {
                continue
            }
            var it: Client? = clientGroupHead(c)
            while let x = it {
                if clientIsParked(x) {
                    arr.append(buildClientJson(x))
                }
                it = x.groupNext
            }
        }
        return .array(arr)
    }

    func transformToStr(_ t: Int32) -> String {
        switch t {
        case 0:
            return "normal"
        case 1:
            return "90"
        case 2:
            return "180"
        case 3:
            return "270"
        case 4:
            return "flipped"
        case 5:
            return "flipped-90"
        case 6:
            return "flipped-180"
        case 7:
            return "flipped-270"
        default:
            return "unknown"
        }
    }

    func buildMonitorJson(_ m: Monitor) -> JSONValue {
        .object([
            ("name", .string(m.screen.name)),
            ("active", .bool(m === selectedMonitor)),
            ("is_hdr", .bool(false)),   // not in mango: HDR is macOS's (MangoCompat)
            ("is_vrr", .bool(false)),   // not in mango: VRR is macOS's (MangoCompat)
            ("x", .int(Int(m.m.minX))),
            ("y", .int(Int(m.m.minY))),
            ("width", .int(Int(m.m.width))),
            ("height", .int(Int(m.m.height))),
            ("scale", .double(Double(Float(m.screen.scale)))),
            ("transform", .string(transformToStr(m.screen.transform))),
            ("layout_index", .int(m.pertag.ltidxs[getMonCurtag(m)].rawValue)),
            ("layout_symbol", .string(m.pertag.ltidxs[getMonCurtag(m)].symbol)),
            ("last_open_surface", .string("")),   // not in mango: set by layer-shell maps, which macOS does not have
            ("tag_num", .int(config.tagNum)),
            ("hide_clients", .int(Int(m.hideClients))),
            ("tags", buildTagsJson(m)),
            ("active_tags", monitorActiveTags(m)),
            ("active_client", monitorActiveClient(m)),
            ("keymode", .string(keyMode)),
            ("keyboardlayout", .string(ipcGetLayoutStr())),
        ])
    }
}

@MainActor
extension IPCServer {
    func handleCommand(_ clientFd: Int32, _ cmdRaw: String) {
        guard let server else {
            sendStaticJson(clientFd, "{\"error\":\"compositor unavailable\"}\n")   // not in mango: the weak server gone
            return
        }
        var resp: JSONValue?

        switch IPCRequest.parse(cmdRaw) {
        case .get(let cmd):
            if cmd == "get version" {
                resp = .object([("version", .string(VERSION))])
            } else if cmd == "get cursorpos" {
                let p = server.system.pointer
                resp = .object([("x", .double(Double(p.x))), ("y", .double(Double(p.y))),
                                ("monitor", server.monitorAtPoint(p).map { .string($0.screen.name) } ?? .null)])
            } else if cmd == "get keymode" {
                resp = .object([("keymode", .string(server.keyMode))])
            } else if cmd == "get keyboardlayout" {
                resp = .object([("layout", .string(server.ipcGetLayoutStr()))])
            } else if cmd == "get last_open_surface" || cmd.hasPrefix("get last_open_surface ") {
                let m: Monitor?
                if cmd == "get last_open_surface" { // exactly "get last_open_surface"
                    m = server.selectedMonitor
                } else {
                    m = server.monitorByName(String(cmd.dropFirst(22)))
                }
                guard let m else {
                    sendStaticJson(clientFd, "{\"error\":\"monitor not found\"}\n")
                    return
                }
                resp = .object([("monitor", .string(m.screen.name)),
                                ("last_open_surface", .string(""))])   // not in mango: no layer shell on macOS
            } else if cmd.hasPrefix("get monitor ") {
                guard let m = server.monitorByName(String(cmd.dropFirst(12))) else {
                    sendStaticJson(clientFd, "{\"error\":\"monitor not found\"}\n")
                    return
                }
                resp = server.buildMonitorJson(m)
            } else if cmd == "get focusing-client" {
                if let sel = server.selectedMonitor?.sel.flatMap({ server.clientByIdAll($0) }) {
                    resp = server.buildClientJson(sel)
                } else {
                    sendStaticJson(clientFd, "{\"error\":\"no focused client\"}\n")
                    return
                }
            } else if cmd.hasPrefix("get client ") {
                guard let c = server.clientByIdAll(IPCRequest.clientID(atoi: cmd.dropFirst(11))) else {
                    sendStaticJson(clientFd, "{\"error\":\"client not found\"}\n")
                    return
                }
                resp = server.buildClientJson(c)
            } else if cmd.hasPrefix("get tag ") {
                // not in mango: the last field is the tag, as macOS's monitor names have spaces (sscanf "%63s %d")
                let rest = Substring(cmd.dropFirst(8))
                let ws = CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}")
                let trimmedRest = rest.trimmingCharacters(in: ws)
                var monName = "", extTagText = Substring("")
                if let split = trimmedRest.unicodeScalars.lastIndex(where: { ws.contains($0) }) {
                    monName = String(trimmedRest.unicodeScalars[..<split]).trimmingCharacters(in: ws)
                    extTagText = Substring(String(trimmedRest.unicodeScalars[trimmedRest.unicodeScalars.index(after: split)...]))
                }
                var digits = extTagText
                if let f = digits.first, f == "+" || f == "-" { digits = digits.dropFirst() }
                guard !monName.isEmpty, let f = digits.first, f.isASCII, f.isNumber else {
                    sendStaticJson(clientFd, "{\"error\":\"usage: get tag <monitor> <index>\"}\n")
                    return
                }
                let extTagIdx = IPCRequest.cAtoi(extTagText)
                let tagIdx = extTagIdx - 1
                guard let m = server.monitorByName(monName), tagIdx >= 0, tagIdx < server.config.tagNum else {
                    sendStaticJson(clientFd, "{\"error\":\"invalid monitor or tag index\"}\n")
                    return
                }
                let tagBit: UInt32 = 1 << UInt32(tagIdx)
                var numclients = 0, focusedClient = false
                var isActive = false, isUrgent = false
                if tagBit & server.getMonitorActiveTagset(m) != 0 {
                    isActive = true
                }

                let focused = server.clientFocusTop(m)
                for c in server.clients {
                    if c.mon !== m || c.tags & tagBit == 0 {
                        continue
                    }
                    if c === focused {
                        focusedClient = true
                    }
                    if c.isurgent {
                        isUrgent = true
                    }
                    numclients += 1
                }
                resp = .object([
                    ("monitor", .string(m.screen.name)),
                    ("tag_index", .int(extTagIdx)),
                    ("is_active", .bool(isActive)),
                    ("is_urgent", .bool(isUrgent)),
                    ("client_count", .int(numclients)),
                    ("focused_client", .bool(focusedClient)),
                ])
            } else if cmd == "get all-clients" {
                resp = .object([("clients", server.buildAllClientsArray())])
            } else if cmd == "get all-monitors" {
                resp = .object([("monitors", .array(server.monitors.map(server.buildMonitorJson)))])
            } else if cmd == "get all-devices" {
                /* Aggregates and lists entries by physical device (libinput device
                 * group). */
                struct IPCDevGroup {
                    var group: UInt64
                    var name: String
                    var types: [String] = []
                    var vendor: Int32, product: Int32
                    var count = 0
                }
                var groups: [IPCDevGroup] = []

                for dev in server.system.inputDevices {
                    let grp = dev.deviceGroup

                    var gi = -1
                    for i in groups.indices where groups[i].group == grp {
                        gi = i
                        break
                    }
                    if gi < 0 {
                        gi = groups.count
                        groups.append(IPCDevGroup(group: grp, name: dev.name, vendor: dev.vendor, product: dev.product))
                    }
                    groups[gi].count += 1
                    // not in mango: no find_device_rule, device_rule has no effect on macOS

                    let type = ipcDeviceTypeStr(dev)
                    if !groups[gi].types.contains(type) && groups[gi].types.count < 8 {
                        groups[gi].types.append(type)
                    }
                }

                var arr: [JSONValue] = []
                for g in groups {
                    arr.append(.object([
                        ("name", .string(g.name)),
                        ("types", .array(g.types.map { .string($0) })),
                        ("vendor", .int(Int(g.vendor))),
                        ("product", .int(Int(g.product))),
                        ("identifier", .string("\(g.vendor):\(g.product):\(g.name)")),
                        ("interfaces", .int(g.count)),
                        ("matched", .bool(false)),   // not in mango: device_rule has no effect on macOS
                    ]))
                }

                resp = .object([("devices", .array(arr))])
            } else if cmd == "get all-layers" {
                resp = server.buildLayersResponse()
            } else if cmd == "get all-tags" {
                resp = server.buildAllTagsResponse()
            } else if cmd.hasPrefix("get tags ") {
                guard let m = server.monitorByName(String(cmd.dropFirst(9))) else {
                    sendStaticJson(clientFd, "{\"error\":\"monitor not found\"}\n")
                    return
                }
                resp = server.buildMonitorTagsResponse(m)
            } else if cmd == "get layouts" {
                resp = server.buildLayoutsResponse()
            } else if let get = server.portHooks.ipcGets[cmd] {
                resp = get(server)   // Port extension: not in mango (get binds)
            } else {
                sendStaticJson(clientFd, "{\"error\":\"unknown command\"}\n")
                return
            }
        case .dispatch(let dispatch, let clientId):
            var tc: Client?
            if let clientId {
                tc = server.clientById(clientId)
                if tc == nil && dispatch.name == "focusid" {
                    tc = server.clientByIdAll(clientId)
                }
                if tc == nil {
                    return sendStaticJson(clientFd, "{\"error\":\"no client found\"}\n")
                }
            }

            // not in mango: parse_func_name runs in dispatch, with "" for a field IPC does not give
            if Dispatch.isKnown(dispatch.name) {
                _ = server.dispatch(dispatch, target: tc, notGiven: "")
                sendStaticJson(clientFd, "{\"success\":true}\n")
            } else {
                sendStaticJson(clientFd, "{\"error\":\"unknown function\"}\n")
            }
            return // Fast path exit
        case .watch, .unknown:
            sendStaticJson(clientFd, "{\"error\":\"unknown command\"}\n")
            return
        }

        if let resp {
            sendStaticJson(clientFd, resp.serialized + "\n")
        }
    }

    func handleWatchCommand(_ fd: Int32, _ cmd: String, _ client: IPCClientState) -> Bool {
        guard let watch = IPCWatch.parse(cmd) else {
            return false
        }
        let type = watch.type
        let arg = watch.monitorName

        let wc = IPCWatchClient(fd: fd, watch: watch.target)

        client.source?.remove()
        client.source = nil
        wc.source = loop.addFd(fd) { [weak self, wc] in self?.ipcWatchDataHandler(wc) }
        ipcWatchClients.append(wc)

        guard let server else { return true }   // not in mango: the weak server gone

        /* Pushes the initial state. */
        var json: JSONValue?
        switch type {
        case .monitor:
            if let m = arg.flatMap(server.monitorByName) {
                json = server.buildMonitorJson(m)
            }
        case .lastOpenSurface:
            let m: Monitor? = arg != nil ? server.monitorByName(arg!) : server.selectedMonitor
            if let m {
                json = .object([("monitor", .string(m.screen.name)),
                                ("last_open_surface", .string(""))])   // not in mango: no layer shell on macOS
            }
        case .focusingClient:
            if let sel = server.selectedMonitor?.sel.flatMap({ server.clientByIdAll($0) }) {
                json = server.buildClientJson(sel)
            } else {
                json = .object([("id", .null), ("title", .null), ("appid", .null)])
            }
        case .client:
            if let c = server.clientByIdAll(watch.clientID) {
                json = server.buildClientJson(c)
            }
        case .tags:
            if let m = arg.flatMap(server.monitorByName) {
                json = server.buildMonitorTagsResponse(m)
            }
        case .allMonitors:
            json = .object([("monitors", .array(server.monitors.map(server.buildMonitorJson)))])
        case .allTags:
            json = server.buildAllTagsResponse()
        case .allClients:
            json = .object([("clients", .array(server.clients.map(server.buildClientJson)))])
        case .device:
            json = .object([("name", .null), ("type", .null)])
        case .keymode:
            json = .object([("keymode", .string(server.keyMode))])
        case .kbLayout:
            json = .object([("layout", .string(server.ipcGetLayoutStr()))])
        default:
            break
        }

        if let json {
            ipcNotifyJsonToFd(wc, json)
        }

        return true
    }

    /* ---------- External notification API ---------- */
    func ipcNotifyMonitor(_ m: Monitor, _ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .monitor && m.screen.name == wc.watch.monitorName {
            ipcNotifyJsonToFd(wc, server.buildMonitorJson(m))
        }
    }

    func ipcNotifyLastSurfaceWsName(_ m: Monitor, _ server: MangoServer) {
        for wc in ipcWatchClients {
            if wc.watch.type != .lastOpenSurface {
                continue
            }

            var match = false
            if let name = wc.watch.monitorName {
                if m.screen.name == name {
                    match = true
                }
            } else {
                if m === server.selectedMonitor {
                    match = true
                }
            }

            if !match {
                continue
            }

            ipcNotifyJsonToFd(wc, .object([("monitor", .string(m.screen.name)),
                                           ("last_open_surface", .string(""))]))   // not in mango: no layer shell on macOS
        }
    }

    func ipcNotifyFocusingClient(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .focusingClient {
            let json: JSONValue
            if let sel = server.selectedMonitor?.sel.flatMap({ server.clientByIdAll($0) }) {
                json = server.buildClientJson(sel)
            } else {
                json = .object([("id", .null), ("title", .null), ("appid", .null)])
            }
            ipcNotifyJsonToFd(wc, json)
        }
    }

    func ipcNotifyAllMonitors(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .allMonitors {
            ipcNotifyJsonToFd(wc, .object([("monitors", .array(server.monitors.map(server.buildMonitorJson)))]))
        }
    }

    func ipcNotifyAllClients(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .allClients {
            ipcNotifyJsonToFd(wc, .object([("clients", server.buildAllClientsArray())]))
        }
    }

    func ipcNotifyKeymode(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .keymode {
            ipcNotifyJsonToFd(wc, .object([("keymode", .string(server.keyMode))]))
        }
    }

    func ipcNotifyKbLayout(_ server: MangoServer) {
        for wc in ipcWatchClients where wc.watch.type == .kbLayout {
            ipcNotifyJsonToFd(wc, .object([("layout", .string(server.ipcGetLayoutStr()))]))
        }
    }

    /* ---------- Init & cleanup ---------- */

    // not in mango: the socket's failures thrown, and the socket the user's at /tmp/mango-<user>.sock
    public func ipcInit() throws {
        if ipcSocketFd >= 0 { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw IPCServerError.socketPathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for (i, b) in path.enumerated() { dst[i] = UInt8(bitPattern: b) }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        // not in mango: a socket another mango serves is not taken over (the path is the user's, not the pid's)
        if Self.isLive(addr) { throw IPCServerError.alreadyRunning(socketPath) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCServerError.socketFailed(errno) }

        var flags = fcntl(fd, F_GETFD, 0)
        if flags == -1 || fcntl(fd, F_SETFD, flags | FD_CLOEXEC) == -1 {
            mangoError(true, .error, "failed to set FD_CLOEXEC on IPC socket")
            Darwin.close(fd)
            throw IPCServerError.socketFailed(errno)
        }
        // Sets O_NONBLOCK
        flags = fcntl(fd, F_GETFL, 0)
        if flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1 {
            mangoError(true, .error, "failed to set O_NONBLOCK on IPC socket")
            Darwin.close(fd)
            throw IPCServerError.socketFailed(errno)
        }

        unlink(socketPath)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            Darwin.close(fd)
            throw IPCServerError.bindFailed(e)
        }
        chmod(socketPath, 0o600)   // not in mango: the socket is the user's alone (mango's is in its runtime dir)
        Darwin.listen(fd, 16)
        ipcSocketFd = fd

        setenv(IPCServer.environmentVariable, socketPath, 1)

        ipcEventSource = loop.addFd(fd) { [weak self] in self?.ipcHandleConnection() }
    }

    // not in mango: whether a mango answers on the socket
    nonisolated static func isLive(_ addr: sockaddr_un) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var a = addr
        let r = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return r == 0
    }
}

// not in mango: cJSON, the library mango prints its replies with
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
        // cJSON's compare_double: equal within DBL_EPSILON of the larger
        if let t = Double(s15), abs(t - d) <= max(abs(t), abs(d)) * Double.ulpOfOne { return s15 }
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
