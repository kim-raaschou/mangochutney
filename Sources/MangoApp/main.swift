import AppKit
import Mango
import Port

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var server: MangoServer?
    var statusItem: NSStatusItem?
    var mainMenu: NSMenu?
    let layoutPanel = LayoutPanelModel()
    /// What the status item shows now (redrawn only when it changes).
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
        Permissions.shared.prepareFirstStart(configPath ?? ConfigParser.defaultConfigURL())
        Permissions.shared.showIfNeeded()
        if AX.isTrusted {
            startWM()
        } else {
            setStatus("Mango Chutney: needs Accessibility")
            Log.info("waiting for Accessibility permission (System Settings › Privacy & Security › Accessibility)")
            // No timer: macOS posts `com.apple.accessibility.api` when the list changes.
            // The grant can land a moment after that notice, so the check also runs
            // whenever an app is activated (leaving System Settings is one).
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
        Log.info("Accessibility granted")
        startWM()
    }

    func startWM() {
        let server = MangoServer(configURL: configPath)
        server.useMacSystem()   // mango on macOS: the port stands where wlroots does
        self.server = server
        server.onStateChange = { [weak self] in MainActor.assumeIsolated { self?.refreshStatus() } }
        server.setup()
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.cleanup()
    }

    // MARK: Menu bar

    func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
            // The mango logo (mangowm brand, from the mango repository) in front of the tags.
            if let logo = Self.logo(mono: false) {
                b.image = logo
                b.imagePosition = .imageLeft
                b.imageHugsTitle = true
            }
            // A click, left or right, opens the menu (the layouts first).
            b.target = self
            b.action = #selector(statusClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeLayoutPanelItem(model: layoutPanel))
        menu.addItem(.separator())
        // Learn, as Omarchy's menu. The palettes are on their keys (Hyper K, Hyper L), not here.
        menu.addItem(.sectionHeader(title: "Learn"))
        // Port extension: not in mango. The Hyper key (chutney_hyper_key, chutney_hyper_tap), and
        // what SUPER and HYPER are on a Mac; its last row opens the docs.
        // The keys as Raycast's Hyper Key offers them: Caps Lock, the modifiers, F1 … F12.
        let hyper = NSMenu()
        func keyItem(_ k: KeyboardOptions.HyperKey, in menu: NSMenu) {
            let i = menu.addItem(withTitle: k.label, action: #selector(setHyperKey(_:)), keyEquivalent: "")
            i.representedObject = k.name
            i.target = self
            hyperKeyItems.append(i)
        }
        let keys = KeyboardOptions.hyperKeys
        keyItem(keys[0], in: hyper)
        hyper.addItem(.separator())
        for k in keys where k.original == nil { keyItem(k, in: hyper) }
        let fKeys = NSMenu()
        for k in keys where k.name.hasPrefix("f") { keyItem(k, in: fKeys) }
        hyper.addItem(withTitle: "Function Keys", action: nil, keyEquivalent: "").submenu = fKeys
        hyper.addItem(.separator())
        hyper.addItem(.sectionHeader(title: "Quick Press"))
        for (title, tap) in [("Does Nothing", "none"), ("The Key Itself", "original"), ("Escape", "escape")] {
            let i = hyper.addItem(withTitle: title, action: #selector(setHyperTap(_:)), keyEquivalent: "")
            i.representedObject = tap
            i.target = self
            hyperTapItems.append(i)
        }
        hyper.addItem(.separator())
        legendItem = hyper.addItem(withTitle: "", action: #selector(showKeysDocs), keyEquivalent: "")
        legendItem?.target = self
        legendItem?.toolTip = "mango's modifiers on a Mac: SUPER is Command; HYPER is chutney_hyper_modifier"
        hyperItem = menu.addItem(withTitle: "Hyper Key", action: nil, keyEquivalent: "")
        hyperItem?.submenu = hyper
        menu.addItem(withTitle: "Getting Started", action: #selector(showGettingStarted), keyEquivalent: "")
        menu.addItem(withTitle: "mango Documentation", action: #selector(showMangoDocs), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload Config", action: #selector(reload), keyEquivalent: "r")
        menu.addItem(withTitle: "Edit Config", action: #selector(editConfig), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Restart Mango Chutney", action: #selector(restart), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Mango Chutney", action: #selector(quit), keyEquivalent: "q")
        for i in menu.items where i.submenu == nil { i.target = self }
        mainMenu = menu
        statusItem = item
        setStatus("mango")
    }

    /// mango.svg from the app bundle (or Resources/ next to a development build).
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
        // The brand colours, or (chutney_menu_bar_logo=mono) its shape in the menu bar's colour,
        // resolved as it is drawn (in the title a template image is not tinted).
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
        // Only touch the button when the text changes (it is redrawn by the system).
        shownStatus = ""
        if statusItem?.button?.title != s { statusItem?.button?.title = s }
    }

    /// The status item: the logo, each monitor's tags (chutney_menu_bar_tag_style) and layout
    /// icon (MenuBarStatus: the selected monitor's in full, the others dimmed), the key mode.
    func setStatus(monitors: [MenuBarMonitor], showLayout: Bool, mode: String, style: String, logo: String) {
        let key = "\(monitors)|\(showLayout)|\(mode)|\(style)|\(logo)"
        guard shownStatus != key, let b = statusItem?.button else { return }
        shownStatus = key
        // Everything in the title, the logo too: one line, one middle, one rhythm.
        b.image = nil
        let font = b.font ?? .monospacedSystemFont(ofSize: 12, weight: .medium)
        let title = NSMutableAttributedString()
        // The gaps: between the tags, and between the groups (logo, tags, layout, mode).
        let near: CGFloat = 3, apart: CGFloat = 7
        // The middle of the text line (its cap height's), where every image's middle goes,
        // on half points so the edges stay sharp on Retina.
        let middle = font.capHeight / 2
        func text(_ s: String, dim: Bool = false) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if dim { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            title.append(NSAttributedString(string: s, attributes: attrs))
        }
        // An empty attachment of `points` (kerning does not reach an attachment).
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
        // The tags' height (an SF Symbol square at 14 points) for the logo and the mode too.
        let cell = Self.tagImage(MenuBarTag(number: 1, active: false), style: style)?.size.height ?? 16
        // The gaps are measured ink to ink: an SF Symbol has some air at its sides, the logo
        // and the layout icon less.
        if logo != "off", let img = Self.logo(mono: logo == "mono") {
            image(img, height: cell)
            space(apart + 0.5)
        }
        for (n, m) in monitors.enumerated() {
            // One monitor is drawn as it always was; with more, the others are dimmed.
            let dim = monitors.count > 1 && !m.selected
            if n > 0 {
                image(Self.separatorImage, height: 13)
                space(apart)
            }
            for (i, t) in m.tags.enumerated() {
                if style == "text" {
                    // Every tag three characters wide, in view or not: the item keeps its width.
                    let c = t.number == 0 ? "S" : "\(t.number)"
                    text(t.active ? "[\(c)]" : " \(c) ", dim: dim)
                } else if let img = Self.tagImage(t, style: style, dim: dim) {
                    image(img, height: cell)
                    if i < m.tags.count - 1 { space(near) }
                }
            }
            if showLayout {
                // As text: mango's own layout symbol ("T", "DW"), two characters wide.
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
        // The key mode (chutney_menu_bar_mode), always shown so the item keeps its width: its
        // first letter in the tags' shape, mango's M outlined for the default mode, filled for another
        // ("w.square.fill"); as text when there is no such symbol or the tags are text.
        if !mode.isEmpty {
            let active = mode != "default"
            if style != "text", let img = Self.modeImage(mode, style: style, active: active) {
                image(img, height: cell)
            } else {
                let c = active ? (mode.first.map(String.init) ?? "?") : "M"
                text(active ? "[\(c)]" : " \(c) ")
            }
        } else if title.length > 0 {
            title.deleteCharacters(in: NSRange(location: title.length - 1, length: 1))   // no gap at the end
        }
        b.attributedTitle = title
    }

    /// A tag as an SF Symbols number ("3.square.fill", "3.circle"; the special tag a star),
    /// a template image the menu bar colours itself.
    static func tagImage(_ t: MenuBarTag, style: String, dim: Bool = false) -> NSImage? {
        let shape = style == "circle" ? "circle" : "square"
        let name = (t.number == 0 ? "star" : "\(t.number)") + ".\(shape)" + (t.active ? ".fill" : "")
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: "tag \(t.number)")?
            .withSymbolConfiguration(cfg) else { return nil }
        img.isTemplate = true
        return dim ? dimmed(img) : img
    }

    /// The line between two monitors' groups, in the menu bar's text colour, a little lighter.
    static let separatorImage = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
        NSColor.labelColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: CGRect(x: 0.25, y: 0, width: 1.5, height: rect.height), xRadius: 0.75, yRadius: 0.75).fill()
        return true
    }

    /// Another monitor's tag: the symbol in the menu bar's text colour, dimmed as secondary
    /// text is (resolved as it is drawn: light and dark menu bars). A template image is not
    /// dimmed by the menu bar, so it is drawn in that colour here.
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

    /// A key mode as its first letter in the tags' shape: "m.square" for default, "w.square.fill".
    static func modeImage(_ mode: String, style: String, active: Bool) -> NSImage? {
        // default mode shows mango's M; another mode its own first letter
        guard let c = (active ? mode.lowercased().first : "m"), c.isLetter, c.isASCII else { return nil }
        let shape = style == "circle" ? "circle" : "square"
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let img = NSImage(systemSymbolName: "\(c).\(shape)" + (active ? ".fill" : ""), accessibilityDescription: "\(mode) mode")?
            .withSymbolConfiguration(cfg)
        img?.isTemplate = true
        return img
    }

    /// The layout's icon from LayoutIcon's frames, in the menu bar's text colour (labelColor,
    /// resolved as it is drawn: light and dark menu bars). Not a template image: in the
    /// title's text only SF Symbols are tinted, our own template stays black. Edges on half
    /// points (a pixel on a Retina screen) stay sharp; cards behind another at least half
    /// solid, so a pile reads as cards.
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
        statusItem?.isVisible = config.chutneyMenuBar
        let mode = config.chutneyMenuBarMode ? server.keyMode : (server.keyMode == "default" ? "" : server.keyMode)
        setStatus(monitors: MenuBarStatus.monitors(server), showLayout: config.chutneyMenuBarLayout, mode: mode,
                  style: config.chutneyMenuBarTagStyle, logo: config.chutneyMenuBarLogo)
    }

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        if server == nil { startIfTrusted() }   // granted while System Settings stayed in front
        showMenu(mainMenu)
    }

    /// Open the menu from the status item (the native way, anchored under it).
    func showMainMenu() { showMenu(mainMenu) }

    func showMenu(_ menu: NSMenu?) {
        guard let item = statusItem, let menu else { return }
        item.menu = menu
        item.button?.performClick(nil)
        // Detached again in menuDidClose, never while it is still open.
    }

    func menuWillOpen(_ menu: NSMenu) {
        server?.holdNativeFocus = true
        layoutPanel.server = server
        layoutPanel.refresh()
        loginItem?.state = FileManager.default.fileExists(atPath: Self.loginPlist) ? .on : .off
        if let server {
            legendItem?.title = ModifierLegend.text(server.config)
            let key = server.config.chutneyHyperKey
            for i in hyperKeyItems { i.state = (i.representedObject as? String) == key ? .on : .off }
            hyperItem?.title = "Hyper Key: " + (KeyboardOptions.hyperKey(key)?.label ?? "⌃⌥⌘ held")
            // Quick Press, as Raycast's: only for Caps Lock and a function key.
            let quick = KeyboardOptions.hyperKey(key)?.original != nil
            for i in hyperTapItems {
                i.state = (i.representedObject as? String) == server.config.chutneyHyperTap ? .on : .off
                i.isEnabled = quick
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        // Fires for submenus too; only the top-level menu closing ends the session.
        guard menu === mainMenu || menu.supermenu == nil else { return }
        if menu === mainMenu { statusItem?.menu = nil }
        // Let the click that closed the menu land first, then apply any held focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated { self?.server?.holdNativeFocus = false }
        }
    }

    @objc func reload() { server?.reloadConfig() }

    var legendItem: NSMenuItem?
    var hyperItem: NSMenuItem?
    var hyperKeyItems: [NSMenuItem] = []
    var hyperTapItems: [NSMenuItem] = []

    /// The Hyper key from the menu: kept in the menu's file (chutney_menu_config), read last.
    @objc func setHyperKey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        saveMenuChoice("chutney_hyper_key", key)
    }
    @objc func setHyperTap(_ sender: NSMenuItem) {
        guard let tap = sender.representedObject as? String else { return }
        saveMenuChoice("chutney_hyper_tap", tap)
    }
    private func saveMenuChoice(_ key: String, _ value: String) {
        guard let server, let url = MenuSave.url(server.config, configURL: server.configURL) else { return }
        MenuSave.set(key, value, in: url)
        server.reloadConfig()
    }
    /// The docs' page on the keys (bundled with the app until they are on the web).
    @objc func showKeysDocs() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("docs/chutney/bindings/keys.md") else { return }
        NSWorkspace.shared.open(url)
    }
    @objc func showGettingStarted() { Permissions.openGettingStarted() }
    @objc func showMangoDocs() {
        NSWorkspace.shared.open(URL(string: "https://mangowm.github.io/docs/")!)
    }
    @objc func editConfig() {
        ConfigFiles.open(server?.configURL ?? ConfigParser.defaultConfigURL())
    }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func showPermissions() { Permissions.shared.show() }

    var loginItem: NSMenuItem?
    static var loginPlist: String { NSHomeDirectory() + "/Library/LaunchAgents/dev.mangochutney.plist" }

    /// Start at Login: `mmsg service install` / `mmsg service uninstall`, the mmsg next to this
    /// mango. When this mango is the service itself, uninstall only removes the plist (no
    /// bootout, which would stop this mango); the service is gone at the next login.
    @objc func toggleLogin() {
        let installed = FileManager.default.fileExists(atPath: Self.loginPlist)
        if installed, ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == "dev.mangochutney" {
            try? FileManager.default.removeItem(atPath: Self.loginPlist)
            return
        }
        service(installed ? "uninstall" : "install")
    }

    /// `mmsg service <verb>`, with the mmsg beside this mango.
    func service(_ verb: String) {
        let mmsg = Bundle.main.executableURL!.resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("mmsg").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: mmsg)
        p.arguments = ["service", verb]
        try? p.run()
    }

    /// A new mango once this one has gone (one runs at a time): from the login service when
    /// it is installed (`mmsg service install`), else the app again. This one quits as
    /// `chutney_restart` does: hidden windows stay hidden, the next mango restores them.
    /// The helper waits for the exit by checking every 0.1 s, for the second or so mango
    /// takes to quit.
    @objc func restart() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = Bundle.main.bundlePath
        let app = path.hasSuffix(".app") ? "'\(path.replacingOccurrences(of: "'", with: ""))'" : "'Mango Chutney'"
        Spawn.shell("while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; "
                    + "launchctl kickstart gui/\(getuid())/dev.mangochutney 2>/dev/null || open -a \(app)")
        if let server { _ = server.dispatch(Dispatch(name: "chutney_restart")) } else { NSApp.terminate(nil) }
    }
}

