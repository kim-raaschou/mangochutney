import AppKit
import SwiftUI
import Mango
import Port

@MainActor
final class LayoutPanelModel: ObservableObject {
    weak var server: MangoServer?
    weak var host: NSView?
    /// macOS's Reduce motion (Accessibility › Motion): Space changes fade instead of slide. Only System
    /// Settings changes it; it is shown here as macOS tells it.
    @Published var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var motionObserver: NSObjectProtocol?
    @Published var layout: LayoutKind = .tile
    @Published var animations = true
    @Published var screenWidth: CGFloat = 1728
    @Published var gapSpecial = false
    @Published var gapLinkInner = true
    @Published var gapLinkOuter = true
    @Published var config = Config()
    @Published var border: Double = 0
    @Published var mfact: Double = 0.55
    @Published var nmaster: Double = 1
    @Published var fitInfo = false

    init() {
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        }
    }

    static let motionSettings = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Motion")!

    /// System Settings at Accessibility › Motion, where Reduce motion is; the menu closes.
    func openMotionSettings() {
        host?.enclosingMenuItem?.menu?.cancelTracking()
        NSWorkspace.shared.open(Self.motionSettings)
    }

    func toggleFitInfo() {
        fitInfo.toggle()
        refresh()
    }

    private func resizeHost() {
        guard let h = host else { return }
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize
        if h.frame.size != size { h.frame.size = size }
    }

    func refresh() {
        defer {
            resizeHost()
            DispatchQueue.main.async { [weak self] in self?.resizeHost() }
        }
        guard let server, let m = server.selectedMonitor else { return }
        layout = m.layout
        screenWidth = m.screen.workArea.width
        border = Double(server.config.borderpx)
        animations = server.config.animations
        config = server.config
        mfact = Double(m.pertag.mfacts[getMonCurtag(m)])
        nmaster = Double(m.pertag.nmasters[getMonCurtag(m)])
    }

    private func send(_ name: String, _ args: String...) {
        server?.dispatch(Dispatch(name: name, args: args))
        refresh()
    }

    func setLayout(_ k: LayoutKind) {
        send("setlayout", k.name)
        saveTag("layout_name", k.name)
    }
    func inCircle(_ k: LayoutKind) -> Bool { CircleLayout.contains(config.circleLayout, k) }

    func toggleCircle(_ k: LayoutKind) {
        guard let server, let names = CircleLayout.toggled(config.circleLayout, k) else { return }
        CircleLayout.set(names, server: server)
        refresh()
    }

    func setOption(_ key: String, _ value: String) { option(key, value) }

    func setGap(_ key: String, _ px: Int) {
        option(key, String(max(0, px)))
    }

    func tagField(_ field: String) -> String { "tag_rule id:\(server?.selectedMonitor?.pertag.curtag ?? 0) \(field)" }

    var accent: Color { PortAccent.color(config) }
    private var menuURL: URL? { server.flatMap { MenuSave.url($0.config, configURL: $0.configURL) } }

    private func option(_ key: String, _ value: String) {
        server?.dispatch(Dispatch(name: "setoption", args: [key, value]))
        if let url = menuURL { MenuSave.set(key, value, in: url) }
        refresh()
    }

    private func saveTag(_ field: String, _ value: String) {
        guard let url = menuURL, let m = server?.selectedMonitor, m.pertag.curtag > 0 else { return }
        MenuSave.setTagRule(tag: Int(m.pertag.curtag), field, value, in: url)
        refresh()
    }

    func setAnimations(_ on: Bool) {
        guard on != server?.config.animations else { return }
        option("animations", on ? "1" : "0")
    }
    func setBorder(_ v: Double) {
        let px = Int(v.rounded())
        guard px != server?.config.borderpx else { return }
        option("border_px", String(px))
    }
    func setMfact(_ v: Double) {
        guard abs(v - Double(server?.selectedMonitor.map { $0.pertag.mfacts[getMonCurtag($0)] } ?? 0)) > 0.001 else { return }
        send("setmfact", String(format: "%.2f", 1 + v))
        saveTag("master_factor", String(format: "%.2f", v))
    }
    func setNmaster(_ v: Double) {
        guard let m = server?.selectedMonitor else { return }
        let d = Int(v.rounded()) - Int(m.pertag.nmasters[getMonCurtag(m)])
        if d != 0 {
            send("incnmaster", String(d))
            saveTag("master_count", String(Int(v.rounded())))
        }
    }
}

