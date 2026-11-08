import AppKit
import SwiftUI
import Mango

@MainActor
public final class HotkeysPalette {
    public static let shared = HotkeysPalette()
    private var panel: HotkeysPanel?
    private let model = HotkeysModel()
    private var keyMonitor: Any?
    private weak var server: MangoServer?

    func toggle(_ server: MangoServer) {
        if panel?.isVisible == true { close() } else { show(server) }
    }

    public func show(_ server: MangoServer) {
        self.server = server
        let config = server.config
        model.maxRows = config.chutneyHotkeysMaxRows
        model.recentCount = config.chutneyHotkeysRecent
        model.width = CGFloat(config.chutneyHotkeysWidth)
        model.look = HotkeysLook(config: config)
        model.legend = ModifierLegend.text(config)
        let hyper = Modifiers.parse(config.chutneyHyperModifier, hyperModifier: "") ?? []
        model.onLayout = nil
        let apps = config.chutneyHotkeysApps ? SpotlightApps.shared : nil
        model.load(server.shortcutRows, hyper: hyper,
                   context: Self.context(server), windows: Self.windows(server), apps: apps?.apps ?? [],
                   usage: HotkeysUsage.scores(HotkeysUsage.read()))
        apps?.onChange = { [weak self] found in
            guard let self, self.panel?.isVisible == true else { return }
            self.model.setApps(found)
        }
        model.run = { [weak self] row in self?.run(row) }
        if panel == nil {
            let p = HotkeysPanel(contentRect: NSRect(x: 0, y: 0, width: model.width, height: model.look.height(rows: model.maxRows)),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.onResign = { [weak self] in self?.close() }
            let glass = GlassBacking(material: .popover)
            let host = NSHostingView(rootView: HotkeysView(model: model))
            host.translatesAutoresizingMaskIntoConstraints = false
            glass.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                host.topAnchor.constraint(equalTo: glass.topAnchor),
                host.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            p.contentView = glass
            panel = p
        }
        panel?.appearance = model.look.macOS ? nil : NSAppearance(named: .darkAqua)
        (panel?.contentView as? GlassBacking)?.cornerRadius = model.look.cornerRadius
        panel?.invalidateShadow()
        let id = server.selectedMonitor?.screen.displayID
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let tallest = model.look.height(rows: model.maxRows)
            top = NSPoint(x: area.midX - model.width / 2, y: min(area.maxY, area.midY + tallest / 2))
        }
        fit(model.page.rows)
        model.onLayout = { [weak self] rows in self?.fit(rows) }
        server.holdNativeFocus = true
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, self.panel?.isKeyWindow == true else { return e }
                return self.handle(e) ? nil : e
            }
        }
        panel?.makeKeyAndOrderFront(nil)
        if let p = panel { NativeFocus.focusOwn(windowID: CGWindowID(p.windowNumber)) }
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
        focusSearch()
        DispatchQueue.main.async { [weak self] in self?.focusSearch() }
    }

    private var top = NSPoint.zero

    private func fit(_ rows: Int) {
        let h = model.look.height(rows: rows)
        panel?.setFrame(NSRect(x: top.x, y: top.y - h, width: model.width, height: h), display: true)
    }

    private func focusSearch() {
        guard let panel, let field = model.field, panel.firstResponder !== field.currentEditor() else { return }
        panel.makeFirstResponder(field)
    }

    private func handle(_ e: NSEvent) -> Bool {
        let ctrl = e.modifierFlags.contains(.control)
        switch e.keyCode {
        case 125: model.move(1)
        case 126: model.move(-1)
        case 48: model.move(e.modifierFlags.contains(.shift) ? -1 : 1)
        case 45 where ctrl, 38 where ctrl: model.move(1)
        case 35 where ctrl, 40 where ctrl: model.move(-1)
        case 36, 76: model.enter()
        case 124: return model.query.isEmpty && (model.moveColumn(1) || model.openSelected())
        case 123: return model.query.isEmpty && (model.moveColumn(-1) || model.back())
        case 51: return model.query.isEmpty && model.back()
        case 53: if !model.escape() { close() }
        default:
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let c = e.charactersIgnoringModifiers, c.count == 1, let n = Int(c) else { return false }
            return model.digit(n)
        }
        return true
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        releaseFocus()
    }

    private func run(_ row: HotkeyRow) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.orderOut(nil)
        guard let server else { return }
        switch row.kind {
        case .binding(let d, let args):
            HotkeysUsage.record(row.id)
            server.dispatch(Dispatch(name: d, args: model.typedArguments(row) ?? args))
        case .window(let id):
            if let c = server.clientByIdAll(id) { server.dispatch(Dispatch(name: "focusid"), target: c) }
        case .app(let path):
            HotkeysUsage.record(row.id)
            let id = row.appID ?? ""
            let windows = server.appWindowsInGridOrder(id.lowercased())
            if let last = server.focusHistory.lazy.compactMap({ h in windows.first { $0.id == h } }).first ?? windows.first {
                server.dispatch(Dispatch(name: "focusid"), target: last)
            } else {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
                if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                    server.holdNativeFocus = false
                    return
                }
            }
        }
        releaseFocus()
    }

    static func context(_ server: MangoServer) -> HotkeysContext {
        var c = HotkeysContext()
        if let f = server.focused {
            c.hasFocused = true
            c.floating = f.isFloating
            c.fullscreen = f.isFullscreen
            c.maximized = f.isMaximizeScreen
            c.global = f.isGlobal
            c.overlay = f.isOverlay
        }
        if let m = server.selectedMonitor {
            c.layout = m.layout.name
            let viewed = m.tagset[m.seltags]
            c.viewedTags = Set((1...32).filter { viewed & (1 << UInt32($0 - 1)) != 0 })
        }
        c.monitorCount = server.monitors.count
        c.minimizedCount = server.clients.filter(\.isMinimized).count
        c.overview = server.overviewState != nil
        c.gaps = server.enableGaps
        for r in server.shortcutRows where r.dispatch == "chutney_focus_app" {
            guard let app = r.args.first?.lowercased(), c.appSteps[app] == nil else { continue }
            let windows = server.appWindowsInGridOrder(app).map(\.id)
            let current = server.focused?.id
            let rule = FocusAppRule.decide(windows: windows, current: current, recent: server.focusHistory)
            c.appSteps[app] = HotkeysAppStep(rule: rule, windows: windows.count,
                                             inApp: current.map(windows.contains) ?? false)
        }
        return c
    }

    static func windows(_ server: MangoServer) -> [HotkeysWindow] {
        let focused = server.focused?.id
        let all = server.clients.map { c -> HotkeysWindow in
            let tags = c.tags & 0x7FFF_FFFF
            let tag: Int? = c.isMinimized ? nil : (tags == 0 ? 0 : tags.trailingZeroBitCount + 1)
            return HotkeysWindow(id: c.id, app: c.appName, bundleID: c.bundleId, title: c.title, tag: tag,
                                 focused: c.id == focused,
                                 appPath: NSRunningApplication(processIdentifier: c.pid)?.bundleURL?.path)
        }
        return all.filter(\.focused) + all.filter { !$0.focused }
    }

    private func releaseFocus() {
        guard let server else { return }
        server.holdNativeFocus = false
        if NSApp.keyWindow == nil, let c = server.focused { server.mac.focus(c, raise: true) }
    }
}

