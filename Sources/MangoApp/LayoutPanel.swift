import AppKit
import SwiftUI
import Mango
import Port

/// Not in mango: the layout panel at the top of the menu bar menu (after mangobutter's
/// quickshell LayoutTweaks). It only sends mango's own dispatchers (setlayout, setmfact,
/// incnmaster, setoption for the gaps and border_px), as a bar does over IPC.
@MainActor
final class LayoutPanelModel: ObservableObject {
    weak var server: MangoServer?
    /// The menu item's view: its height follows the layout's options.
    weak var host: NSView?
    @Published var layout: LayoutKind = .tile
    @Published var animations = true
    /// The gap editor: the special tag's gaps rather than the tags', and horizontal and
    /// vertical tied together.
    /// The selected monitor's width in points: the gap preview is drawn to its scale.
    @Published var screenWidth: CGFloat = 1728
    @Published var gapSpecial = false
    @Published var gapLinkInner = true
    @Published var gapLinkOuter = true
    /// The config the layout options are read from (refreshed when the menu opens or one is set).
    @Published var config = Config()
    @Published var border: Double = 0
    @Published var mfact: Double = 0.55
    @Published var nmaster: Double = 1
    /// chutney_physical_pixels: the border and gap sliders are in points, in steps of one pixel (`pixel` points).
    @Published var physical = false
    @Published var pixel: Double = 1

    /// The focused monitor's current tag, read when the menu opens.
    private func resizeHost() {
        guard let h = host else { return }
        h.layoutSubtreeIfNeeded()
        let size = h.fittingSize
        if h.frame.size != size { h.frame.size = size }
    }

    func refresh() {
        defer {
            // The menu takes the panel's new height at once (a section came or went), and
            // again once SwiftUI has drawn it: no frame at the old size.
            resizeHost()
            DispatchQueue.main.async { [weak self] in self?.resizeHost() }
        }
        guard let server, let m = server.selectedMonitor else { return }
        conflicts = menuURL.map { MenuSave.conflicts(configURL: server.configURL, menuURL: $0) } ?? []
        layout = m.layout
        physical = server.config.chutneyPhysicalPixels
        pixel = physical ? 1 / max(1, Double(m.screen.scale)) : 1
        screenWidth = m.screen.workArea.width
        border = Double(server.config.borderpx) * pixel
        animations = server.config.animations
        config = server.config
        mfact = Double(m.current.settings.mfact)
        nmaster = Double(m.current.settings.nmaster)
    }

    private func send(_ name: String, _ args: String...) {
        server?.dispatch(Dispatch(name: name, args: args))
        refresh()
    }

    func setLayout(_ k: LayoutKind) {
        send("setlayout", k.name)
        saveTag("layout_name", k.name)
    }
    /// In mango's circle_layout: the layouts switch_layout goes round and the layout palette shows.
    /// Without circle_layout every layout is (mango: all of them).
    func inCircle(_ k: LayoutKind) -> Bool { CircleLayout.contains(config.circleLayout, k) }

    /// A layout ticked in or out of circle_layout (CircleLayout, as the layout palette's ticks).
    func toggleCircle(_ k: LayoutKind) {
        guard let server, let names = CircleLayout.toggled(config.circleLayout, k) else { return }
        CircleLayout.set(names, server: server)
        refresh()
    }

    /// One of the layout options, through mango's setoption.
    func setOption(_ key: String, _ value: String) { option(key, value) }

    /// A gap key (gap_inner_horizontal, special_gap_outer_vertical, …) in pixels, whole as
    /// mango's.
    func setGap(_ key: String, _ px: Int) {
        option(key, String(max(0, px)))
    }

    /// Port extension: not in mango. Where the panel saves its changes (chutney_menu_config),
    /// and where they overrule the config.
    @Published var conflicts: [MenuSave.Conflict] = []

    /// The panel's marking colour: mango's focuscolor, or macOS's accent (PortAccent).
    var accent: Color { PortAccent.color(config) }
    private var menuURL: URL? { server.flatMap { MenuSave.url($0.config, configURL: $0.configURL) } }

    /// mango setoption, then saved (chutney_menu_config).
    private func option(_ key: String, _ value: String) {
        server?.dispatch(Dispatch(name: "setoption", args: [key, value]))
        if let url = menuURL { MenuSave.set(key, value, in: url) }
        refresh()
    }

