import AppKit
import Mango

public enum ChutneyTheme {
    public static let fileName = "chutney_theme.conf"

    static let colors: [(key: String, color: NSColor, alpha: Double?)] = [
        ("focus_color", .controlAccentColor, nil),
        ("border_color", .systemGray, nil),
        ("root_color", .windowBackgroundColor, nil),
        ("urgent_color", .systemRed, nil),
        ("maximized_screen_color", .systemGreen, nil),
        ("scratchpad_color", .systemBlue, nil),
        ("global_color", .systemPurple, nil),
        ("overlay_color", .systemTeal, nil),
        ("drop_color", .controlAccentColor, Double(0x55) / 255),
        ("split_color", .controlAccentColor, nil),
    ]

    static let header = """
    # Written by Mango Chutney (chutney_macos_appearance), not for editing: mango's colours in macOS's,
    # written again when the accent colour or light/dark changes. Your own settings are in
    # config.conf; a colour of your own goes there, after its chutney_theme.conf line.
    """

    public static func url(configURL: URL) -> URL {
        configURL.deletingLastPathComponent().appendingPathComponent(fileName).standardizedFileURL
    }

    static func text(macOS: Bool, resolve: (NSColor) -> RGBA?) -> String {
        var lines = [header]
        if macOS {
            for (key, color, alpha) in colors {
                guard var c = resolve(color) else { continue }
                if let alpha { c.a = alpha }
                lines.append("\(key)=\(hex(c))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func hex(_ c: RGBA) -> String {
        func b(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "0x%02x%02x%02x%02x", b(c.r), b(c.g), b(c.b), b(c.a))
    }

    @discardableResult
    public static func sync(configURL: URL, style: Bool? = nil, resolve: (NSColor) -> RGBA? = rgba) -> Bool {
        let file = url(configURL: configURL)
        let macOS = style ?? ConfigParser.parseConfig(fileAt: configURL).config.chutneyMacOSAppearance
        let exists = FileManager.default.fileExists(atPath: file.path)
        guard macOS || exists else { return false }
        let text = text(macOS: macOS, resolve: resolve)
        guard (try? String(contentsOf: file, encoding: .utf8)) != text else { return false }
        do {
            try text.write(to: file, atomically: false, encoding: .utf8)
        } catch {
            mangoError(true, .info, "chutney_macos_appearance: could not write \(file.path): \(error)")
            return false
        }
        MenuSave.lastWritten[file.path] = text
        return true
    }

    public static func rgba(_ color: NSColor) -> RGBA? {
        let appearance = NSApp?.effectiveAppearance
        var out: RGBA?
        let read = {
            if let c = color.usingColorSpace(.sRGB) {
                out = RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
            }
        }
        if let appearance { appearance.performAsCurrentDrawingAppearance(read) } else { read() }
        return out
    }
}

extension MangoServer {
    func observeMacOSTheme() {
        let changed: () -> Void = { [weak self] in
            guard let self, ChutneyTheme.sync(configURL: self.configURL) else { return }
            mangoError(true, .info, "chutney_macos_appearance: \(ChutneyTheme.fileName) written for the new accent colour or light/dark")
            self.reloadConfig()
        }
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { changed() }
        }
        ChutneyTheme.appearanceObservation = NSApp?.observe(\.effectiveAppearance) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { changed() } }
        }
    }
}

extension ChutneyTheme {
    nonisolated(unsafe) static var appearanceObservation: NSKeyValueObservation?
}
