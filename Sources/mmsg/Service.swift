// `mmsg service ...`, `mmsg logs`: manage mango as a per-user LaunchAgent.
import Foundation
import Darwin

enum Service {
    static let label = "dev.mangochutney"
    /// The agent's label before the app was named Mango Chutney: install takes it away.
    static let oldLabel = "dev.mango.wm"
    static let defaultExecutable = "/Applications/Mango Chutney.app/Contents/MacOS/mango"
    /// The `mango` next to this `mmsg` when both live in an app bundle (an installed or `dist/`
    /// Mango Chutney.app, also behind the ~/.local/bin symlink), else the standard install location.
    static var executable: String {
        if let me = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let sibling = me.deletingLastPathComponent().appendingPathComponent("mango").path
            if sibling.contains(".app/Contents/MacOS/"), FileManager.default.isExecutableFile(atPath: sibling) {
                return sibling
            }
        }
        return defaultExecutable
    }
    static var user: String { NSUserName() }
    static var outLogPath: String { "/tmp/mango_\(user).out.log" }
    static var errLogPath: String { "/tmp/mango_\(user).err.log" }
    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }
    static var domain: String { "gui/\(getuid())" }
    static var serviceTarget: String { "\(domain)/\(label)" }

    static let usage = "usage: mmsg service install|uninstall|start|stop|restart|status|plist"

    static func run(_ args: [String]) -> Int32 {
        guard args.count == 1 else { return err(usage) }
        switch args[0] {
        case "install": return install()
        case "uninstall": return uninstall()
        case "start": return start()
        case "stop": return stop()
        case "restart": return restart()
        case "status": return status()
        case "plist": return printPlist()
        default: return err(usage)
        }
    }

    // MARK: Commands

    static func plist() -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            // Restart only after a crash. A second instance exits with status 1 ("already
            // running"), which `SuccessfulExit: false` would respawn every 10 seconds forever
            // (for example `open -a "Mango Chutney"` followed by `mmsg service install`).
            "KeepAlive": ["Crashed": true],
            // Windows started through `spawn` must survive `service stop/restart`.
            "AbandonProcessGroup": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": outLogPath,
            "StandardErrorPath": errLogPath,
        ]
    }

    static func install() -> Int32 {
        if !FileManager.default.isExecutableFile(atPath: executable) {
            warn("warning: \(executable) not found; the agent will fail until Mango Chutney.app is installed")
        }
        // The agent from before the rename goes, or two would start mango.
        let old = NSHomeDirectory() + "/Library/LaunchAgents/\(oldLabel).plist"
        _ = launchctl(["bootout", "\(domain)/\(oldLabel)"], quiet: true)
        if FileManager.default.fileExists(atPath: old) { try? FileManager.default.removeItem(atPath: old) }
        let url = URL(fileURLWithPath: plistPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist(), format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        } catch {
            return err("mmsg: cannot write \(plistPath): \(error.localizedDescription)")
        }
        print("wrote \(plistPath)")
        // Reload so an edited plist takes effect. bootout returns before the job is fully gone,
        // and bootstrapping too early fails with "Input/output error", so wait for it.
        if isLoaded() {
            _ = launchctl(["bootout", serviceTarget], quiet: true)
            waitUntilUnloaded()
        }
        var rc = launchctl(["bootstrap", domain, plistPath], quiet: true)
        if rc != 0 {
            usleep(1_000_000)
            rc = launchctl(["bootstrap", domain, plistPath])
        }
        if rc == 0 { print("loaded \(label) into \(domain)") }
        return rc
    }

    static func uninstall() -> Int32 {
        if isLoaded() {
            let rc = launchctl(["bootout", serviceTarget])
            if rc != 0 { return rc }
            print("unloaded \(label)")
        }
        if FileManager.default.fileExists(atPath: plistPath) {
            do { try FileManager.default.removeItem(atPath: plistPath) } catch {
                return err("mmsg: cannot remove \(plistPath): \(error.localizedDescription)")
            }
            print("removed \(plistPath)")
        }
        return 0
    }

    static func start() -> Int32 {
        guard requireInstalled() else { return 1 }
        if isLoaded() {
            return launchctl(["kickstart", serviceTarget])
        }
        return launchctl(["bootstrap", domain, plistPath])
    }

    static func stop() -> Int32 {
        // With KeepAlive {SuccessfulExit=false} a plain kill would be restarted;
        // unloading the job is the only reliable stop.
        guard isLoaded() else {
            print("\(label) is not running")
            return 0
        }
        return launchctl(["bootout", serviceTarget])
    }

    static func restart() -> Int32 {
        guard requireInstalled() else { return 1 }
        guard isLoaded() else { return launchctl(["bootstrap", domain, plistPath]) }
        if servicePID() == nil, capture("/usr/bin/pgrep", ["-x", "mango"]).0 == 0 {
            return err("mmsg: mango is running, but not as the service; quit it first (mmsg dispatch quit)")
        }
        // Ask mango to quit for a restart (hidden windows stay hidden, the next mango
        // restores them from the saved layout), wait for it to exit, start it again.
        // A clean exit is not restarted by KeepAlive {SuccessfulExit=false}.
        if let pid = servicePID(), FileManager.default.fileExists(atPath: socketPath()),
           runIPC("dispatch chutney_restart", sink: { _ in }, replyTimeout: 3) == 0, waitForExit(pid) {
            return launchctl(["kickstart", serviceTarget])
        }
        return launchctl(["kickstart", "-k", serviceTarget])
    }

    /// The running job's pid, from `launchctl print`.
    static func servicePID() -> pid_t? {
        let (status, out) = capture("/bin/launchctl", ["print", serviceTarget])
        guard status == 0 else { return nil }
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("pid = "), let pid = pid_t(t.dropFirst(6)) { return pid }
        }
        return nil
    }

    /// Waits (at most 10 s) for `pid` to exit; true when it did. A process-exit event
    /// from the kernel, not a poll.
    static func waitForExit(_ pid: pid_t) -> Bool {
        let done = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global())
        source.setEventHandler { done.signal() }
        source.resume()
        defer { source.cancel() }
        if kill(pid, 0) != 0 { return true }   // already gone
        return done.wait(timeout: .now() + 10) == .success
    }

    /// `mmsg service plist`: print the LaunchAgent plist that `install` would write.
    static func printPlist() -> Int32 {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist(), format: .xml, options: 0) else {
            return err("mmsg: cannot encode the plist")
        }
        FileHandle.standardOutput.write(data)
        return 0
    }

    static func status() -> Int32 {
        let installed = FileManager.default.fileExists(atPath: plistPath)
        print("plist:   \(plistPath) (\(installed ? "installed" : "not installed"))")
        let (rc, output) = capture("/bin/launchctl", ["print", serviceTarget])
        if rc == 0 {
            var state = "loaded", pid: String?, lastExit: String?
            for raw in output.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("state = ") { state = String(line.dropFirst(8)) }
                else if line.hasPrefix("pid = ") { pid = String(line.dropFirst(6)) }
                else if line.hasPrefix("last exit code = ") { lastExit = String(line.dropFirst(17)) }
            }
            var desc = "service: \(serviceTarget) \(state)"
            if let pid { desc += ", pid \(pid)" }
            if let lastExit { desc += ", last exit code \(lastExit)" }
            print(desc)
        } else {
            print("service: \(serviceTarget) not loaded")
        }
        let sock = ProcessInfo.processInfo.environment["MANGO_INSTANCE_SIGNATURE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "/tmp/mango-\(user).sock"
        print("socket:  \(sock) (\(FileManager.default.fileExists(atPath: sock) ? "present" : "absent"))")
        print("logs:    \(outLogPath), \(errLogPath)")
        return rc == 0 ? 0 : 3
    }

    /// `mmsg logs`: follow both log files (replaces this process with tail).
    static func followLogs() -> Int32 {
        // -F keeps following across restarts/truncation and waits for missing files.
        let argv: [String] = ["tail", "-F", outLogPath, errLogPath]
        var cargs = argv.map { strdup($0) }
        cargs.append(nil)
        execv("/usr/bin/tail", cargs)
        perror("execv /usr/bin/tail")
        return 1
    }

    // MARK: Helpers

    static func isLoaded() -> Bool {
        capture("/bin/launchctl", ["print", serviceTarget]).0 == 0
    }

    /// Polls (up to ~10 s) until launchd no longer knows the job.
    static func waitUntilUnloaded() {
        var tries = 0
        while isLoaded() && tries < 100 {
            usleep(100_000)
            tries += 1
        }
    }

    static func requireInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: plistPath) { return true }
        warn("mmsg: \(plistPath) not found; run 'mmsg service install' first")
        return false
    }

    /// Runs launchctl with inherited stdout/stderr.
    @discardableResult
    static func launchctl(_ args: [String], quiet: Bool = false) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        if quiet {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        do { try p.run() } catch {
            warn("mmsg: cannot run launchctl: \(error.localizedDescription)")
            return 1
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 && !quiet {
            warn("mmsg: launchctl \(args.joined(separator: " ")) failed (\(p.terminationStatus))")
        }
        return p.terminationStatus
    }

    static func capture(_ tool: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func err(_ message: String) -> Int32 {
        warn(message)
        return 1
    }
}