    /// A field of the current tag's tag_rule, saved (chutney_menu_config); the special tag
    /// has no tag_rule.
    private func saveTag(_ field: String, _ value: String) {
        guard let url = menuURL, let m = server?.selectedMonitor, m.curtag > 0 else { return }
        MenuSave.setTagRule(tag: m.curtag, field, value, in: url)
        refresh()
    }


    func setAnimations(_ on: Bool) {
        guard on != server?.config.animations else { return }
        option("animations", on ? "1" : "0")
    }
    func setBorder(_ v: Double) {
        let px = Int((v / pixel).rounded())   // border_px stays whole, as mango's
        guard px != server?.config.borderpx else { return }
        option("border_px", String(px))
    }
    func setMfact(_ v: Double) {
        guard abs(v - Double(server?.selectedMonitor?.current.settings.mfact ?? 0)) > 0.001 else { return }
        send("setmfact", String(format: "%.2f", 1 + v))   // > 1: absolute
        saveTag("master_factor", String(format: "%.2f", v))
    }
    func setNmaster(_ v: Double) {
        guard let m = server?.selectedMonitor else { return }
        let d = Int(v.rounded()) - m.current.settings.nmaster
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
            header("Desktop")
            GapEditor(model: model)
            slider("border_px", value: $model.border, in: 0...5, step: model.pixel,
                   label: model.physical
                       ? "\(Self.points(model.border)) pt (\(Int((model.border / model.pixel).rounded())) px)"
                       : "\(Int(model.border)) px",
                   commit: model.setBorder)
                .help("border width")
            let options = LayoutOption.options(for: model.layout)
            if model.layout.usesMaster || !options.isEmpty {
                header("Layout options")
            }
            // mfact and nmaster are the tag's (mango pertag), and only the layouts that read them show them.
            if model.layout.usesMaster {
                slider("mfact", value: $model.mfact, in: 0.1...0.9, step: 0.05, percent: true, commit: model.setMfact)
                    .help("master width (the tag's)")
                slider("nmaster", value: $model.nmaster, in: 0...6, step: 1, unit: "", commit: model.setNmaster)
                    .help("windows in the master area (the tag's)")
            }
            ForEach(options) { optionView($0) }
            header("Effects")
            // mangobutter's Blur and Shadows are left out: macOS cannot draw them on another app's window.
            Toggle("animations", isOn: Binding(get: { model.animations }, set: { model.setAnimations($0) }))
                .font(.system(size: 10, design: .monospaced))
                .toggleStyle(.switch)
                .controlSize(.mini)
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
            Toggle("layout icon", isOn: Binding(get: { model.config.chutneyMenuBarLayout },
                                                set: { model.setOption("chutney_menu_bar_layout", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
            Toggle("key mode", isOn: Binding(get: { model.config.chutneyMenuBarMode },
                                         set: { model.setOption("chutney_menu_bar_mode", $0 ? "1" : "0") }))
                .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
            // Where the menu's saved choices win over the config: a note, no lock.
            if !model.conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("The menu's choice wins over your config:").font(.system(size: 10, weight: .medium))
                    ForEach(model.conflicts.prefix(5)) { c in
                        Text("\(c.key) \(c.menuValue) (\(c.configFile):\(c.configLine) says \(c.configValue))")
                    }
                    if model.conflicts.count > 5 { Text("and \(model.conflicts.count - 5) more (mango -p)") }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .help("To give a key back to your config, delete its line in chutney_menu.conf")
            }
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
            slider(o.key, value: Binding(get: { model.config[keyPath: kp] }, set: { model.config[keyPath: kp] = $0 }),
                   in: range, step: step, label: String(format: step < 1 ? "%.2f" : "%.0f", model.config[keyPath: kp]),
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

    static func points(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", (v * 100).rounded() / 100)
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        unit: String = "", percent: Bool = false, label: String? = nil, commit: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, design: .monospaced))
                Spacer()
                Text(label ?? (percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue))\(unit)"))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(model.accent)
            }
            // Sent as it moves: inside an open menu the end of a drag is not reported reliably.
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .onChange(of: value.wrappedValue) { _, v in commit(v) }
        }
    }
}

/// The panel as a menu item.
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
    /// The layouts that read mfact and nmaster: mango's tile_core, right_tile_core,
    /// center_tile_core, deck_core, vertical_tile_core and vertical_deck_core (layout/).
    var usesMaster: Bool {
        switch self {
        case .tile, .rightTile, .centerTile, .verticalTile, .deck, .verticalDeck: return true
        default: return false
        }
    }
}