// MARK: - Entry

nonisolated(unsafe) var _signalSources: [DispatchSourceSignal] = []

// Not in mango: the port's answers to mango's config reader (its keys, its notes), before any
// config is read.
MacConfigPort.install()

var configPath: URL?
var check = false
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "-c", "--config":
        if let p = args.next() { configPath = URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
    case "-p", "--check":
        check = true   // after every argument, so `-p -c <file>` checks that file
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
        Log.verbose = true
    case "-h", "--help":
        print("""
        Usage: mango [-c config] [-p] [--list-ignored] [--list-glance] [-d] [-v]
          -c, --config <path>   use this config file (default ~/.config/mango/config.conf, else config.toml)
          -p, --check           validate the config, list what has no effect on macOS, and exit
          --list-ignored        print the mango names that do nothing on macOS (Markdown)
          --list-glance         print how much of mango works on macOS (Markdown)
          -d, --debug           verbose logging
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
    // Port extension: not in mango. Where the menu's saved settings overrule this file.
    if let menu = MenuSave.url(parsed.config, configURL: url) {
        // The config reads the menu's file with mango's own source_optional, last.
        if !parsed.sourcedFiles.contains(where: { $0.standardizedFileURL == menu }) {
            print("warning: chutney_menu_config: \(menu.lastPathComponent) is saved to but not read; end the config with source_optional=\(menu.lastPathComponent)")
        }
        for c in MenuSave.conflicts(configURL: url, menuURL: menu) {
            print("warning: \(c.configFile):\(c.configLine) \(c.key) \(c.configValue) is overridden by \(menu.lastPathComponent) (\(c.menuValue))")
        }
    }
    // Port extension: not in mango. chutney_style's colours (chutney_theme.conf) over this file's.
    if parsed.config.chutneyStyle {
        let theme = ChutneyTheme.url(configURL: url)
        if !parsed.sourcedFiles.contains(where: { $0.standardizedFileURL == theme }) {
            print("warning: chutney_style: \(theme.lastPathComponent) is written but not read; add source_optional=\(theme.lastPathComponent) before the menu's source_optional line")
        } else {
            let keys = MenuSave.conflicts(configURL: url, menuURL: theme).map(\.key)
            if !keys.isEmpty {
                print("note: chutney_style: \(theme.lastPathComponent) draws \(keys.count) colour(s) of \(url.lastPathComponent) in macOS's (\(keys.joined(separator: ", "))); to keep one, set it in chutney.conf after source_optional=\(theme.lastPathComponent)")
            }
        }
    }
    // Not errors: what a mango user should know about this file on macOS.
    let sections: [(ConfigNote.Kind, String)] = [
        (.notYet, "Not implemented yet, macOS would allow it"),
        (.noEffect, "Cannot work on macOS"),
        (.unsupportedDispatcher, "Bindings that cannot work on macOS"),
        (.portExtension, "macOS port extensions (mango itself reports each as an unknown keyword)"),
    ]
    for (kind, title) in sections {
        let notes = parsed.notes.filter { $0.kind == kind }
        guard !notes.isEmpty else { continue }
        // One line per name, with every place it is used.
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

// Refuse to run twice.
let me = ProcessInfo.processInfo.processIdentifier
let others = NSWorkspace.shared.runningApplications.filter {
    // and the app from before it was named Mango Chutney
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

// Restore windows on SIGTERM / SIGINT (launchctl stop, Ctrl-C).
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    src.resume()
    _signalSources.append(src)
}
app.run()