struct LayoutPanelView: View {
    @ObservedObject var model: LayoutPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Layout")
            LayoutGrid(model: model)
            let options = LayoutOption.options(for: model.layout)
            if model.layout.usesMaster || !options.isEmpty {
                header("Layout options")
            }
            if model.layout.usesMaster {
                slider("mfact", value: $model.mfact, in: 0.1...0.9, step: 0.05, percent: true, commit: model.setMfact)
                    .help("master width (the tag's)")
                slider("nmaster", value: $model.nmaster, in: 0...6, step: 1, unit: "", commit: model.setNmaster)
                    .help("windows in the master area (the tag's)")
            }
            ForEach(options) { optionView($0) }
        }
        .padding(12)
        .frame(width: 340)
    }

    @ViewBuilder
    private func optionView(_ o: LayoutOption) -> some View {
        switch o.kind {
        case .toggle(let kp):
            Toggle(o.key, isOn: Binding(get: { model.config[keyPath: kp] },
                                        set: { model.setOption(o.key, $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced))
                .toggleStyle(.switch).controlSize(.mini)
                .disabled(o.disabled(model.config))
                .help(o.title)
        case .slider(let kp, let range, let step):
            slider(o.key, value: Binding(get: { Double(model.config[keyPath: kp]) }, set: { model.config[keyPath: kp] = Float($0) }),
                   in: range, step: step, label: String(format: step < 1 ? "%.2f" : "%.0f", Double(model.config[keyPath: kp])),
                   commit: { model.setOption(o.key, String(format: "%.2f", $0)) })
                .help(o.title)
        case .intSlider(let kp, let range, let step):
            slider(o.key, value: Binding(get: { Double(model.config[keyPath: kp]) },
                                         set: { model.config[keyPath: kp] = Int($0) }),
                   in: range, step: step, label: "\(model.config[keyPath: kp])",
                   commit: { model.setOption(o.key, String(Int($0))) })
                .help(o.title)
        case .choice(let kp, let labels):
            HStack {
                Text(o.key).font(.system(size: 10, design: .monospaced)).help(o.title)
                Spacer()
                Picker("", selection: Binding(get: { model.config[keyPath: kp] },
                                              set: { model.setOption(o.key, String($0)) })) {
                    ForEach(labels.indices, id: \.self) { Text(labels[$0]).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
        }
    }

    private func header(_ s: String) -> some View { panelHeader(s) }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        unit: String = "", percent: Bool = false, label: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        panelSlider(model, title, value: value, in: range, step: step, unit: unit, percent: percent, label: label, commit: commit)
    }
}

@MainActor
func panelHeader(_ s: String) -> some View {
    Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
}

@MainActor
func panelSlider(_ model: LayoutPanelModel, _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                 unit: String = "", percent: Bool = false, label: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, design: .monospaced))
                Spacer()
                Text(label ?? (percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue))\(unit)"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(model.accent)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { _, v in commit(v) }
        }
}

