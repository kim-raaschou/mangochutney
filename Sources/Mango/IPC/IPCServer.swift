import Foundation
import Darwin

public struct IPCWatch: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case monitor, focusingClient, client, tags, allMonitors, allTags, allClients,
             allDevices, keymode, keyboardLayout, lastOpenSurface
    }
    public var kind: Kind
    public var monitorName: String?
    public var clientID: ClientID = 0

    public init(kind: Kind, monitorName: String? = nil, clientID: ClientID = 0) {
        self.kind = kind; self.monitorName = monitorName; self.clientID = clientID
    }

    // not in mango: handle_watch_command's parsing, apart
    public static func parse(_ cmd: String) -> IPCWatch? {
        if cmd.hasPrefix("watch monitor ") {
            return IPCWatch(kind: .monitor, monitorName: String(cmd.dropFirst(14)))
        } else if cmd == "watch focusing-client" {
            return IPCWatch(kind: .focusingClient)
        } else if cmd.hasPrefix("watch client ") {
            return IPCWatch(kind: .client, clientID: IPCRequest.clientID(atoi: cmd.dropFirst(13)))
        } else if cmd.hasPrefix("watch tags ") {
            return IPCWatch(kind: .tags, monitorName: String(cmd.dropFirst(11)))
        } else if cmd == "watch all-monitors" {
            return IPCWatch(kind: .allMonitors)
        } else if cmd == "watch all-tags" {
            return IPCWatch(kind: .allTags)
        } else if cmd == "watch all-clients" {
            return IPCWatch(kind: .allClients)
        } else if cmd == "watch all-devices" {
            return IPCWatch(kind: .allDevices)
        } else if cmd == "watch keymode" {
            return IPCWatch(kind: .keymode)
        } else if cmd == "watch keyboardlayout" {
            return IPCWatch(kind: .keyboardLayout)
        } else if cmd == "watch last_open_surface" {
            return IPCWatch(kind: .lastOpenSurface, monitorName: nil)
        } else if cmd.hasPrefix("watch last_open_surface ") {
            let arg = String(cmd.dropFirst(24))
            return IPCWatch(kind: .lastOpenSurface, monitorName: arg.isEmpty ? nil : arg)
        }
        return nil
    }
}

public enum IPCRequest: Equatable, Sendable {
    case get(String)
    case dispatch(Dispatch, target: ClientID?)
    case watch(IPCWatch)
    case unknown

    // not in mango: the line parsed into a request, apart from ipc_handle_client_data
    public static func parse(_ rawLine: String) -> IPCRequest {
        var raw = rawLine
        if raw.hasSuffix("\n") { raw.removeLast() }
        if raw.hasSuffix("\r") { raw.removeLast() }

        if let w = IPCWatch.parse(raw) { return .watch(w) }
        let cmd = String(raw.map { $0 == "," ? " " : $0 })
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

    static let commandTakingDispatchers: Set<String> = [
        "spawn", "spawn_shell", "spawn_on_empty", "toggle_named_scratchpad",
    ]

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
                var overflow = false
                while j < bytes.count && bytes[j] >= 48 && bytes[j] <= 57 {
                    let (m, o1) = id.multipliedReportingOverflow(by: 10)
                    let (a, o2) = m.addingReportingOverflow(Int(bytes[j] - 48))
                    if o1 || o2 { overflow = true } else { id = a }
                    j += 1
                }
                if j > digitsStart && !negative && !overflow && id > 0
                    && (j == bytes.count || bytes[j] == comma || bytes[j] == space || bytes[j] == tab) {
                    clientID = id
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
        switch name {
        case "spawn", "spawn_shell":
            var parts: [String] = []
            while parts.count < 4, let t = nextToken() { parts.append(t) }
            if parts.count == 4, let r = remainderArg() { parts.append(r) }
            let cmd = parts.prefix { $0 != "0" }
            if !cmd.isEmpty { args = [cmd.joined(separator: ",")] }
        case "spawn_on_empty":
            if let r = remainderArg() {
                if let c = r.lastIndex(of: ",") {
                    let cmd = trimmed(r[..<c]), tag = trimmed(r[r.index(after: c)...])
                    args = tag.isEmpty ? [cmd] : [cmd, tag]
                } else {
                    args = [r]
                }
            }
        case "toggle_named_scratchpad":
            for _ in 0..<2 {
                guard let t = nextToken() else { break }
                args.append(t)
            }
            if args.count == 2, let cmd = remainderArg() { args.append(cmd) }
        default:
            while args.count < 4, let t = nextToken() { args.append(t) }
            if args.count == 4, let r = remainderArg() { args.append(r) }
        }
        let target: ClientID? = (clientID > 0 && clientID <= Int(ClientID.max)) ? ClientID(clientID) : nil
        return (Dispatch(name: name, args: args), target)
    }
}

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

@MainActor
public final class IPCServer {
    public static let environmentVariable = "MANGO_INSTANCE_SIGNATURE"

