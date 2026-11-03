import AppKit
import Mango

/// Not in mango: the port's default config. mango reads /etc/mango/config.conf when the
/// user has none; a Mac app has no /etc config, so the first start writes the shipped
/// config.conf: mango's own, then the port's keys from its marker line to the end
/// (docs/afvigelser.md), and start.conf beside it, the first lines to try (read by
/// config.conf with source_optional). The only files the app writes besides are its own,
/// read last (chutney_theme.conf, chutney_menu.conf).
public enum ConfigFiles {
    /// The line where the port's keys begin in the shipped config.conf.
    static let portMarker = "# Mango Chutney: the macOS port's own keys"

    /// Writes the default config on first run (no file at `configURL`).
    static func ensure(_ configURL: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return }
        try? fm.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let def = bundled("config") {
            try? fm.copyItem(at: def, to: configURL)
            Log.info("wrote default config to \(configURL.path)")
        }
        let start = startURL(configURL)
        if !fm.fileExists(atPath: start.path), let def = bundled("start") {
            try? fm.copyItem(at: def, to: start)
        }
    }

    /// The first lines to try, beside the config; the welcome window opens it.
    static func startURL(_ configURL: URL) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent("start.conf")
    }

    /// A first start: there is no config yet, so the permissions window offers the keys.
    static func isFirstStart(_ configURL: URL) -> Bool {
        !FileManager.default.fileExists(atPath: configURL.path)
    }

    /// The first start's "macOS" keys: the shipped config-mac.conf (mango's keys on Hyper,
    /// Caps Lock held; script/mac-config.swift) in place of the default config, and only
    /// while that is as the first start wrote it; mango reloads when it is saved.
    static func useMacKeys(configURL: URL) {
        ensure(configURL)
        func text(_ url: URL?) -> String? { url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
        guard text(configURL) == text(bundled("config")), let mac = text(bundled("config-mac")) else {
            Log.info("keys: the config is no longer the default; left as it is")
            return
        }
        do {
            try mac.write(to: configURL, atomically: true, encoding: .utf8)
            Log.info("keys: mango's keys on Hyper, in \(configURL.path)")
        } catch {
            Log.info("keys: could not write the config: \(error)")
        }
    }

    /// Opens a config file in its app, or in TextEdit when no app opens .conf files.
    public static func open(_ url: URL) {
        let ws = NSWorkspace.shared
        if ws.urlForApplication(toOpen: url) != nil { ws.open(url); return }
        guard let textEdit = ws.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") else { return }
        ws.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    /// A bundled default config file (`config.conf`, `config-mac.conf`, `start.conf`).
    static func bundled(_ name: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: "conf") { return u }
        // Development: Resources/<name>.conf next to the package.
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
