import AppKit
import Mango

public enum ConfigFiles {
    static let portMarker = "# not mango default: from here to the end, the macOS port's own keys"

    static func ensure(_ configURL: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return }
        try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let def = bundled("config") else { wlrLog(.info, "no default config in the app"); return }
        do {
            try fm.copyItem(at: def, to: configURL)
            wlrLog(.info, "wrote default config to \(configURL.path)")
        } catch {
            wlrLog(.info, "could not write the default config to \(configURL.path): \(error)")
        }
    }

    static func isFirstStart(_ configURL: URL) -> Bool {
        !FileManager.default.fileExists(atPath: configURL.path)
    }

    public static func open(_ url: URL) {
        let ws = NSWorkspace.shared
        if ws.urlForApplication(toOpen: url) != nil { ws.open(url); return }
        guard let textEdit = ws.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
        ws.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    static let hyperKeyLine = "chutney_hyper_key=caps_lock\r\n"

    static func setHyperKey(_ key: String, tap: String, configURL: URL) {
        guard let current = try? String(contentsOf: configURL, encoding: .utf8), current.contains(hyperKeyLine) else {
            wlrLog(.info, "keys: no \(hyperKeyLine.trimmingCharacters(in: .newlines)) line in \(configURL.path); the Hyper key is left as it is")
            return
        }
        let line = "chutney_hyper_key=\(key)\r\n" + (tap == "none" ? "" : "chutney_hyper_tap=\(tap)\r\n")
        do {
            try current.replacingOccurrences(of: hyperKeyLine, with: line).write(to: configURL, atomically: true, encoding: .utf8)
            wlrLog(.info, "keys: Hyper is \(key), pressed alone: \(tap), in \(configURL.path)")
        } catch {
            wlrLog(.info, "keys: could not write the config: \(error)")
        }
    }

    static func bundled(_ name: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: "conf") { return u }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/\(name).conf")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