final class HotkeysPanel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {}
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

struct HotkeysLook {
    var macOS: Bool
    var marking: Color = .accentColor
    var root = Color(Config().rootcolor)
    var border = Color(Config().bordercolor)

    init(macOS: Bool) { self.macOS = macOS }

    init(config: Config) {
        macOS = config.chutneyStyle
        marking = PortAccent.color(config)
        root = Color(config.rootcolor)
        border = Color(config.bordercolor)
    }

    var cornerRadius: CGFloat { macOS ? 14 : 0 }
    var rowHeight: CGFloat { macOS ? 34 : 38 }
    var rowSpacing: CGFloat { 2 }
    var searchHeight: CGFloat { macOS ? 44 : 40 }
    var padding: CGFloat { macOS ? 10 : 20 }
    var placeholder: String { macOS ? "Search hotkeys, windows and apps" : "Go…" }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        macOS ? .system(size: size, weight: weight) : .system(size: size, weight: weight, design: .monospaced)
    }

    var text: Color { macOS ? Color.primary : Color(white: 0.9) }
    var dim: Color { macOS ? Color.primary : Color(white: 0.6) }
    var accent: Color { marking }
    var selectionFill: Color { marking }
    var selectionText: Color { .white }
    var background: Color { macOS ? .clear : root }
    var frame: Color { border }

    func height(rows: Int) -> CGFloat {
        2 * padding + searchHeight + (macOS ? 9 : 20) + 16
            + CGFloat(max(rows, 1)) * (rowHeight + rowSpacing)
    }
}

struct HotkeysView: View {
    @ObservedObject var model: HotkeysModel
    private var look: HotkeysLook { model.look }

