import AppKit
import ApplicationServices
import SwiftUI

public enum Permission: CaseIterable, Identifiable {
    case accessibility
    case screenRecording

    public var id: Self { self }

    var isRequired: Bool { self == .accessibility }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "macwindow.on.rectangle"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }

    var detail: String {
        switch self {
        case .accessibility:
            "Lets Mango Chutney see, focus, move and resize windows. Nothing is managed without it."
        case .screenRecording:
            "Pictures of the windows in the overview, and the switcher. "
                + "Without it the overview moves the windows themselves."
        }
    }

    var hint: String {
        switch self {
        case .accessibility:
            "Already on in the list? Remove Mango Chutney there with − and press Allow… again. "
                + "An old \"mango\" row can go too."
        case .screenRecording:
            "macOS asks to quit and reopen Mango Chutney once it is on; Restart does the same."
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    func request() {
        switch self {
        case .accessibility: _ = AX.requestTrust()
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        }
    }

    var settingsURL: URL? {
        let pane = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")
    }
}

public struct PermissionState: Equatable {
    public var accessibility: Bool
    public var screenRecording: Bool
    public var skipScreenRecording: Bool

    public init(accessibility: Bool, screenRecording: Bool, skipScreenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.skipScreenRecording = skipScreenRecording
    }

    public func isGranted(_ p: Permission) -> Bool {
        switch p {
        case .accessibility: accessibility
        case .screenRecording: screenRecording
        }
    }

    public var showAtLaunch: Bool { !accessibility || (!screenRecording && !skipScreenRecording) }

    public var showForCapture: Bool { !screenRecording && !skipScreenRecording }

    public var allGranted: Bool { accessibility && screenRecording }
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var state: PermissionState
    @Published var firstStart = false
    @Published var settings = false
    @Published var canSave = true
    @Published var settingsTab = "general"
    var look: AnyView?
    @Published var hyperKey: String? {
        didSet { if settings, hyperKey != oldValue { onChoice("chutney_hyper_key", hyperKey ?? "none") } }
    }
    @Published var hyperTap = "none" {
        didSet { if settings, hyperTap != oldValue { onChoice("chutney_hyper_tap", hyperTap) } }
    }
    @Published var startAtLogin = false {
        didSet { if settings, startAtLogin != oldValue { onStartAtLogin(startAtLogin) } }
    }
    var onChoice: (String, String) -> Void = { _, _ in }
    var onStartAtLogin: (Bool) -> Void = { _ in }
    @Published var welcome = false
    var onContinue: () -> Void = {}
    var onOpenConfig: () -> Void = {}
    var onDone: () -> Void = {}
    var onRestart: () -> Void = {}
    var onQuit: () -> Void = {}

    init(state: PermissionState) { self.state = state }
}

@MainActor
public final class Permissions {
    public static let shared = Permissions()

    public var restart: () -> Void = {}
    public var quit: () -> Void = { NSApp.terminate(nil) }
    public var installLoginService: () -> Void = {}
    public var firstStartDone: () -> Void = {}
    public struct Choices {
        public var hyperKey: String?, hyperTap: String, startAtLogin: Bool, canSave: Bool, configURL: URL

        public init(hyperKey: String?, hyperTap: String, startAtLogin: Bool, canSave: Bool, configURL: URL) {
            self.hyperKey = hyperKey; self.hyperTap = hyperTap; self.startAtLogin = startAtLogin; self.canSave = canSave
            self.configURL = configURL
        }
    }
    public var currentChoices: () -> Choices? = { nil }
    public var saveChoice: (String, String) -> Void = { _, _ in }
    public var setStartAtLogin: (Bool) -> Void = { _ in }
    public var lookView: () -> AnyView? = { nil }
    public var firstStartPending: Bool { firstStartConfig != nil }

    private static let skipKey = "skipScreenRecording"
    private var window: NSWindow?
    private var model: PermissionsModel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var askedForCapture = false
    private var firstStartConfig: URL?
    private var yourConfig: URL?
    private static let gettingStarted =
        URL(string: "https://github.com/kim-raaschou/mangochutney/blob/main/docs/guide.md#getting-started")!

    public static func openGettingStarted() { NSWorkspace.shared.open(gettingStarted) }
    static let guide = URL(string: "https://github.com/kim-raaschou/mangochutney/blob/main/docs/guide.md")!
    static let mangoDocs = URL(string: "https://mangowm.github.io/docs/")!

    public var state: PermissionState {
        PermissionState(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted,
                        skipScreenRecording: UserDefaults.standard.bool(forKey: Self.skipKey))
    }

    public func prepareFirstStart(_ configURL: URL) {
        guard ConfigFiles.isFirstStart(configURL) else { return }
        firstStartConfig = configURL
    }

    public func showIfNeeded() {
        if state.showAtLaunch || firstStartConfig != nil { show() }
    }

    public func askForCapture() {
        guard !askedForCapture, state.showForCapture else { return }
        askedForCapture = true
        show()
    }

    public func show() {
        let model = self.model ?? PermissionsModel(state: state)
        model.state = state
        model.firstStart = firstStartConfig != nil
        model.onContinue = { [weak self] in self?.continueOn() }
        model.onRestart = { [weak self] in self?.restart() }
        model.onQuit = { [weak self] in self?.quit() }
        model.onOpenConfig = { [weak self] in self?.openConfig() }
        model.onDone = { [weak self] in self?.window?.close() }
        self.model = model
        if window == nil {
            let host = NSHostingView(rootView: PermissionsView(model: model))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Mango Chutney Permissions"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.collectionBehavior = [.moveToActiveSpace]
            w.contentView = host
            w.center()
            window = w
        }
        observe()
        window?.makeKeyAndOrderFront(nil)
        if let w = window { NativeFocus.focusOwn(windowID: CGWindowID(w.windowNumber)) }
        NSApp.activate()
    }

    public func showSettings() {
        show()
        guard let model, firstStartConfig == nil else { return }
        let c = currentChoices()
        model.settings = false
        model.welcome = false
        model.hyperKey = c?.hyperKey
        model.hyperTap = c?.hyperTap ?? "none"
        model.startAtLogin = c?.startAtLogin ?? false
        model.canSave = c?.canSave ?? false
        yourConfig = c?.configURL
        model.onChoice = { [weak self] key, value in self?.saveChoice(key, value) }
        model.onStartAtLogin = { [weak self] on in self?.setStartAtLogin(on) }
        model.look = lookView()
        model.settings = true
        window?.title = "Mango Chutney Settings"
    }

    public func refresh() {
        model?.state = state
    }

    private func continueOn() {
        if !state.screenRecording { UserDefaults.standard.set(true, forKey: Self.skipKey) }
        if let url = firstStartConfig, let model {
            ConfigFiles.ensure(url)
            let key = model.hyperKey ?? "caps_lock"
            let quickPress = KeyboardOptions.hyperKey(key)?.original != nil
            ConfigFiles.setHyperKey(key, tap: quickPress ? model.hyperTap : "none", configURL: url)
            if model.startAtLogin { installLoginService() }
            firstStartConfig = nil
            yourConfig = url
            model.firstStart = false
            model.welcome = true
            window?.title = "Welcome to Mango Chutney"
            firstStartDone()
            Self.openGettingStarted()
            return
        }
        window?.close()
    }

    private func openConfig() {
        if let yourConfig { ConfigFiles.open(yourConfig) }
    }

    private func observe() {
        guard observers.isEmpty else { return }
        let check: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.window?.isVisible != true { self.stopObserving(); return }
                self.refresh()
            }
        }
        let dnc = DistributedNotificationCenter.default()
        let ws = NSWorkspace.shared.notificationCenter
        observers = [
            (dnc, dnc.addObserver(forName: Notification.Name("com.apple.accessibility.api"), object: nil,
                                  queue: .main, using: check)),
            (ws, ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                queue: .main, using: check)),
            (NotificationCenter.default, NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: check)),
        ]
    }

    private func stopObserving() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
    }
}

struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: Bundle.main.url(forResource: "mango", withExtension: "svg")
                    .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.welcome ? "Remember two keys"
                         : model.settings ? "Mango Chutney Settings" : "Mango Chutney needs your permission")
                        .font(.title3.bold())
                    Text(model.welcome ? "Everything else is found from them. Getting Started is open in your browser."
                         : model.settings ? "Permissions, your Hyper key and Start at Login, kept as you choose."
                         : "macOS asks you to allow these in System Settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            if model.welcome {
                Welcome(hyperKey: model.hyperKey)
                    .padding(20)

                Divider()

                HStack(spacing: 10) {
                    Spacer()
                    Button("Open Your Config", action: model.onOpenConfig)
                    Button("Done", action: model.onDone)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            } else {
                if model.settings, model.look != nil {
                    Picker("", selection: $model.settingsTab) {
                        Text("General").tag("general")
                        Text("Look").tag("look")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                }
                if model.settings, model.settingsTab == "look", let look = model.look {
                    look.padding(20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Permission.allCases) { p in
                            PermissionRow(permission: p, granted: model.state.isGranted(p), onRestart: model.onRestart)
                        }
                    }
                    .padding(20)

                    if model.firstStart || model.settings {
                        Divider()
                        FirstStartChoices(model: model)
                            .padding(20)
                    }
                    if model.settings {
                        Divider()
                        YourConfig(model: model)
                            .padding(20)
                    }

                }
                Divider()

                HStack(spacing: 10) {
                    Button("Quit Mango Chutney", action: model.onQuit)
                    Spacer()
                    Button(model.state.allGranted ? (model.firstStart ? "Continue" : "Done")
                           : model.state.accessibility ? "Continue without Screen Recording" : "Waiting for Accessibility…",
                           action: model.onContinue)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.state.accessibility || (model.firstStart && model.hyperKey == nil))
                }
                .padding(16)
            }
        }
        .frame(width: 560)
    }
}