struct LookView: View {
    @ObservedObject var model: LayoutPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Desktop")
            GapEditor(model: model)
            slider("border_px", value: $model.border, in: 0...5, step: 1,
                   label: "\(Int(model.border)) px",
                   commit: model.setBorder)
                .help("border width")
            header("Effects")
            Toggle("animations", isOn: Binding(get: { model.animations }, set: { model.setAnimations($0) }))
                .font(.system(size: 10, design: .monospaced))
                .toggleStyle(.switch)
                .controlSize(.mini)
            HStack {
                Text("animation_type_open").font(.system(size: 10, design: .monospaced))
                Spacer()
                Picker("", selection: Binding(get: { model.config.animationTypeOpen.rawValue },
                                              set: { model.setOption("animation_type_open", $0) })) {
                    Text("slide").tag("slide")
                    Text("zoom").tag("zoom")
                    Text("none").tag("none")
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
            .disabled(!model.animations)
            HStack {
                Text("tag_animation_direction").font(.system(size: 10, design: .monospaced))
                Spacer()
                Picker("", selection: Binding(get: { model.config.tagAnimationDirection },
                                              set: { model.setOption("tag_animation_direction", String($0)) })) {
                    Text("horizontal").tag(1)
                    Text("vertical").tag(0)
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
            .disabled(!model.animations)
            Text("Durations and curves: animation_duration_* and animation_curve_* in your config.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            header("Menu bar")
            HStack {
                Text("tags").font(.system(size: 10, design: .monospaced))
                Spacer()
                Picker("", selection: Binding(get: { model.config.chutneyMenuBarTagStyle },
                                              set: { model.setOption("chutney_menu_bar_tag_style", $0) })) {
                    Image(systemName: "1.square.fill").tag("square")
                    Image(systemName: "1.circle.fill").tag("circle")
                    Text("[1]").tag("text")
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
            .help("chutney_menu_bar_tag_style")
            HStack {
                Text("logo").font(.system(size: 10, design: .monospaced))
                Spacer()
                Picker("", selection: Binding(get: { model.config.chutneyMenuBarLogo },
                                              set: { model.setOption("chutney_menu_bar_logo", $0 == "off" ? "0" : $0) })) {
                    Text("colour").tag("color")
                    Text("mono").tag("mono")
                    Text("off").tag("off")
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
            .help("chutney_menu_bar_logo")
            Toggle("layout icon", isOn: Binding(get: { model.config.chutneyMenuBarLayout },
                                                set: { model.setOption("chutney_menu_bar_layout", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
                .help("chutney_menu_bar_layout")
            Toggle("key mode", isOn: Binding(get: { model.config.chutneyMenuBarMode },
                                         set: { model.setOption("chutney_menu_bar_mode", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
                .help("chutney_menu_bar_mode")
            HStack(spacing: 4) {
                header("Windows larger than their tile")
                Button { model.toggleFitInfo() } label: {
                    Image(systemName: model.fitInfo ? "info.circle.fill" : "info.circle")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(model.fitInfo ? "Hide the explanation" : "What these do")
            }
            if model.fitInfo { fitInfoText }
            Toggle("overlap warning", isOn: Binding(get: { model.config.chutneyOverlapWarning },
                                                    set: { model.setOption("chutney_overlap_warning", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
                .help("chutney_overlap_warning: the tag in orange in the menu bar")
            HStack {
                Text("fit layout").font(.system(size: 10, design: .monospaced))
                Spacer()
                Picker("", selection: Binding(get: { model.config.chutneyFitLayout },
                                              set: { model.setOption("chutney_fit_layout", String($0)) })) {
                    Text("off").tag(0)
                    Text("menu").tag(1)
                    Text("notify").tag(2)
                    Text("auto").tag(3)
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
            }
            .help("chutney_fit_layout: \"Fit layout\" in this menu, also a notification (a Fit button, or no room), or by itself")
            header("Fullscreen")
            Toggle("own tag", isOn: Binding(get: { model.config.chutneyFullscreenTag },
                                            set: { model.setOption("chutney_fullscreen_tag", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
                .help("chutney_fullscreen_tag: a window in macOS fullscreen has its own tag F1–F12, shown as its app's icon in the menu bar, as it has its own Space")
            HStack {
                Text("reduce motion").font(.system(size: 10, design: .monospaced))
                Spacer()
                Text(model.reduceMotion ? "on" : "off").font(.system(size: 10)).foregroundStyle(.secondary)
                Button("Settings…") { model.openMotionSettings() }
                    .controlSize(.mini)
            }
            .help("macOS's Reduce motion (Accessibility › Motion): Space changes fade instead of slide, all over macOS. Only System Settings can change it.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ s: String) -> some View { panelHeader(s) }

    /// Port extension: not in mango. What chutney_overlap_warning and chutney_fit_layout do.
    private var fitInfoText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Some apps will not be smaller than a set size. Such a window stays larger than its tile and covers the window next to it.")
            Text("overlap warning: its tag turns orange in the menu bar.")
            Text("fit layout: makes room for it with mango's resizewin. Its tile grows by what the window lacks, and the tiles beside it shrink. Offered only where the row (for width) or the column (for height) has room for it, counting the least size each window there has kept before. Otherwise the layout stays as it is.")
            VStack(alignment: .leading, spacing: 1) {
                Text("off: nothing")
                Text("menu: \"Fit layout: …\" at the top of this menu")
                Text("notify: also a notification with a Fit button, or one saying there is no room")
                Text("auto: fits by itself, at most 3 times per view")
            }
            .font(.system(size: 10, design: .monospaced))
            Text("Keys: chutney_overlap_warning, chutney_fit_layout. Bind the dispatcher chutney_fit_layout to fit from a key, whatever the level.")
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        label: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        panelSlider(model, title, value: value, in: range, step: step, label: label, commit: commit)
    }
}

@MainActor
func makeLayoutPanelItem(model: LayoutPanelModel) -> NSMenuItem {
    let host = NSHostingView(rootView: LayoutPanelView(model: model))
    host.frame.size = host.fittingSize
    model.host = host
    let item = NSMenuItem()
    item.view = host
    return item
}

extension LayoutKind {
    var usesMaster: Bool {
        switch self {
        case .tile, .rightTile, .centerTile, .verticalTile, .deck, .verticalDeck: return true
        default: return false
        }
    }
}

struct LayoutOption: Identifiable {
    enum Kind {
        case toggle(WritableKeyPath<Config, Bool>)
        case slider(WritableKeyPath<Config, Float>, ClosedRange<Double>, Double)
        case intSlider(WritableKeyPath<Config, Int>, ClosedRange<Double>, Double)
        case choice(WritableKeyPath<Config, Int>, [String])
    }
    var id: String { key }
    let key: String
    let title: String
    let kind: Kind
    var overruledBy: [WritableKeyPath<Config, Bool>] = []

    func disabled(_ c: Config) -> Bool { overruledBy.contains { c[keyPath: $0] } }

    static func options(for kind: LayoutKind) -> [LayoutOption] {
        switch kind {
        case .tile, .rightTile, .verticalTile:
            return [.init(key: "new_is_master", title: "new is master", kind: .toggle(\.newIsMaster))]
        case .centerTile:
            return [.init(key: "new_is_master", title: "new is master", kind: .toggle(\.newIsMaster)),
                    .init(key: "center_master_overspread", title: "master overspread", kind: .toggle(\.centerMasterOverspread)),
                    .init(key: "center_when_single_stack", title: "centre single stack", kind: .toggle(\.centerWhenSingleStack))]
        case .scroller, .verticalScroller:
            return [.init(key: "scroller_default_proportion", title: "default width",
                          kind: .slider(\.scrollerDefaultProportion, 0.1...1, 0.05)),
                    .init(key: "scroller_structs", title: "side room", kind: .intSlider(\.scrollerStructs, 0...200, 5)),
                    .init(key: "scroller_prefer_overspread", title: "prefer overspread", kind: .toggle(\.scrollerPreferOverspread)),
                    .init(key: "scroller_focus_center", title: "focus centre", kind: .toggle(\.scrollerFocusCenter),
                          overruledBy: [\.scrollerPreferOverspread]),
                    .init(key: "scroller_prefer_center", title: "prefer centre", kind: .toggle(\.scrollerPreferCenter),
                          overruledBy: [\.scrollerPreferOverspread, \.scrollerFocusCenter]),
                    .init(key: "scroller_ignore_proportion_single", title: "ignore single width",
                          kind: .toggle(\.scrollerIgnoreProportionSingle))]
        case .dwindle:
            return [.init(key: "dwindle_split_ratio", title: "split ratio", kind: .slider(\.dwindleSplitRatio, 0.05...0.95, 0.05)),
                    .init(key: "dwindle_horizontal_split", title: "side split", kind: .choice(\.dwindleHsplit, ["cursor", "right", "left"])),
                    .init(key: "dwindle_vertical_split", title: "top split", kind: .choice(\.dwindleVsplit, ["cursor", "below", "above"])),
                    .init(key: "dwindle_smart_split", title: "smart split", kind: .toggle(\.dwindleSmartSplit)),
                    .init(key: "dwindle_preserve_split", title: "preserve split", kind: .toggle(\.dwindlePreserveSplit)),
                    .init(key: "dwindle_smart_resize", title: "smart resize", kind: .toggle(\.dwindleSmartResize)),
                    .init(key: "dwindle_manual_split", title: "manual split", kind: .toggle(\.dwindleManualSplit))]
        case .monocle:
            return [.init(key: "monocle_tab_mode", title: "tab mode", kind: .toggle(\.monocleTabMode)),
                    .init(key: "monocle_no_border", title: "no border", kind: .toggle(\.monocleNoBorder)),
                    .init(key: "monocle_no_gap", title: "no gap", kind: .toggle(\.monocleNoGap))]
        case .deck, .verticalDeck:
            return [.init(key: "deck_tab_mode", title: "tab mode", kind: .toggle(\.deckTabMode))]
        default:
            return []
        }
    }
}

struct GapEditor: View {
    @ObservedObject var model: LayoutPanelModel
    private var special: Bool { model.gapSpecial }

    private var prefix: String { special ? "special_gap" : "gap" }
    private func value(_ kind: String) -> Int {
        let c = model.config
        switch (special, kind) {
        case (false, "inner_horizontal"): return c.gappih
        case (false, "inner_vertical"): return c.gappiv
        case (false, "outer_horizontal"): return c.gappoh
        case (false, "outer_vertical"): return c.gappov
        case (true, "inner_horizontal"): return c.specialGappih
        case (true, "inner_vertical"): return c.specialGappiv
        case (true, "outer_horizontal"): return c.specialGappoh
        default: return c.specialGappov
        }
    }
    private var allRound: String? {
        switch model.layout {
        case .grid: return "horizontal"
        case .verticalGrid: return "vertical"
        default: return nil
        }
    }

    private func set(_ kind: String, _ px: Int) {
        model.setGap("\(prefix)_\(kind)", px)
        guard allRound == nil else { return }
        let linked = kind.hasPrefix("inner") ? model.gapLinkInner : model.gapLinkOuter
        if linked {
            let other = kind.hasSuffix("horizontal") ? kind.replacingOccurrences(of: "horizontal", with: "vertical")
                                                     : kind.replacingOccurrences(of: "vertical", with: "horizontal")
            model.setGap("\(prefix)_\(other)", px)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
            if let d = allRound {
                Text("\(model.layout.name) uses one gap all round, as mango does: the \(d) ones.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            row("inner", linked: $model.gapLinkInner)
            row("outer", linked: $model.gapLinkOuter)
        }
    }

    private var preview: some View {
        Canvas { ctx, size in
            let k = size.width / max(1, model.screenWidth)
            func v(_ which: String, _ dir: String) -> CGFloat { CGFloat(value("\(which)_\(allRound ?? dir)")) * k }
            let ih = v("inner", "horizontal"), iv = v("inner", "vertical")
            let oh = v("outer", "horizontal"), ov = v("outer", "vertical")
            let screen = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: screen, cornerRadius: 4), with: .color(.primary.opacity(0.06)))
            let area = screen.insetBy(dx: min(oh, size.width / 4), dy: min(ov, size.height / 4))
            let mw = (area.width - ih) * 0.55
            let master = CGRect(x: area.minX, y: area.minY, width: mw, height: area.height)
            let sx = master.maxX + ih, sw = area.maxX - sx
            let sh = (area.height - iv) / 2
            let stack1 = CGRect(x: sx, y: area.minY, width: sw, height: sh)
            let stack2 = CGRect(x: sx, y: stack1.maxY + iv, width: sw, height: area.maxY - stack1.maxY - iv)
            for r in [master, stack1, stack2] where r.width > 1 && r.height > 1 {
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(model.accent.opacity(0.7)))
            }
        }
        .frame(height: 70)
    }

    private func row(_ which: String, linked: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let d = allRound {
                Text("\(prefix)_\(which)_\(d)").font(.system(size: 10, design: .monospaced))
                gapSlider("\(which)_\(d)", symbol: nil)
            } else {
            HStack(spacing: 4) {
                Text((model.gapSpecial ? "special_gap_" : "gap_") + which).font(.system(size: 10, design: .monospaced))
                Button { linked.wrappedValue.toggle() } label: {
                    Image(systemName: linked.wrappedValue ? "link" : "link.badge.plus")
                        .font(.system(size: 9))
                        .foregroundStyle(linked.wrappedValue ? model.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(linked.wrappedValue ? "horizontal and vertical together" : "horizontal and vertical apart")
                Spacer()
            }
            if linked.wrappedValue {
                gapSlider("\(which)_horizontal", symbol: nil)
            } else {
                gapSlider("\(which)_horizontal", symbol: "arrow.left.and.right")
                gapSlider("\(which)_vertical", symbol: "arrow.up.and.down")
            }
            }
        }
    }

    private func gapSlider(_ kind: String, symbol: String?) -> some View {
        let v = value(kind)
        let label = "\(v) px"
        let points = Binding<Double>(get: { Double(value(kind)) },
                                     set: { set(kind, Int($0.rounded())) })
        return HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 12) }
            Slider(value: points, in: 0...40, step: 1).controlSize(.small)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(model.accent)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct LayoutGrid: View {
    @ObservedObject var model: LayoutPanelModel
    private let columns = Array(repeating: GridItem(.fixed(74), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(LayoutKind.allCases, id: \.self) { kind in
                let on = kind == model.layout
                Button { model.setLayout(kind) } label: {
                    LayoutCell(kind: kind, selected: on, tint: model.accent, size: CGSize(width: 74, height: 44))
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    let ticked = model.inCircle(kind)
                    Button { model.toggleCircle(kind) } label: {
                        Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(on ? Color.white : ticked ? model.accent : Color.secondary)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(ticked ? "In circle_layout: switch_layout and the layout switcher" : "Not in circle_layout")
                }
            }
        }
    }
}
