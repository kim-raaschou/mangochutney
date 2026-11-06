// Port extension: not in mango. mmsg's macOS extras (service, logs, reload, binds) and their
// lines in its usage; mmsg (Sources/Mango/mmsg) is mango's mmsg.c and calls these two.
import Darwin
import Foundation

public func mmsgPortUsage() {
    print("""
    macOS extras:
      reload                                   Reload the config (dispatch reload_config)
      binds [mode]                             List the active shortcuts in readable form
      get binds                                The same as JSON
      logs                                     Follow mango's stdout/stderr logs
                                               (\(Service.outLogPath), \(Service.errLogPath))
      service install                          Install and load the LaunchAgent (\(Service.label))
      service uninstall                        Unload and remove the LaunchAgent
      service start|stop|restart               Start, stop or restart mango via launchctl
      service status                           Show LaunchAgent and IPC socket status
      Without MANGO_INSTANCE_SIGNATURE the socket defaults to /tmp/mango-<user>.sock.

    """)
}

/// The port's command's exit status, or nil when the command is mango's.
public func mmsgPortCommand(_ args: [String]) -> Int32? {
    switch args.first {
    case "service": return Service.run(Array(args.dropFirst()))
    case "logs" where args.count == 1: return Service.followLogs()
    case "reload" where args.count == 1: return runIPC("dispatch reload_config")
    case "binds" where args.count <= 2: return printBinds(mode: args.count == 2 ? args[1] : nil)
    default: return nil
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
    exit(EXIT_FAILURE)
}

func socketPath() -> String {
    if let env = ProcessInfo.processInfo.environment["MANGO_INSTANCE_SIGNATURE"], !env.isEmpty {
        return env
    }
    return "/tmp/mango-\(NSUserName()).sock"
}

/// Connects, sends `command` + "\n" and copies everything received to stdout
/// until EOF. Returns the process exit status.
/// `replyTimeout`: give up on a mango that does not answer (seconds); with it, failures
/// return EXIT_FAILURE instead of exiting, so the caller can fall back.
func runIPC(_ command: String, sink: ((ArraySlice<UInt8>) -> Void)? = nil, replyTimeout: Int? = nil) -> Int32 {
    let path = socketPath()
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8CString)
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
        fail("mmsg: socket path too long: \(path)")
    }
    withUnsafeMutableBytes(of: &addr.sun_path) { dst in
        for (i, b) in pathBytes.enumerated() { dst[i] = UInt8(bitPattern: b) }
    }
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    if sock < 0 { perror("socket"); return EXIT_FAILURE }
    var one: Int32 = 1
    _ = setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    if let replyTimeout {
        var tv = timeval(tv_sec: replyTimeout, tv_usec: 0)
        _ = setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    let connected = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    if connected != 0 {
        let err = errno
        close(sock)
        if replyTimeout != nil { return EXIT_FAILURE }
        switch err {
        case ENOENT:
            fail("mango is not running (no socket at \(path))")
        case ECONNREFUSED:
            fail("mango is not running (stale socket \(path))")
        default:
            fail("cannot connect to mango at \(path): \(String(cString: strerror(err)))")
        }
    }

    let payload = Array((command + "\n").utf8)
    var offset = 0
    while offset < payload.count {
        let n = payload[offset...].withUnsafeBufferPointer { send(sock, $0.baseAddress, $0.count, 0) }
        if n < 0 {
            if errno == EINTR { continue }
            perror("send"); close(sock); return EXIT_FAILURE
        }
        offset += n
    }

    // Copy lines to stdout as they arrive (flushing per line, like mmsg.c).
    var pendingLine: [UInt8] = []
    var buf = [UInt8](repeating: 0, count: 65536)
    func writeOut(_ bytes: ArraySlice<UInt8>) {
        if let sink { sink(bytes); return }
        bytes.withUnsafeBufferPointer { p in
            var off = 0
            while off < p.count {
                let w = write(STDOUT_FILENO, p.baseAddress! + off, p.count - off)
                if w < 0 { if errno == EINTR { continue }; exit(EXIT_FAILURE) }
                off += w
            }
        }
    }
    while true {
        let n = recv(sock, &buf, buf.count, 0)
        if n == 0 { break }
        if n < 0 {
            if errno == EINTR { continue }
            perror("recv"); close(sock); return EXIT_FAILURE
        }
        pendingLine.append(contentsOf: buf[0..<n])
        if let lastNL = pendingLine.lastIndex(of: 10) {
            writeOut(pendingLine[...lastNL])
            pendingLine.removeSubrange(...lastNL)
        }
    }
    if !pendingLine.isEmpty { writeOut(pendingLine[...]) }
    close(sock)
    return EXIT_SUCCESS
}

/// `mmsg binds [mode]`: readable table of the active bindings.
func printBinds(mode: String?) -> Int32 {
    var data = Data()
    let rc = runIPC("get binds") { data.append(contentsOf: $0) }
    guard rc == EXIT_SUCCESS else { return rc }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = obj["binds"] as? [[String: Any]] else {
        FileHandle.standardError.write(data)
        return EXIT_FAILURE
    }
    var modes: [String] = []
    var byMode: [String: [(String, String)]] = [:]
    for r in rows {
        let m = r["mode"] as? String ?? "default"
        if let mode, m != mode && m != "common" { continue }
        if byMode[m] == nil { modes.append(m) }
        byMode[m, default: []].append((r["keys"] as? String ?? "", r["action"] as? String ?? ""))
    }
    let width = rows.map { ($0["keys"] as? String ?? "").count }.max().map { min($0, 34) } ?? 20
    for (i, m) in modes.enumerated() {
        if i > 0 { print("") }
        print(m == "default" ? "Shortcuts" : "Mode \(m)")
        for (k, a) in byMode[m] ?? [] {
            print("  " + k.padding(toLength: max(width, k.count), withPad: " ", startingAt: 0) + "  " + a)
        }
    }
    return EXIT_SUCCESS
}