/// A layout's own config options as the panel shows them (mango's layout docs): set with
/// mango's setoption, read back from the config.
struct LayoutOption: Identifiable {
    enum Kind {
        case toggle(WritableKeyPath<Config, Bool>)
        case slider(WritableKeyPath<Config, Double>, ClosedRange<Double>, Double)
        case intSlider(WritableKeyPath<Config, Int>, ClosedRange<Double>, Double)
        case choice(WritableKeyPath<Config, Int>, [String])
    }
    var id: String { key }
    /// mango's key, shown; `title` says it in words (the help).
    let key: String
    let title: String
    let kind: Kind
    /// Overruled by a higher one (the scroller's centring: overspread > focus centre >
    /// prefer centre).
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

/// The gaps: mango's four (inner/outer, horizontal/vertical), for the normal tags or the
/// special tag, and smart_gaps. A small screen drawn with them, and a stepper for each;
/// the chain ties horizontal and vertical together.
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
    private func set(_ kind: String, _ px: Int) {
        model.setGap("\(prefix)_\(kind)", px)
        let linked = kind.hasPrefix("inner") ? model.gapLinkInner : model.gapLinkOuter
        if linked {
            let other = kind.hasSuffix("horizontal") ? kind.replacingOccurrences(of: "horizontal", with: "vertical")
                                                     : kind.replacingOccurrences(of: "vertical", with: "horizontal")
            model.setGap("\(prefix)_\(other)", px)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: $model.gapSpecial) {
                    Text("tags").tag(false)
                    Text("special tag").tag(true)
                }
                .pickerStyle(.segmented).controlSize(.mini).frame(width: 150)
                Spacer()
                Toggle("smart_gaps", isOn: Binding(get: { model.config.smartgaps },
                                              set: { model.setOption("smart_gaps", $0 ? "1" : "0") }))
                    .font(.system(size: 10, design: .monospaced)).toggleStyle(.switch).controlSize(.mini)
                    .help("no gaps with one window")
            }
            preview
            row("inner", linked: $model.gapLinkInner)
            row("outer", linked: $model.gapLinkOuter)
        }
    }

    /// A screen with a master and two stacked windows, drawn with the gaps at the screen's
    /// own scale (the preview's width for the monitor's), so they look as they will.
    private var preview: some View {
        Canvas { ctx, size in
            let k = size.width / max(1, model.screenWidth) * CGFloat(model.pixel)
            let ih = CGFloat(value("inner_horizontal")) * k, iv = CGFloat(value("inner_vertical")) * k
            let oh = CGFloat(value("outer_horizontal")) * k, ov = CGFloat(value("outer_vertical")) * k
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

    /// A row: one slider for horizontal and vertical together (linked), or one each.
    private func row(_ which: String, linked: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(which).font(.system(size: 10, design: .monospaced))
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

    /// A gap's slider, 0–40 points in steps of a pixel; sent as it moves.
    private func gapSlider(_ kind: String, symbol: String?) -> some View {
        let v = value(kind)
        let label = model.physical ? "\(LayoutPanelView.points(Double(v) * model.pixel)) pt" : "\(v) px"
        let points = Binding<Double>(get: { Double(value(kind)) * model.pixel },
                                     set: { set(kind, Int(($0 / model.pixel).rounded())) })
        return HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8)).foregroundStyle(.secondary).frame(width: 12) }
            Slider(value: points, in: 0...40, step: model.pixel).controlSize(.small)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(model.accent)
                .frame(width: 44, alignment: .trailing)
        }
    }
}


/// The layouts as a grid of their icons; a click sets the layout (mango setlayout), the
/// tick in the corner puts it in circle_layout (switch_layout and the layout palette).
struct LayoutGrid: View {
    @ObservedObject var model: LayoutPanelModel
    private let columns = Array(repeating: GridItem(.fixed(74), spacing: 6), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(LayoutKind.allCases, id: \.self) { kind in
                let on = kind == model.layout
                Button { model.setLayout(kind) } label: {
                    VStack(spacing: 3) {
                        LayoutIcon(kind: kind, selected: on, tint: model.accent)
                        // mango's name, smaller where it is long (vertical_scroller).
                        Text(kind.name)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 74, height: 44)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(on ? model.accent : Color.primary.opacity(0.06)))
                    .foregroundStyle(on ? Color.white : Color.primary)
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
                    .help(ticked ? "In circle_layout: switch_layout and the layout palette" : "Not in circle_layout")
                }
            }
        }
    }
}
