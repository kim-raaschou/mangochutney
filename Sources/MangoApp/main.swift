import AppKit
import SwiftUI
import Mango
import Port

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var server: MangoServer?
    var statusItem: NSStatusItem?
    var menuOpen = false
    var tagSpans: [(from: CGFloat, to: CGFloat, monitor: String, tag: Int)] = []
    var mainMenu: NSMenu?
    var overlapItems: [NSMenuItem] = []
    var shownSuggestions: [MenuBarSuggestion] = []
    let layoutPanel = LayoutPanelModel()
    var shownStatus = ""
    var permissionObservers: [(NotificationCenter, NSObjectProtocol)] = []
    let configPath: URL?

    init(configPath: URL?) {
        self.configPath = configPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Permissions.shared.restart = { [weak self] in self?.restart() }
        Permissions.shared.quit = { [weak self] in self?.quit() }
        Permissions.shared.installLoginService = { [weak self] in self?.service("install") }
        Permissions.shared.firstStartDone = { [weak self] in self?.startIfTrusted() }
        Permissions.shared.currentChoices = { [weak self] in
            let login = FileManager.default.fileExists(atPath: Self.loginPlist)
            guard let server = self?.server else {
                return .init(hyperKey: nil, hyperTap: "none", startAtLogin: login, canSave: false,
                             configURL: self?.configPath ?? ConfigParser.defaultConfigURL())
            }
            let key = server.config.chutneyHyperKey
            let menu = MenuSave.url(server.config, configURL: server.configURL)
            return .init(hyperKey: key.isEmpty ? nil : key, hyperTap: server.config.chutneyHyperTap, startAtLogin: login,
                         canSave: menu != nil, configURL: server.configURL, menuFile: menu,
                         overrides: menu.map { MenuSave.conflicts(configURL: server.configURL, menuURL: $0).count } ?? 0)
        }
        Permissions.shared.saveChoice = { [weak self] key, value in self?.saveMenuChoice(key, value) }
        Permissions.shared.setStartAtLogin = { [weak self] on in self?.setLogin(on) }
        Permissions.shared.lookView = { [weak self] in
            guard let self, self.server != nil else { return nil }
            self.layoutPanel.server = self.server
            self.layoutPanel.refresh()
            return AnyView(LookView(model: self.layoutPanel))
        }
        Permissions.shared.prepareFirstStart(configPath ?? ConfigParser.defaultConfigURL())
        Permissions.shared.showIfNeeded()
        if AX.isTrusted {
            startWM()
        } else {
            setStatus("Mango Chutney: needs Accessibility")
            wlrLog(.info, "waiting for Accessibility permission (System Settings › Privacy & Security › Accessibility)")
            let check: (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.startIfTrusted() }
            }
            let dnc = DistributedNotificationCenter.default()
            let ws = NSWorkspace.shared.notificationCenter
            permissionObservers = [
                (dnc, dnc.addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil,
                                      queue: .main, using: check)),
                (ws, ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                    queue: .main, using: check)),
            ]
        }
    }

    func startIfTrusted() {
        Permissions.shared.refresh()
        guard server == nil, AX.isTrusted else { return }
        for (center, token) in permissionObservers { center.removeObserver(token) }
        permissionObservers = []
        wlrLog(.info, "Accessibility granted")
        startWM()
    }

    func startWM() {
        guard !Permissions.shared.firstStartPending else {
            setStatus("Mango Chutney: choose your Hyper key")
            return
        }
        let server = MangoServer(configURL: configPath)
        server.useMacSystem()
        server.cliDebugLog = cliDebugLog
        self.server = server
        server.onStateChange = { [weak self] in MainActor.assumeIsolated { self?.refreshStatus() } }
        server.setup()
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.cleanup()
    }

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            if let logo = Self.logo(mono: false) {
                b.image = logo
                b.imagePosition = .imageLeft
                b.imageHugsTitle = true
            }
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeLayoutPanelItem(model: layoutPanel))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload Config", action: #selector(reload), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Restart Mango Chutney", action: #selector(restart), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Mango Chutney", action: #selector(quit), keyEquivalent: "q")
        for i in menu.items where i.submenu == nil { i.target = self }
        menu.addItem(.separator())
        let version = menu.addItem(withTitle: "Mango Chutney \(mangoVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        mainMenu = menu
        statusItem = item
        for name in [NSWindow.didMoveNotification, NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                MainActor.assumeIsolated {
                    guard let self, n.name != NSWindow.didMoveNotification || n.object as? NSWindow === self.statusItem?.button?.window
                    else { return }
                    self.publishTagHits()
                }
            }
        }
        setStatus("mango")
    }

    static func logo(mono: Bool) -> NSImage? {
        var url = Bundle.main.url(forResource: "mango", withExtension: "svg")
        if url == nil {
            var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<6 {
                let c = dir.appendingPathComponent("Resources/mango.svg")
                if FileManager.default.fileExists(atPath: c.path) { url = c; break }
                dir = dir.deletingLastPathComponent()
            }
        }
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 16, height: 16)
        guard mono else { return img }
        let shape = NSImage(size: img.size, flipped: false) { rect in
            img.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        shape.accessibilityDescription = "mango"
        return shape
    }

    func setStatus(_ s: String) {
        shownStatus = ""
        if statusItem?.button?.title != s { statusItem?.button?.title = s }
    }

    func setStatus(monitors: [MenuBarMonitor], showLayout: Bool, mode: String, style: String, logo: String) {
        let key = "\(monitors)|\(showLayout)|\(mode)|\(style)|\(logo)"
        guard shownStatus != key, let b = statusItem?.button else { return }
        shownStatus = key
        tagSpans = []
        b.image = nil
        let font = b.font ?? .monospacedSystemFont(ofSize: 12, weight: .medium)
        let title = NSMutableAttributedString()
        let near: CGFloat = 3, apart: CGFloat = 7
        let middle = font.capHeight / 2
        func text(_ s: String, dim: Bool = false, overlap: Bool = false) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if dim { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            if overlap { attrs[.foregroundColor] = Self.overlapColor.withAlphaComponent(dim ? 0.6 : 1) }
            title.append(NSAttributedString(string: s, attributes: attrs))
        }
        func space(_ points: CGFloat) {
            guard title.length > 0 else { return }
            let a = NSTextAttachment()
            a.image = NSImage(size: NSSize(width: points, height: 1))
            a.bounds = CGRect(x: 0, y: 0, width: points, height: 1)
            title.append(NSAttributedString(attachment: a))
        }
        func image(_ img: NSImage, height: CGFloat? = nil) {
            let h = height ?? img.size.height
            let w = img.size.width * h / max(img.size.height, 1)
            let a = NSTextAttachment()
            a.image = img
            a.bounds = CGRect(x: 0, y: ((middle - h / 2) * 2).rounded() / 2, width: w, height: h)
            title.append(NSAttributedString(attachment: a))
        }
        let cell = Self.tagImage(MenuBarTag(number: 1, active: false), style: style)?.size.height ?? 16
        if logo != "off", let img = Self.logo(mono: logo == "mono") {
            image(img, height: cell)
            space(apart + 0.5)
        }
        for (n, m) in monitors.enumerated() {
            let dim = monitors.count > 1 && !m.selected
            if n > 0 {
                image(Self.separatorImage, height: 13)
                space(apart)
            }
            for (i, t) in m.tags.enumerated() {
                let start = title.size().width
                defer { tagSpans.append((start, title.size().width, m.name, t.number)) }
                if style == "text" {
                    let c = t.number == 0 ? "S" : "\(t.number)"
                    text(t.active ? "[\(c)]" : " \(c) ", dim: dim, overlap: t.overlap)
                } else if let img = Self.tagImage(t, style: style, dim: dim) {
                    image(img, height: cell)
                    if i < m.tags.count - 1 { space(near) }
                }
            }
            if showLayout {
                if style == "text" {
                    space(apart)
                    text(m.layout.symbol.padding(toLength: 2, withPad: " ", startingAt: 0), dim: dim)
                } else {
                    space(apart - 0.5)
                    image(Self.layoutImage(m.layout, dim: dim))
                }
            }
            space(apart)
        }
        if !mode.isEmpty {
            let active = mode != "default"
            if style != "text", let img = Self.modeImage(mode, style: style, active: active) {
                image(img, height: cell)
            } else {
                let c = active ? (mode.first.map(String.init) ?? "?") : "M"
                text(active ? "[\(c)]" : " \(c) ")
            }
        } else if title.length > 0 {
            title.deleteCharacters(in: NSRange(location: title.length - 1, length: 1))
        }
        b.attributedTitle = title
        publishTagHits()
    }

    static func tagImage(_ t: MenuBarTag, style: String, dim: Bool = false) -> NSImage? {
        let shape = style == "circle" ? "circle" : "square"
        let name = (t.number == 0 ? "star" : "\(t.number)") + ".\(shape)" + (t.active ? ".fill" : "")
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: "tag \(t.number)")?
            .withSymbolConfiguration(cfg) else { return nil }
        img.isTemplate = true
        if t.overlap { return tinted(img, overlapColor.withAlphaComponent(dim ? 0.6 : 1)) }
        return dim ? dimmed(img) : img
    }

    static let overlapColor = NSColor.systemOrange

    static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
        let img = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        img.accessibilityDescription = symbol.accessibilityDescription
        return img
    }

    static let separatorImage = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0.25, y: 0, width: 1.5, height: rect.height), xRadius: 0.75, yRadius: 0.75).fill()
        return true
    }

    static func dimmed(_ symbol: NSImage) -> NSImage {
        let img = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.secondaryLabelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        img.accessibilityDescription = symbol.accessibilityDescription
        return img
    }

    static func modeImage(_ mode: String, style: String, active: Bool) -> NSImage? {
        guard let c = (active ? mode.lowercased().first : "m"), c.isLetter, c.isASCII else { return nil }
        let shape = style == "circle" ? "circle" : "square"
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "\(c).\(shape)" + (active ? ".fill" : ""), accessibilityDescription: "\(mode) mode")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    static func layoutImage(_ kind: LayoutKind, dim: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 12)
        let frames = LayoutIcon.frames(kind, in: CGRect(origin: .zero, size: size))
        func half(_ v: CGFloat) -> CGFloat { (v * 2).rounded() / 2 }
        let img = NSImage(size: size, flipped: true) { _ in
            for (r, alpha) in frames {
                let x = half(r.minX + 0.5), y = half(r.minY + 0.5)
                let sharp = CGRect(x: x, y: y, width: half(r.maxX - 0.5) - x, height: half(r.maxY - 0.5) - y)
                guard sharp.width > 0, sharp.height > 0 else { continue }
                (dim ? NSColor.secondaryLabelColor : NSColor.labelColor).withAlphaComponent(max(alpha, 0.5)).setFill()
                NSBezierPath(roundedRect: sharp, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        img.accessibilityDescription = "layout \(kind.name)"
        return img
    }

    func refreshStatus() {
        guard let server else { return }
        let config = server.config
        if statusItem?.isVisible != config.chutneyMenuBar {
            statusItem?.isVisible = config.chutneyMenuBar
            publishTagHits()
        }
        let mode = config.chutneyMenuBarMode ? server.keyMode : (server.keyMode == "default" ? "" : server.keyMode)
        setStatus(monitors: MenuBarStatus.monitors(server), showLayout: config.chutneyMenuBarLayout, mode: mode,
                  style: config.chutneyMenuBarTagStyle, logo: config.chutneyMenuBarLogo)
    }

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if server == nil { startIfTrusted() }
        if let server, let e = NSApp.currentEvent, e.type == .leftMouseUp, let t = tag(under: sender) {
            MenuBarStatus.viewTag(server, monitor: t.monitor, tag: t.tag)
            return
        }
        showMenu(mainMenu)
    }

    func publishTagHits() {
        guard let server else { return }
        guard let item = statusItem, item.isVisible, !menuOpen, let b = item.button, let w = b.window,
              let primary = NSScreen.screens.first else { MenuBarStatus.publishTags(server, []); return }
        let r = w.convertToScreen(b.convert(b.bounds, to: nil))
        let left = r.minX + (r.width - b.attributedTitle.size().width) / 2
        let top = primary.frame.maxY - w.frame.maxY
        MenuBarStatus.publishTags(server, tagSpans.map {
            MenuBarTagHit(frame: CGRect(x: left + $0.from, y: top, width: $0.to - $0.from, height: w.frame.height),
                          monitor: $0.monitor, tag: $0.tag)
        })
    }

    func tag(under b: NSStatusBarButton) -> (monitor: String, tag: Int)? {
        guard let w = b.window else { return nil }
        let x = b.convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil).x
            - (b.bounds.width - b.attributedTitle.size().width) / 2
        return tagSpans.first { x >= $0.from && x < $0.to }.map { ($0.monitor, $0.tag) }
    }

    func showOverlaps(_ menu: NSMenu) {
        for i in overlapItems { menu.removeItem(i) }
        overlapItems = []
        shownSuggestions = []
        guard let server else { return }
        let lines = MenuBarStatus.overlapLines(server)
        guard !lines.isEmpty else { return }
        var at = 1
        func add(_ i: NSMenuItem) {
            menu.insertItem(i, at: at)
            overlapItems.append(i)
            at += 1
        }
        let font = NSFont.menuFont(ofSize: 0)
        let bold = NSFont.boldSystemFont(ofSize: font.pointSize)
        for tag in lines {
            let h = NSMenuItem(title: tag.heading, action: nil, keyEquivalent: "")
            h.isEnabled = false
            h.attributedTitle = NSAttributedString(string: tag.heading, attributes: [.font: bold, .foregroundColor: NSColor.labelColor])
            h.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "overlap")?
                .withSymbolConfiguration(.init(paletteColors: [Self.overlapColor]))
            add(h)
            for w in tag.windows {
                let i = NSMenuItem(title: "\(w.app): \(w.by)", action: nil, keyEquivalent: "")
                i.isEnabled = false
                let t = NSMutableAttributedString(string: w.app, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                t.append(NSAttributedString(string: "  \(w.by)", attributes: [.font: font, .foregroundColor: Self.overlapColor]))
                i.attributedTitle = t
                i.indentationLevel = 1
                add(i)
            }
            for s in tag.suggestions {
                let i = NSMenuItem(title: s.title, action: #selector(applySuggestion(_:)), keyEquivalent: "")
                i.target = self
                i.tag = shownSuggestions.count
                i.indentationLevel = 1
                i.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)
                shownSuggestions.append(s)
                add(i)
            }
        }
        let sep = NSMenuItem.separator()
        menu.insertItem(sep, at: 1)
        overlapItems.append(sep)
    }

    @objc func applySuggestion(_ sender: NSMenuItem) {
        guard let server, shownSuggestions.indices.contains(sender.tag) else { return }
        MenuBarStatus.apply(server, shownSuggestions[sender.tag])
    }

    func showMainMenu() { showMenu(mainMenu) }

    func showMenu(_ menu: NSMenu?) {
        guard let item = statusItem, let menu else { return }
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === mainMenu { showOverlaps(menu) }
        menuOpen = true
        publishTagHits()
        server?.holdNativeFocus = true
        layoutPanel.server = server
        layoutPanel.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === mainMenu || menu.supermenu == nil else { return }
        menuOpen = false
        publishTagHits()
        if menu === mainMenu { statusItem?.menu = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.server?.holdNativeFocus = false }
        }
    }

    @objc func reload() { server?.reloadConfig() }

    func saveMenuChoice(_ key: String, _ value: String) {
        guard let server, let url = MenuSave.url(server.config, configURL: server.configURL) else { return }
        let now = key == "chutney_hyper_key" ? server.config.chutneyHyperKey : server.config.chutneyHyperTap
        guard value != now, !(value == "none" && now.isEmpty) else { return }
        MenuSave.set(key, value, in: url)
        server.reloadConfig()
    }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func showSettings() { Permissions.shared.showSettings() }

    static var loginPlist: String { NSHomeDirectory() + "/Library/LaunchAgents/dev.mangochutney.plist" }

    func setLogin(_ on: Bool) {
        let installed = FileManager.default.fileExists(atPath: Self.loginPlist)
        guard on != installed else { return }
        if installed, ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == "dev.mangochutney" {
            try? FileManager.default.removeItem(atPath: Self.loginPlist)
            return
        }
        service(installed ? "uninstall" : "install")
    }

    func service(_ verb: String) {
        let mmsg = Bundle.main.executableURL!.resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("mmsg").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: mmsg)
        p.arguments = ["service", verb]
        try? p.run()
    }

    @objc func restart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let app = path.hasSuffix(".app") ? "'\(path.replacingOccurrences(of: "'", with: ""))'" : "'Mango Chutney'"
        Spawn.shell("while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; "
                    + "launchctl kickstart gui/\(getuid())/dev.mangochutney 2>/dev/null || open -a \(app)")
        if let server { _ = server.dispatch(Dispatch(name: "chutney_restart")) } else { NSApp.terminate(nil) }
    }
}