    var body: some View {
        VStack(alignment: .leading, spacing: look.macOS ? 4 : 10) {
            HStack(spacing: 8) {
                if look.macOS {
                    Image(systemName: "magnifyingglass").font(look.font(18)).foregroundStyle(look.dim)
                }
                if let s = model.openSection, model.query.isEmpty {
                    Text(look.macOS ? s : "\(s) ›").foregroundStyle(look.macOS ? look.accent : look.dim)
                    if look.macOS {
                        Image(systemName: "chevron.right").font(look.font(12)).foregroundStyle(look.dim)
                    }
                }
                HotkeysSearchField(text: $model.query, placeholder: look.placeholder, macOS: look.macOS) { model.field = $0 }
                Text(model.legend).font(look.font(12)).foregroundStyle(look.dim).fixedSize()
            }
            .font(look.font(look.macOS ? 20 : 15))
            .padding(.horizontal, look.macOS ? 8 : 4)
            .frame(height: look.searchHeight)
            if look.macOS { Divider().padding(.bottom, 4) }

            let page = model.page
            if page.items.isEmpty {
                Text("Nothing matches").foregroundStyle(look.dim).font(look.font(13))
                    .padding(.horizontal, 12).frame(height: look.rowHeight)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<page.columns, id: \.self) { col in
                        VStack(spacing: look.rowSpacing) {
                            ForEach(Array(page.items.enumerated()).filter { $0.offset / max(page.rows, 1) == col },
                                    id: \.offset) { i, item in
                                row(item, selected: i == model.selection)
                                    .contentShape(Rectangle())
                                    .onHover { if $0 { model.selection = i } }
                                    .onTapGesture { model.selection = i; model.enter() }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
            Spacer(minLength: 0)
            footer
                .font(look.font(11))
                .foregroundStyle(look.dim)
                .padding(.horizontal, look.macOS ? 8 : 0)
        }
        .padding(look.padding)
        .frame(width: model.width, height: look.height(rows: model.page.rows))
        .background(look.background)
        .overlay { if !look.macOS { Rectangle().stroke(look.frame, lineWidth: 2) } }
    }

    private var footer: Text {
        let more = model.page.more
        let tail = more > 0 ? Text("   +\(more) more: type to narrow").foregroundStyle(look.accent) : Text("")
        return hint + tail
    }

    private var hint: Text {
        guard let r = model.selectedRow else { return Text("↑↓ move   ↩ open   ← back   esc close") }
        if !r.digits.isEmpty, let lo = r.digits.keys.min(), let hi = r.digits.keys.max() {
            return Text("type \(lo)–\(hi) to run it for that number")
        }
        switch r.kind {
        case .window: return Text("↩ go to the window   esc close")
        case .app: return Text("↩ open the app   esc close")
        case .binding(let d, _):
            if !r.runnable { return Text(r.enabled ? "a drag: use its keys" : "nothing to act on now") }
            if let args = model.typedArguments(r) {
                return Text("↩ " + ShortcutFormatter.action(Dispatch(name: d, args: args))).foregroundStyle(look.accent)
            }
            if r.keys.isEmpty { return Text("↩ \(r.next ?? "run")   no key; type :60 for a width") }
            return Text("↩ \(r.next ?? "run")   next time: ") + Text(keyText(r.keys)).foregroundStyle(look.accent)
        }
    }

    @ViewBuilder
    private func row(_ item: HotkeysModel.Item, selected: Bool) -> some View {
        let fg = selected ? look.selectionText : look.text
        let dim = selected && look.macOS ? Color.white.opacity(0.75) : look.dim
        HStack(spacing: look.macOS ? 10 : 14) {
            switch item {
            case .group(let s, let n):
                symbol(HotkeysModel.icon(s), selected: selected)
                Text(s)
                Spacer()
                Text("\(n)").foregroundStyle(dim)
                Image(systemName: "chevron.right").font(look.font(12)).foregroundStyle(dim)
            case .row(let r):
                let recent = model.query.isEmpty && model.openSection == nil
                if let path = r.iconPath {
                    Image(nsImage: AppIcons.icon(path)).resizable().frame(width: 22, height: 22).frame(width: 24)
                } else {
                    symbol(recent ? "clock" : HotkeysModel.icon(r.section), selected: selected)
                }
                Text(r.action).lineLimit(1)
                if let st = r.state {
                    Text(st)
                        .font(look.font(11))
                        .foregroundStyle(st == "off" ? dim : (selected ? fg : look.accent))
                }
                Spacer(minLength: 12)
                if let place = r.place, !place.isEmpty {
                    Text(place).font(look.font(look.macOS ? 13 : 14)).foregroundStyle(dim).padding(.trailing, 6)
                }
                keys(r.keys, dim: dim)
            }
        }
        .font(look.font(look.macOS ? 13 : 14))
        .foregroundStyle(fg)
        .opacity(isRunnable(item) ? 1 : 0.45)
        .padding(.horizontal, look.macOS ? 10 : 16).frame(height: look.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: look.macOS ? 7 : 0)
                .fill(selected ? look.selectionFill : Color.clear)
        }
    }

    private func symbol(_ name: String, selected: Bool) -> some View {
        Image(systemName: name)
            .foregroundStyle(look.macOS && !selected ? look.dim : (selected ? look.selectionText : look.text))
            .frame(width: 24)
    }

    private func isRunnable(_ item: HotkeysModel.Item) -> Bool {
        if case .row(let r) = item { return r.enabled }
        return true
    }

    @ViewBuilder
    private func keys(_ keys: [String], dim: Color) -> some View {
        if look.macOS {
            Text(keyText(keys)).font(look.font(13)).foregroundStyle(dim)
        } else {
            HStack(spacing: 4) { ForEach(Array(keys.enumerated()), id: \.offset) { keycap($0.element) } }
        }
    }

    private func keyText(_ keys: [String]) -> String {
        guard look.macOS else { return keys.joined(separator: " ") }
        var out = ""
        for k in keys {
            if k == "›" { out += " › "; continue }
            out += k == "Hyper" ? "Hyper " : k
        }
        return out
    }

    @ViewBuilder
    private func keycap(_ s: String) -> some View {
        if s == "›" {
            Text(s).font(look.font(12)).foregroundStyle(look.dim)
        } else {
            Text(s)
                .font(look.font(12))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(look.dim.opacity(0.6), lineWidth: 1) }
        }
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(_ path: String) -> NSImage {
        if let i = cache[path] { return i }
        let i = NSWorkspace.shared.icon(forFile: path)
        cache[path] = i
        return i
    }
}

struct HotkeysSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var macOS: Bool
    var made: (NSTextField) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.delegate = context.coordinator
        style(f)
        made(f)
        return f
    }

