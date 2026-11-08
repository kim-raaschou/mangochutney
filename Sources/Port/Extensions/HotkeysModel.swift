import AppKit
import Mango

struct HotkeysContext: Equatable {
    var hasFocused = false
    var floating = false
    var fullscreen = false
    var maximized = false
    var global = false
    var overlay = false
    var layout = "tile"
    var viewedTags: Set<Int> = [1]
    var monitorCount = 1
    var minimizedCount = 0
    var overview = false
    var gaps = true
    var appSteps: [String: HotkeysAppStep] = [:]
}

struct HotkeysAppStep: Equatable {
    var rule: FocusAppRule
    var windows: Int
    var inApp: Bool
}

struct HotkeysWindow: Equatable {
    var id: ClientID
    var app: String
    var bundleID: String
    var title: String
    var tag: Int?
    var focused = false
    var appPath: String?
}

struct HotkeysApp: Equatable {
    var name: String
    var path: String
    var bundleID: String
    var lastUsed: Date?
    var useCount = 0
}

struct HotkeyRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case binding(dispatch: String, args: [String])
        case window(ClientID)
        case app(path: String)
    }

    let id: String
    var kind: Kind
    var section: String
    var keys: [String]
    var action: String
    var haystack = ""
    var state: String?
    var enabled = true
    var digits: [Int: [String]] = [:]
    var useCount = 0
    var iconPath: String?
    var appID: String?
    var title: String?
    var appName: String?
    var place: String?
    var next: String?

    var dispatch: String {
        if case .binding(let d, _) = kind { return d }
        return ""
    }

    var args: [String] {
        if case .binding(_, let a) = kind { return a }
        return []
    }

    var runnable: Bool { enabled && dispatch != "moveresize" && digits.isEmpty }
}

@MainActor
final class HotkeysModel: ObservableObject {
    enum Item: Equatable {
        case group(String, Int)
        case row(HotkeyRow)
    }

    @Published var query = "" { didSet { if query != oldValue { selection = 0; relayout() } } }
    @Published private(set) var openSection: String? { didSet { relayout() } }
    @Published var selection = 0
    private(set) var rows: [HotkeyRow] = []
    private(set) var folded: [String: HotkeyRow] = [:]
    private(set) var appRows: [HotkeyRow] = []
    private(set) var offeredRows: [HotkeyRow] = []
    private var places: [String: String] = [:]
    private(set) var usage: [String: Double] = [:]
    var run: ((HotkeyRow) -> Void)?
    var legend = ""
    var refuse: () -> Void = { NSSound.beep() }
    weak var field: NSTextField?

    var recentCount = 4
    var maxRows = 14
    var width: CGFloat = 680
    var look = HotkeysLook(macOS: false)
    var onLayout: ((Int) -> Void)?