    // not in mango: /tmp/mango-<user>.sock, where mmsg looks; macOS has no XDG_RUNTIME_DIR
    nonisolated public static func defaultSocketPath() -> String {
        "/tmp/mango-\(NSUserName()).sock"
    }

    final class IPCClientState {
        let fd: Int32
        var buf: [UInt8] = []
        var source: EventSource?
        init(fd: Int32) { self.fd = fd }
    }

    final class IPCWatchClient {
        let fd: Int32
        let watch: IPCWatch
        var source: EventSource?
        // not in mango: the last line sent, so an unchanged one is not sent again
        var lastPayload: String?
        init(fd: Int32, watch: IPCWatch) { self.fd = fd; self.watch = watch }
    }

    public let socketPath: String
    public let version: String
    private weak var server: MangoServer?
    // not in mango: the event loop (wl_event_loop), the port's
    private let loop: EventLoop
    private var ipcSocketFd: Int32 = -1
    private var ipcEventSource: EventSource?
    private var ipcWatchClients: [IPCWatchClient] = []
    private var notifyScheduled = false

    public init(server: MangoServer, loop: EventLoop, socketPath: String = IPCServer.defaultSocketPath(),
                version: String) {
        self.server = server
        self.loop = loop
        self.socketPath = socketPath
        self.version = version
    }

    public var isRunning: Bool { ipcSocketFd >= 0 }

    public var watcherCount: Int { ipcWatchClients.count }