    private func style(_ f: NSTextField) {
        let font = macOS ? NSFont.systemFont(ofSize: 20) : NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        f.font = font
        f.textColor = macOS ? .labelColor : NSColor(red: 0.86, green: 0.82, blue: 0.72, alpha: 1)
        f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: macOS ? NSColor.placeholderTextColor : NSColor(red: 0.55, green: 0.53, blue: 0.48, alpha: 1),
        ])
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.text = $text
        if f.stringValue != text { f.stringValue = text }
        style(f)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { text.wrappedValue = f.stringValue }
        }
    }
}

@MainActor
final class SpotlightApps {
    static let shared = SpotlightApps()
    private(set) var apps: [HotkeysApp] = []
    var onChange: (([HotkeysApp]) -> Void)?
    private nonisolated(unsafe) let query = NSMetadataQuery()
    private let queue = OperationQueue()

    private init() {
        queue.maxConcurrentOperationCount = 1
        query.operationQueue = queue
        query.predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.valueListAttributes = [NSMetadataItemDisplayNameKey, "kMDItemCFBundleIdentifier",
                                     "kMDItemLastUsedDate", "kMDItemUseCount"]
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            nc.addObserver(forName: name, object: query, queue: queue) { [weak self, query] _ in
                let apps = Self.read(query)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.apps = apps
                        self?.onChange?(apps)
                    }
                }
            }
        }
        queue.addOperation { [query] in query.start() }
    }

    private nonisolated static func read(_ query: NSMetadataQuery) -> [HotkeysApp] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        func value(_ attr: String, _ i: Int) -> Any? { query.value(ofAttribute: attr, forResultAt: i) }
        var byID: [String: HotkeysApp] = [:]
        var noID: [HotkeysApp] = []
        for i in 0..<query.resultCount {
            guard let path = (query.result(at: i) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String,
                  isApp(path) else { continue }
            var name = (value(NSMetadataItemDisplayNameKey, i) as? String) ?? (path as NSString).lastPathComponent
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            let app = HotkeysApp(name: name, path: path,
                                 bundleID: value("kMDItemCFBundleIdentifier", i) as? String ?? "",
                                 lastUsed: value("kMDItemLastUsedDate", i) as? Date,
                                 useCount: value("kMDItemUseCount", i) as? Int ?? 0)
            if app.bundleID.isEmpty { noID.append(app); continue }
            if let old = byID[app.bundleID], (old.lastUsed ?? .distantPast) >= (app.lastUsed ?? .distantPast) { continue }
            byID[app.bundleID] = app
        }
        return (Array(byID.values) + noID).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func isApp(_ path: String) -> Bool {
        let inner = path.dropLast(4)
        if inner.contains(".app/") { return false }
        if path.contains("/Library/") && !path.hasPrefix("/System/Library/CoreServices/") { return false }
        return true
    }
}