    func load(_ shortcuts: [ShortcutRow], hyper: Modifiers, context: HotkeysContext = HotkeysContext(),
              windows: [HotkeysWindow] = [], apps: [HotkeysApp] = [], usage: [String: Double] = [:],
              appName: (String) -> String? = HotkeysModel.appName,
              appPath: (String) -> String? = HotkeysModel.appPath) {
        var entry: [String: [String]] = [:]
        for r in shortcuts where r.dispatch == "setkeymode" && r.args.first.map({ $0 != "default" }) == true
            && entry[r.args[0]] == nil {
            entry[r.args[0]] = Self.caps(r.keys, hyper: hyper)
        }
        var seen = Set<String>()
        places = Self.places(windows)
        rows = []
        let bound = Set(shortcuts.map(\.dispatch))
        let offered = Self.fractionArgument.subtracting(bound).sorted().map {
            ShortcutRow(mode: "default", keys: "", action: ShortcutFormatter.action(Dispatch(name: $0)), dispatch: $0, args: [])
        }
        for r in shortcuts + offered {
            let place = "\(r.mode)|\(r.keys)"
            defer { seen.insert(place) }
            if r.dispatch == "setkeymode", r.args.first == "default", seen.contains(place) { continue }
            var action = r.action
            var names: [String] = []
            if r.dispatch == "chutney_focus_app", let id = r.args.first {
                if let name = appName(id) {
                    action = "focus or open \(name)"
                    names.append(name)
                }
            }
            var keys = r.keys.isEmpty ? [] : Self.caps(r.keys, hyper: hyper)
            if let e = entry[r.mode] { keys = e + ["›"] + keys }
            let (state, enabled) = Self.evaluate(r.dispatch, r.args, context)
            var row = HotkeyRow(id: Self.usageKey(r), kind: .binding(dispatch: r.dispatch, args: r.args),
                                section: Self.section(r), keys: keys, action: action, state: state, enabled: enabled)
            if rows.contains(where: { $0.id == row.id }) {
                row = HotkeyRow(id: row.id + "|" + r.keys, kind: row.kind, section: row.section, keys: keys,
                                action: action, state: state, enabled: enabled)
            }
            if r.dispatch == "chutney_focus_app", let id = r.args.first {
                row.iconPath = appPath(id)
                row.appID = id
                row.place = places[id]
                row.next = context.appSteps[id.lowercased()].map {
                    Self.next($0, name: names.first ?? id, windows: windows, viewed: context.viewedTags)
                }
            }
            row.haystack = ([row.section, r.dispatch, Self.keywords(r.dispatch)] + names + keys + r.args)
                .joined(separator: " ").lowercased()
            rows.append(row)
        }
        offeredRows = rows.filter(\.keys.isEmpty)
        rows.removeAll(where: \.keys.isEmpty)
        foldDigitRuns()
        for w in windows {
            var row = HotkeyRow(id: "w|\(w.id)", kind: .window(w.id), section: "Windows",
                                keys: [w.tag.map { $0 == 0 ? "special" : "tag \($0)" } ?? "minimized"],
                                action: w.title.isEmpty || w.title == w.app ? w.app : "\(w.app): \(w.title)",
                                state: w.focused ? "●" : nil)
            row.iconPath = w.appPath
            row.appID = w.bundleID
            row.title = w.title.lowercased()
            row.appName = w.app.lowercased()
            row.haystack = [w.app, w.title, w.bundleID, "window switch go"].joined(separator: " ").lowercased()
            rows.append(row)
        }
        setApps(apps)
        self.usage = usage
        query = ""
        openSection = nil
        selection = 0
        relayout()
    }

    func setApps(_ apps: [HotkeysApp]) {
        let useCount = Dictionary(apps.map { ($0.bundleID, $0.useCount) }, uniquingKeysWith: max)
        var bound = Set<String>()
        for i in rows.indices where rows[i].dispatch == "chutney_focus_app" {
            guard let id = rows[i].args.first else { continue }
            bound.insert(id)
            rows[i].useCount = useCount[id] ?? 0
        }
        appRows = apps.filter { !bound.contains($0.bundleID) }.map { a in
            var row = HotkeyRow(id: "a|\(a.path)", kind: .app(path: a.path), section: "Launch", keys: [],
                                action: "open \(a.name)")
            row.haystack = [a.name, a.bundleID, "app open launch start"].joined(separator: " ").lowercased()
            row.useCount = a.useCount
            row.iconPath = a.path
            row.appID = a.bundleID
            row.place = places[a.bundleID]
            return row
        }
        if !query.isEmpty { relayout() }
    }

    static func next(_ s: HotkeysAppStep, name: String, windows: [HotkeysWindow], viewed: Set<Int>) -> String {
        switch s.rule {
        case .launch:
            return "start \(name)"
        case .focus where s.inApp && s.windows == 2:
            return "the other \(name) window"
        case .focus(let id):
            guard let tag = windows.first(where: { $0.id == id })?.tag, tag > 0, !viewed.contains(tag) else {
                return "go to \(name)"
            }
            return "go to \(name) on tag \(tag)"
        }
    }

    static func places(_ windows: [HotkeysWindow]) -> [String: String] {
        Dictionary(grouping: windows, by: \.bundleID).mapValues { ws in
            let tags = Set(ws.compactMap(\.tag))
            var parts: [String] = []
            let numbered = tags.filter { $0 > 0 }.sorted().map(String.init)
            if !numbered.isEmpty { parts.append("tag " + numbered.joined(separator: ", ")) }
            if tags.contains(0) { parts.append("special") }
            if ws.contains(where: { $0.tag == nil }) { parts.append("minimized") }
            return parts.joined(separator: " · ")
        }
    }