    public func ipcInit() throws {
        if ipcSocketFd >= 0 { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw IPCServerError.socketPathTooLong(socketPath) }
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
            Log.error("failed to set FD_CLOEXEC on IPC socket")
            Darwin.close(fd)
            throw IPCServerError.socketFailed(errno)
        }
        flags = fcntl(fd, F_GETFL, 0)
        if flags == -1 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1 {
            Log.error("failed to set O_NONBLOCK on IPC socket")
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

    public func ipcCleanup() {
        ipcEventSource?.remove()
        ipcEventSource = nil
        if ipcSocketFd >= 0 { Darwin.close(ipcSocketFd) }
        ipcSocketFd = -1
        unlink(socketPath)
        if let current = getenv(IPCServer.environmentVariable), String(cString: current) == socketPath {
            unsetenv(IPCServer.environmentVariable)
        }
        for wc in ipcWatchClients { ipcRemoveWatchClient(wc) }
    }

    func ipcHandleConnection() {
        let clientFd = accept(ipcSocketFd, nil, nil)
        if clientFd < 0 { return }
        var flags = fcntl(clientFd, F_GETFL, 0)
        if flags == -1 || fcntl(clientFd, F_SETFL, flags | O_NONBLOCK) == -1 {
            Log.error("failed to set O_NONBLOCK on IPC client socket")
            Darwin.close(clientFd)
            return
        }
        flags = fcntl(clientFd, F_GETFD, 0)
        if flags == -1 || fcntl(clientFd, F_SETFD, flags | FD_CLOEXEC) == -1 {
            Log.error("failed to set FD_CLOEXEC on IPC client socket")
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

    func ipcHandleClientData(_ client: IPCClientState) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = recv(client.fd, &chunk, chunk.count, 0)
        if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { return }
        if n <= 0 { cleanup(); return }
        client.buf.append(contentsOf: chunk[0..<n])
        guard let nl = client.buf.firstIndex(of: 10) else {
            if client.buf.count > 1024 * 1024 { cleanup() }
            return
        }
        let cmd = String(decoding: client.buf[..<nl], as: UTF8.self)

        if handleWatchCommand(client.fd, cmd, client) { return }

        handleCommand(client.fd, cmd)
        cleanup()

        func cleanup() {
            Darwin.close(client.fd)
            client.source?.remove()
            client.source = nil
        }
    }

    func handleWatchCommand(_ fd: Int32, _ cmd: String, _ client: IPCClientState) -> Bool {
        guard case .watch(let watch) = IPCRequest.parse(cmd) else { return false }
        let wc = IPCWatchClient(fd: fd, watch: watch)
        client.source?.remove()
        client.source = nil
        wc.source = loop.addFd(fd) { [weak self, wc] in self?.ipcWatchDataHandler(wc) }
        ipcWatchClients.append(wc)
        // not in mango: the watcher's first line at once, from the snapshot
        if let line = server?.watchPayload(watch)?.serialized {
            wc.lastPayload = line
            ipcNotifyJsonToFd(wc, line)
        }
        return true
    }

    func ipcWatchDataHandler(_ wc: IPCWatchClient) {
        var buf = [UInt8](repeating: 0, count: 64)
        let n = recv(wc.fd, &buf, buf.count, 0)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
            ipcRemoveWatchClient(wc)
        }
    }

    func ipcRemoveWatchClient(_ wc: IPCWatchClient) {
        ipcWatchClients.removeAll { $0 === wc }
        wc.source?.remove()
        wc.source = nil
        Darwin.close(wc.fd)
    }

    func sendStaticJson(_ fd: Int32, _ json: String) {
        let data = Array((json + "\n").utf8)
        _ = data.withUnsafeBufferPointer { send(fd, $0.baseAddress, $0.count, 0) }
    }

    func ipcNotifyJsonToFd(_ wc: IPCWatchClient, _ json: String) {
        let data = Array((json + "\n").utf8)
        let n = data.withUnsafeBufferPointer { send(wc.fd, $0.baseAddress, $0.count, 0) }
        if n < 0 { ipcRemoveWatchClient(wc) }
    }

    // not in mango: printstatus's part for the watchers, run after the events waiting (handle_print_status)
    public func notifyChanged() {
        guard isRunning, !notifyScheduled, !ipcWatchClients.isEmpty else { return }
        notifyScheduled = true
        Task { @MainActor [weak self] in self?.handlePrintStatus() }
    }

    private func handlePrintStatus() {
        notifyScheduled = false
        guard isRunning, !ipcWatchClients.isEmpty, let server else { return }
        for wc in ipcWatchClients {
            guard let line = server.watchPayload(wc.watch)?.serialized, line != wc.lastPayload else { continue }
            wc.lastPayload = line
            ipcNotifyJsonToFd(wc, line)
        }
    }

    func handleCommand(_ fd: Int32, _ cmd: String) {
        guard let server else {
            sendStaticJson(fd, IPCJSON.error("compositor unavailable").serialized)
            return
        }
        switch IPCRequest.parse(cmd) {
        case .get(let get):
            sendStaticJson(fd, reply(get, server).serialized)
        case .dispatch(let dispatch, let target):
            var json = IPCJSON.success
            var c: Client?
            if let target {
                // mango: a client's id; a parked group member only for focusid
                c = server.clientById(target) ?? (dispatch.name == "focusid" ? server.clientByIdAll(target) : nil)
            }
            if target != nil && c == nil {
                json = IPCJSON.noClientFound
            } else if !Dispatch.isKnown(dispatch.name) {
                json = IPCJSON.unknownFunction
            } else if let problem = server.dispatch(dispatch, target: c) {
                Log.debug("dispatch \(dispatch.name): \(problem)")
            }
            sendStaticJson(fd, json.serialized)
        case .watch, .unknown:
            sendStaticJson(fd, IPCJSON.unknownCommand.serialized)
        }

        func reply(_ cmd: String, _ server: MangoServer) -> JSONValue {
            if cmd == "get version" {
                return .object([("version", .string(version))])
            } else if cmd == "get cursorpos" {
                let p = server.system.pointer
                return .object([("x", .double(Double(p.x))), ("y", .double(Double(p.y))),
                                ("monitor", server.monitorAtPoint(p).map { .string($0.screen.name) } ?? .null)])
            } else if cmd == "get keymode" {
                return .object([("keymode", .string(server.keyMode))])
            } else if cmd == "get keyboardlayout" {
                return .object([("layout", .string(server.system.keyboardLayout))])
            } else if cmd == "get last_open_surface" || cmd.hasPrefix("get last_open_surface ") {
                let m = cmd == "get last_open_surface" ? server.selectedMonitor : server.monitorByName(String(cmd.dropFirst(22)))
                guard let m else { return IPCJSON.monitorNotFound }
                return .object([("monitor", .string(m.screen.name)), ("last_open_surface", .string(""))]) // not in mango: no layer shell on macOS
            } else if cmd.hasPrefix("get monitor ") {
                guard let m = server.monitorByName(String(cmd.dropFirst(12))) else { return IPCJSON.monitorNotFound }
                return server.buildMonitorJson(m)
            } else if cmd == "get focusing-client" {
                guard let c = server.ipcFocusingClient() else { return IPCJSON.noFocusedClient }
                return server.buildClientJson(c)
            } else if cmd.hasPrefix("get client ") {
                let id = IPCRequest.clientID(atoi: cmd.dropFirst(11))
                guard let c = server.clientByIdAll(id) else { return IPCJSON.clientNotFound }
                return server.buildClientJson(c)
            } else if cmd.hasPrefix("get tag ") {
// not in mango: macOS display names have spaces, so the last field is the tag.
                let rest = Substring(cmd.dropFirst(8))
                let ws = CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}")
                let trimmedRest = rest.trimmingCharacters(in: ws)
                guard let split = trimmedRest.unicodeScalars.lastIndex(where: { ws.contains($0) }) else {
                    return IPCJSON.error("usage: get tag <monitor> <index>")
                }
                let monName = String(trimmedRest.unicodeScalars[..<split]).trimmingCharacters(in: ws)
                let indexText = Substring(String(trimmedRest.unicodeScalars[trimmedRest.unicodeScalars.index(after: split)...]))
                var digits = indexText
                if let f = digits.first, f == "+" || f == "-" { digits = digits.dropFirst() }
                guard !monName.isEmpty, let f = digits.first, f.isASCII, f.isNumber else {
                    return IPCJSON.error("usage: get tag <monitor> <index>")
                }
                let index = IPCRequest.cAtoi(indexText)
                guard let m = server.monitorByName(monName), index >= 1, index <= server.config.tagNum else {
                    return IPCJSON.error("invalid monitor or tag index")
                }
                let bit: UInt32 = 1 << UInt32(index - 1)
                let onTag = server.clients.filter { $0.mon === m && $0.tags & bit != 0 }
                let top = server.clientFocusTop(m)
                return .object([
                    ("monitor", .string(m.screen.name)),
                    ("tag_index", .int(index)),
                    ("is_active", .bool(server.getMonitorActiveTagset(m) & bit != 0)),
                    ("is_urgent", .bool(onTag.contains { $0.isUrgent })),
                    ("client_count", .int(onTag.count)),
                    ("focused_client", .bool(top.map { $0.mon === m && $0.tags & bit != 0 } ?? false)),
                ])
            } else if cmd == "get all-clients" {
                return .object([("clients", server.buildAllClientsArray())])
            } else if cmd == "get all-monitors" {
                return .object([("monitors", .array(server.monitors.map(server.buildMonitorJson)))])
            } else if cmd == "get all-devices" {
                return IPCJSON.allDevices
            } else if cmd == "get all-layers" {
                return IPCJSON.allLayers
            } else if cmd == "get all-tags" {
                return server.buildAllTagsResponse()
            } else if cmd.hasPrefix("get tags ") {
                guard let m = server.monitorByName(String(cmd.dropFirst(9))) else { return IPCJSON.monitorNotFound }
                return server.buildMonitorTagsResponse(m)
            } else if cmd == "get layouts" {
                return server.buildLayoutsResponse()
            } else if let get = server.portHooks.ipcGets[cmd] {
                return get(server)   // Port extension: not in mango (get binds)
            }
            return IPCJSON.unknownCommand
        }
    }
}
