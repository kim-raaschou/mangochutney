import Foundation
import Mango

public enum Spawn {
    /// mango `spawn`: fork + setsid + wordexp + execvp. We run through the
    /// login shell so `~`, `$VAR` and quoting behave like wordexp.
    public static func run(_ command: String, env: [String: String] = [:]) {
        shell(command, env: env)
    }

    /// mango `spawn_shell`: sh -c.
    public static func shell(_ command: String, env: [String: String] = [:]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", command]
        var e = ProcessInfo.processInfo.environment
        for (k, v) in env { e[k] = v }
        p.environment = e
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { Log.error("spawn failed: \(command): \(error)") }
    }
}