private struct FirstStartChoices: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.settings ? "Your Hyper key" : "Choose your Hyper key").font(.headline)
            Text("One key becomes Hyper: held, it acts as Control, Option and Command (⌃⌥⌘), which no app uses, so mango's keys never take an app's shortcut. That key no longer does what it did."
                 + (model.settings ? " A choice here is kept in chutney_menu.conf and wins over config.conf." : " Change it later in Settings (⌘, in the menu bar)."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Hyper Key").gridColumnAlignment(.trailing)
                    Picker("", selection: $model.hyperKey) {
                        Text(model.settings ? "Not set (⌃⌥⌘ held)" : "Choose…").tag(String?.none)
                        Divider()
                        Text("Caps Lock (recommended)").tag(Optional("caps_lock"))
                        Divider()
                        ForEach(KeyboardOptions.hyperKeys.filter { $0.original == nil }, id: \.name) { k in
                            Text(k.label).tag(Optional(k.name))
                        }
                        Divider()
                        ForEach(KeyboardOptions.hyperKeys.filter { $0.name.hasPrefix("f") }, id: \.name) { k in
                            Text(k.label).tag(Optional(k.name))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let key = model.hyperKey.flatMap(KeyboardOptions.hyperKey), key.original != nil {
                    GridRow {
                        Text("Quick Press")
                        Picker("", selection: $model.hyperTap) {
                            Text("Does Nothing").tag("none")
                            Text(key.name == "caps_lock" ? "Toggles Caps Lock" : "Sends \(key.label)").tag("original")
                            Text("Escape").tag("escape")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
            .padding(.leading, 4)
            .disabled(model.settings && !model.canSave)

            Text("Remember two keys").font(.headline)
                .padding(.top, 10)
            TwoKeys(hyperKey: model.hyperKey)
            Toggle("Start Mango Chutney at login", isOn: $model.startAtLogin)
                .padding(.top, 6)
            Text(model.settings ? "Or with mmsg service install and uninstall."
                 : "Later in Settings, or with mmsg service install and uninstall.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct YourConfig: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your config").font(.headline)
            Text("Gaps, borders, colours, layouts, rules and keys are mango's, and they live in your config. mango's documentation has every one; the guide has what Mango Chutney adds.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open Your Config", action: model.onOpenConfig)
                Button("mango Documentation") { NSWorkspace.shared.open(Permissions.mangoDocs) }
                Button("Mango Chutney Guide") { NSWorkspace.shared.open(Permissions.guide) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Welcome: View {
    let hyperKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TwoKeys(hyperKey: hyperKey)
            Divider().padding(.vertical, 6)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your config is yours to change").font(.headline)
                    Text("Open Your Config: near its end are the first lines to try. Take away a #, save, and see the change. The menu bar's mango has the layouts, gaps and borders; Settings (⌘,) has these keys and the docs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

private struct TwoKeys: View {
    let hyperKey: String?

    private var key: KeyboardOptions.HyperKey? { hyperKey.flatMap(KeyboardOptions.hyperKey) }

    private var hyper: String { key?.symbol ?? "Hyper" }

    private var hyperText: String {
        guard let key else { return "Hyper is the key you choose above." }
        return "Hyper is \(key.label) held: it acts as Control, Option and Command (⌃⌥⌘)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            key("K", "Every key, searched by what you want to do",
                "Float, tag, layout: type it and press Return. When you do not know how, press Hyper K.")
            key("L", "The layouts",
                "Pick how the windows are arranged, with the arrows and Return.")
            Text(hyperText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }

    private func key(_ letter: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 6) {
                cap(hyper)
                cap(letter)
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func cap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)) }
            .shadow(color: .black.opacity(0.12), radius: 0, y: 2)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    let onRestart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(permission.title).font(.headline)
                    Text(permission.isRequired ? "Required" : "Optional")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(permission.isRequired ? Color.orange : Color.secondary)
                }
                Text(permission.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Text(permission.hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Label(granted ? "Allowed" : "Not allowed",
                      systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(granted ? Color.green : Color.orange)
                if !granted {
                    Button("Allow…") { permission.request() }
                    Button("Open Settings") {
                        if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                    }
                    if permission == .screenRecording {
                        Button("Restart", action: onRestart)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