    private func foldDigitRuns() {
        var runs: [String: [Int]] = [:]
        var order: [String] = []
        for (i, r) in rows.enumerated() {
            guard case .binding(let d, let a) = r.kind, let last = r.keys.last, let n = Int(last),
                  (1...9).contains(n), a.first == last else { continue }
            let key = ([d] + r.keys.dropLast() + a.dropFirst()).joined(separator: "|")
            if runs[key] == nil { order.append(key) }
            runs[key, default: []].append(i)
        }
        folded = [:]
        var drop = Set<Int>()
        for key in order {
            guard let idx = runs[key], idx.count >= 2, let first = idx.first else { continue }
            let members = idx.map { rows[$0] }
            let nums = members.compactMap { $0.keys.last.flatMap { Int($0) } }
            let range = "\(nums.min()!)–\(nums.max()!)"
            var row = rows[first]
            let d0 = members[0].keys.last!
            if let r = row.action.range(of: d0, options: .backwards) { row.action.replaceSubrange(r, with: range) }
            row.keys[row.keys.count - 1] = range
            row.digits = Dictionary(uniqueKeysWithValues: zip(nums, members.map(\.args)))
            row.enabled = members.contains(where: \.enabled)
            let viewed = zip(nums, members).filter { $0.1.state == "●" }.map { String($0.0) }
            row.state = viewed.isEmpty ? nil : "● " + viewed.joined(separator: ",")
            row.haystack = members.map(\.haystack).joined(separator: " ")
            for m in members { folded[m.id] = m }
            rows[first] = row
            drop.formUnion(idx.dropFirst())
        }
        rows = rows.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    }

    static func usageKey(_ r: ShortcutRow) -> String {
        "b|\(r.mode)|\(r.dispatch)|\(r.args.joined(separator: ","))"
    }

    nonisolated static func appPath(_ bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
    }