nonisolated(unsafe) var _signalSources: [DispatchSourceSignal] = []

MacConfigPort.install()

var configPath: URL?
var check = false
var cliDebugLog = false
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "-c", "--config":
        if let p = args.next() { configPath = URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
    case "-p", "--check":
        check = true
    case "--list-ignored":
        print(MangoCompat.markdown(), terminator: "")
        exit(0)
    case "--list-glance":
        print(MangoCompat.glanceMarkdown(), terminator: "")
        exit(0)
    case "-v", "--version":
        print("mango \(mangoVersion)")
        exit(0)
    case "-d", "--debug":
        cliDebugLog = true
    case "-h", "--help":
        print("""
        Usage: mango [-c config] [-p] [--list-ignored] [--list-glance] [-d] [-v]
          -c, --config <path>   use this config file (default ~/.config/mango/config.conf, else config.toml)
          -p, --check           validate the config, list what has no effect on macOS, and exit
          --list-ignored        print the mango names that do nothing on macOS (Markdown)
          --list-glance         print how much of mango works on macOS (Markdown)
          -d, --debug           Enable debug log
          -v, --version         print version
        """)
        exit(0)
    default:
        break
    }
}

if check {
    let url = configPath ?? ConfigParser.defaultConfigURL()
    let parsed = ConfigParser.parseConfig(fileAt: url)
    for e in parsed.errors { print(e) }
    if let menu = MenuSave.url(parsed.config, configURL: url) {
        if !parsed.sourcedFiles.contains(where: { $0.standardizedFileURL == menu }) {
            print("warning: chutney_menu_config: \(menu.lastPathComponent) is saved to but not read; end the config with source_optional=\(menu.lastPathComponent)")
        }
        for c in MenuSave.conflicts(configURL: url, menuURL: menu) {
            print("warning: \(c.configFile):\(c.configLine) \(c.key) \(c.configValue) is overridden by \(menu.lastPathComponent) (\(c.menuValue))")
        }
    }
    if parsed.config.chutneyStyle {
        let theme = ChutneyTheme.url(configURL: url)
        if !parsed.sourcedFiles.contains(where: { $0.standardizedFileURL == theme }) {
            print("warning: chutney_style: \(theme.lastPathComponent) is written but not read; add source_optional=\(theme.lastPathComponent) before the menu's source_optional line")
        } else {
            let keys = MenuSave.conflicts(configURL: url, menuURL: theme).map(\.key)
            if !keys.isEmpty {
                print("note: chutney_style: \(theme.lastPathComponent) draws \(keys.count) colour(s) of \(url.lastPathComponent) in macOS's (\(keys.joined(separator: ", "))); to keep one, set it again after source_optional=\(theme.lastPathComponent)")
            }
        }
    }
    let sections: [(ConfigNote.Kind, String)] = [
        (.notYet, "Not implemented yet, macOS would allow it"),
        (.noEffect, "Cannot work on macOS"),
        (.unsupportedDispatcher, "Bindings that cannot work on macOS"),
        (.portExtension, "macOS port extensions (mango itself reports each as an unknown keyword)"),
    ]
    for (kind, title) in sections {
        let notes = parsed.notes.filter { $0.kind == kind }
        guard !notes.isEmpty else { continue }
        var order: [String] = []
        var byName: [String: [ConfigNote]] = [:]
        for n in notes {
            if byName[n.name] == nil { order.append(n.name) }
            byName[n.name, default: []].append(n)
        }
        print("\n\(title) (\(order.count)):")
        for name in order {
            let uses = byName[name]!
            let files = Set(uses.map(\.file))
            let places = files.count == 1
                ? "\(uses[0].file):" + uses.map { String($0.line) }.joined(separator: ",")
                : uses.map { "\($0.file):\($0.line)" }.joined(separator: " ")
            print(uses[0].reason.isEmpty ? "  \(name)  [\(places)]" : "  \(name): \(uses[0].reason)  [\(places)]")
        }
    }
    if !parsed.notes.isEmpty { print("") }
    print(parsed.errors.isEmpty ? "config ok: \(url.path)" : "\(parsed.errors.count) error(s)")
    exit(parsed.errors.isEmpty ? 0 : 1)
}

let me = ProcessInfo.processInfo.processIdentifier
let others = NSWorkspace.shared.runningApplications.filter {
    ["dev.mangochutney", "dev.mango.wm"].contains($0.bundleIdentifier ?? "") && $0.processIdentifier != me
}
if !others.isEmpty {
    print("mango is already running (pid \(others[0].processIdentifier))")
    exit(0)
}

setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate(configPath: configPath) }
MainActor.assumeIsolated { app.delegate = delegate }

for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    src.resume()
    _signalSources.append(src)
}
app.run()