    nonisolated static func appName(_ bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    var recent: [HotkeyRow] {
        (rows + Array(folded.values) + appRows).filter { usage[$0.id, default: 0] > 0 && $0.runnable }
            .sorted { (usage[$0.id, default: 0], $1.id) > (usage[$1.id, default: 0], $0.id) }
            .prefix(recentCount).map { $0 }
    }

    var items: [Item] {
        let (words, argument) = Self.splitQuery(query)
        if !words.isEmpty {
            let takes = { (r: HotkeyRow) in argument != nil && Self.takesValue(r) ? 1 : 0 }
            let found = (rows + offeredRows + appRows).enumerated().compactMap { i, r -> (HotkeyRow, Double, Int)? in
                guard let s = Self.score(r, words) else { return nil }
                let used = min(2, usage[r.id, default: 0] / 2) + min(1, Double(r.useCount).squareRoot() / 10)
                return (r, s + used, i)
            }
            let apps = Set(found.compactMap { f -> String? in
                if case .window = f.0.kind { return nil }
                return f.0.appID
            })
            return found.filter { f in
                guard case .window = f.0.kind, let app = f.0.appID, apps.contains(app) else { return true }
                let split = { (s: String?) in (s ?? "").split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }
                let name = split(f.0.appName)
                let own = split(f.0.title).filter { !name.contains($0) }
                let inOwn = { (w: String) in own.contains { $0.hasPrefix(w) } }
                return words.contains(where: inOwn) && words.allSatisfy { w in inOwn(w) || name.contains { $0.hasPrefix(w) } }
            }
            .sorted { ($0.0.enabled ? 1 : 0, takes($0.0), $0.1, -$0.2) > ($1.0.enabled ? 1 : 0, takes($1.0), $1.1, -$1.2) }
            .map { Item.row($0.0) }
        }
        if let s = openSection {
            let inGroup = rows.filter { $0.section == s }
            return (inGroup.filter(\.enabled) + inGroup.filter { !$0.enabled }).map(Item.row)
        }
        var counts: [String: Int] = [:]
        for r in rows { counts[r.section, default: 0] += 1 }
        let groups = counts.keys.sorted { (Self.rank($0), $0) < (Self.rank($1), $1) }.map { Item.group($0, counts[$0]!) }
        return recent.map(Item.row) + groups
    }

    struct Page: Equatable {
        var items: [Item]
        var columns = 1
        var more = 0
        var rows: Int { columns == 2 ? (items.count + 1) / 2 : items.count }
    }

    var page: Page {
        let all = items
        if all.count <= maxRows { return Page(items: all) }
        if !query.isEmpty { return Page(items: Array(all.prefix(maxRows)), more: all.count - maxRows) }
        let cap = maxRows * 2
        return Page(items: Array(all.prefix(cap)), columns: 2, more: max(0, all.count - cap))
    }

    private func relayout() { onLayout?(page.rows) }

    func move(_ by: Int) {
        let n = page.items.count
        guard n > 0 else { return }
        selection = (selection + by % n + n) % n
    }

    func moveColumn(_ by: Int) -> Bool {
        let p = page
        guard p.columns == 2 else { return false }
        let target = selection + by * p.rows
        guard target >= 0, (selection < p.rows) == (by > 0) else { return false }
        selection = min(target, p.items.count - 1)
        return true
    }

    static func splitQuery(_ q: String) -> (words: [String], argument: Double?) {
        var words: [String] = [], argument: Double?
        for w in q.lowercased().split(separator: " ").map(String.init) {
            if let i = w.lastIndex(of: ":"), let v = Double(w[w.index(after: i)...]), v.isFinite {
                argument = v
            } else {
                words.append(w)
            }
        }
        return (words, argument)
    }

    static let fractionArgument: Set<String> = ["set_proportion", "chutney_set_proportion_all"]

    static func takesValue(_ r: HotkeyRow) -> Bool {
        guard case .binding(let d, _) = r.kind else { return false }
        return fractionArgument.contains(d)
    }

    func typedArguments(_ r: HotkeyRow) -> [String]? {
        guard Self.takesValue(r), case .binding(_, var args) = r.kind,
              var v = Self.splitQuery(query).argument, v > 0 else { return nil }
        if v > 1 { v /= 100 }
        let s = String(format: "%g", min(max(v, 0.1), 1))
        if args.isEmpty { args = [s] } else { args[0] = s }
        return args
    }

    var selectedRow: HotkeyRow? {
        let shown = page.items
        guard shown.indices.contains(selection), case .row(let r) = shown[selection] else { return nil }
        return r
    }

    func enter() {
        let shown = page.items
        guard shown.indices.contains(selection) else { return }
        switch shown[selection] {
        case .group(let s, _): open(s)
        case .row(let r): if r.runnable { run?(r) } else { refuse() }
        }
    }

    func digit(_ n: Int) -> Bool {
        guard let r = selectedRow, let args = r.digits[n] else { return false }
        let id = folded.values.first { $0.args == args && $0.dispatch == r.dispatch }?.id ?? r.id
        let one = HotkeyRow(id: id, kind: .binding(dispatch: r.dispatch, args: args), section: r.section,
                        keys: r.keys, action: r.action, state: nil, enabled: r.enabled)
        if one.runnable { run?(one) } else { refuse() }
        return true
    }

    func openSelected() -> Bool {
        let shown = page.items
        guard shown.indices.contains(selection), case .group(let s, _) = shown[selection] else { return false }
        open(s)
        return true
    }

    func open(_ s: String) {
        openSection = s
        selection = 0
    }

    func back() -> Bool {
        guard let s = openSection else { return false }
        openSection = nil
        selection = page.items.firstIndex(of: .group(s, rows.filter { $0.section == s }.count)) ?? 0
        return true
    }

    func escape() -> Bool {
        if !query.isEmpty { query = ""; return true }
        return back()
    }

    static let masterLayouts: Set<String> = ["tile", "right_tile", "center_tile", "vertical_tile", "deck", "vertical_deck"]
    static let scrollerLayouts: Set<String> = ["scroller", "vertical_scroller"]

    static func evaluate(_ dispatch: String, _ args: [String], _ c: HotkeysContext) -> (state: String?, enabled: Bool) {
        let a0 = args.first ?? ""
        let onOff = { (b: Bool) in b ? "on" : "off" }
        switch dispatch {
        case "togglefloating": return (c.hasFocused ? onOff(c.floating) : nil, c.hasFocused)
        case "togglefullscreen", "togglefakefullscreen": return (c.hasFocused ? onOff(c.fullscreen) : nil, c.hasFocused)
        case "togglemaximizescreen": return (c.hasFocused ? onOff(c.maximized) : nil, c.hasFocused)
        case "toggleglobal": return (c.hasFocused ? onOff(c.global) : nil, c.hasFocused)
        case "toggleoverlay": return (c.hasFocused ? onOff(c.overlay) : nil, c.hasFocused)
        case "killclient", "minimized", "tag", "tagsilent", "toggletag", "tagtoleft", "tagtoright", "move_client",
             "exchange_client", "zoom", "movewin", "resizewin", "smartmovewin", "smartresizewin", "centerwin",
             "tag_special_tag", "focusid":
            return (nil, c.hasFocused)
        case "setlayout": return (a0 == c.layout ? "●" : nil, true)
        case "scroller_stack", "set_proportion", "switch_proportion_preset", "chutney_set_proportion_all":
            return (nil, c.hasFocused && scrollerLayouts.contains(c.layout))
        case "dwindle_toggle_split_direction", "dwindle_split_horizontal", "dwindle_split_vertical",
             "dwindle_toggle_current_split":
            return (nil, c.layout == "dwindle")
        case "incnmaster", "setmfact": return (nil, masterLayouts.contains(c.layout))
        case "view": return (Int(a0).map { c.viewedTags.contains($0) } == true ? "●" : nil, true)
        case "focusmon", "tagmon", "tagcrossmon", "viewcrossmon":
            return (nil, c.monitorCount > 1 && (dispatch != "tagmon" || c.hasFocused))
        case "restore_minimized": return (c.minimizedCount > 0 ? "\(c.minimizedCount)" : nil, c.minimizedCount > 0)
        case "togglegaps": return (onOff(c.gaps), true)
        case "toggleoverview": return (onOff(c.overview), true)
        case "enteroverview": return (nil, !c.overview)
        case "leaveoverview": return (nil, c.overview)
        default: return (nil, true)
        }
    }

    static func score(_ r: HotkeyRow, _ words: [String]) -> Double? {
        let action = r.action.lowercased()
        let actionWords = action.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let restWords = r.haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var total = 0.0
        for w in words {
            if actionWords.contains(where: { $0.hasPrefix(w) }) { total += 4 }
            else if action.contains(w) { total += 3 }
            else if restWords.contains(where: { $0.hasPrefix(w) }) { total += 2 }
            else if r.haystack.contains(w) { total += 1 }
            else if w.count >= 3, (actionWords + restWords).contains(where: { isSubsequence(w, of: $0) }) { total += 0.5 }
            else { return nil }
        }
        return total
    }

    static func isSubsequence(_ w: String, of s: String) -> Bool {
        var it = s.makeIterator()
        return w.allSatisfy { c in
            while let x = it.next() { if x == c { return true } }
            return false
        }
    }

    static func keywords(_ dispatch: String) -> String {
        switch dispatch {
        case "view", "toggleview", "comboview", "viewtoleft", "viewtoright", "viewtoleft_have_client",
             "viewtoright_have_client", "viewprev_have_client", "viewnext_have_client":
            return "workspace desktop switch go"
        case "tag", "tagsilent", "toggletag", "tagtoleft", "tagtoright": return "workspace desktop move send"
        case "killclient": return "close quit kill"
        case "togglefloating", "toggle_all_floating": return "float tile"
        case "togglefullscreen", "togglefakefullscreen": return "full screen"
        case "togglemaximizescreen": return "maximize zoom full"
        case "focusdir", "focusstack", "focuslast", "focus_window_or_workspace": return "switch go select window"
        case "move_client", "exchange_client", "zoom": return "move swap window"
        case "movewin", "smartmovewin", "centerwin": return "move position window"
        case "resizewin", "smartresizewin", "setmfact", "set_proportion", "switch_proportion_preset": return "resize size width"
        case "chutney_set_proportion_all": return "resize size width all every"
        case "spawn", "spawn_shell", "spawn_on_empty", "chutney_focus_app": return "app open launch start run"
        case "setlayout", "switch_layout": return "layout arrange"
        case "toggleoverview", "enteroverview", "overcircle": return "expose mission control all windows"
        case "togglejump": return "jump hint label window"
        case "switcher": return "switch alt tab windows"
        case "minimized", "restore_minimized": return "hide minimize"
        case "toggle_scratchpad", "toggle_named_scratchpad": return "scratchpad hide show"
        case "focusmon", "tagmon": return "monitor screen display"
        case "incgaps", "togglegaps": return "gap spacing"
        case "reload_config": return "config settings"
        case "quit": return "exit"
        case "setkeymode": return "mode"
        case "chutney_toggle_hotkeys_palette": return "help keys shortcuts hotkeys"
        default: return ""
        }
    }

    static let order = ["Windows", "Apps", "Focus", "Move & swap", "Tags", "Layout", "Window",
                        "Mouse & trackpad", "mango"]

    static func rank(_ s: String) -> Int { order.firstIndex(of: s) ?? order.count }

    static func section(_ r: ShortcutRow) -> String {
        if ["drag", "scroll", "swipe", "click"].contains(where: r.keys.contains) { return "Mouse & trackpad" }
        switch r.dispatch {
        case "toggleoverview", "enteroverview", "leaveoverview", "overcircle": return "Windows"
        case "spawn", "spawn_shell", "spawn_on_empty", "chutney_focus_app": return "Apps"
        case "focusdir", "focus_window_or_workspace", "focusstack", "focuslast", "togglejump", "switcher",
             "focusmon", "viewcrossmon": return "Focus"
        case "move_client", "exchange_client", "zoom", "smartmovewin", "smartresizewin", "movewin", "resizewin",
             "centerwin", "scroller_stack", "tagmon", "tagcrossmon": return "Move & swap"
        case "view", "toggleview", "tag", "tagsilent", "toggletag", "viewtoleft", "viewtoright", "viewtoleft_have_client",
             "viewtoright_have_client", "viewprev_have_client", "viewnext_have_client", "tagtoleft", "tagtoright",
             "toggle_special_tag", "tag_special_tag", "comboview": return "Tags"
        case "switch_layout", "setlayout", "incnmaster", "setmfact", "incgaps", "togglegaps", "switch_proportion_preset",
             "set_proportion", "chutney_set_proportion_all", "dwindle_toggle_split_direction": return "Layout"
        case "togglefloating", "toggle_all_floating", "togglefullscreen", "togglefakefullscreen", "togglemaximizescreen",
             "toggleglobal", "toggleoverlay", "killclient", "minimized", "restore_minimized", "toggle_scratchpad",
             "toggle_named_scratchpad": return "Window"
        default: return "mango"
        }
    }

    static func icon(_ section: String) -> String {
        switch section {
        case "Windows": return "macwindow.on.rectangle"
        case "Launch": return "arrow.up.forward.app"
        case "Apps": return "square.grid.2x2"
        case "Focus": return "scope"
        case "Move & swap": return "arrow.up.and.down.and.arrow.left.and.right"
        case "Tags": return "number"
        case "Monitors": return "display.2"
        case "Layout": return "rectangle.split.3x1"
        case "Window": return "macwindow"
        case "Mouse & trackpad": return "computermouse"
        default: return "gearshape"
        }
    }

    static func caps(_ keys: String, hyper: Modifiers) -> [String] {
        let parts = keys.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].allSatisfy({ "⌃⌥⇧⌘".contains($0) }) else { return [keys] }
        var mods = Set(parts[0])
        let hyperSymbols = Set(symbols(hyper))
        var out: [String] = []
        if !hyperSymbols.isEmpty, hyperSymbols.isSubset(of: mods) {
            out.append("Hyper")
            mods.subtract(hyperSymbols)
        }
        out += "⌃⌥⇧⌘".filter(mods.contains).map(String.init)
        return out + [parts[1]]
    }

    static func symbols(_ m: Modifiers) -> String {
        var s = ""
        if m.contains(.ctrl) { s += "⌃" }
        if m.contains(.alt) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.superKey) { s += "⌘" }
        return s
    }
}

enum HotkeysUsage {
    struct Entry: Codable {
        var count: Double
        var last: Date
    }

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mango", isDirectory: true)
        return dir.appendingPathComponent("hotkeys-usage.json")
    }

    static func read(_ url: URL = url) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    static func scores(_ entries: [String: Entry], now: Date = Date()) -> [String: Double] {
        entries.mapValues { e in e.count / (1 + max(0, now.timeIntervalSince(e.last)) / (7 * 86400)) }
    }

    static func record(_ id: String, at now: Date = Date(), url: URL = url) {
        var all = read(url)
        let old = all[id]
        let faded = old.map { $0.count / (1 + max(0, now.timeIntervalSince($0.last)) / (7 * 86400)) } ?? 0
        all[id] = Entry(count: faded + 1, last: now)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url, options: .atomic) }
    }
}

@MainActor
public enum ModifierLegend {
    public static func text(_ config: Config) -> String {
        let hyper = Modifiers.parse(config.chutneyHyperModifier, hyperModifier: "").map(HotkeysModel.symbols) ?? ""
        let caps = config.xkbRulesOptions.lowercased().split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces) == "caps:hyper" }
        let key = KeyboardOptions.hyperKey(config.chutneyHyperKey).map { " or \($0.label)" }
            ?? (caps ? " or Caps Lock" : "")
        return "Super ⌘   Hyper \(hyper)" + key
    }
}
