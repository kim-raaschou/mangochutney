import AppKit
import ApplicationServices
import SwiftUI

/// The permissions the port asks macOS for (not in mango: a compositor needs none). One
/// window lists them, says what each is for, opens the right page of System Settings and
/// sees a grant as it lands, after Karabiner-Elements and OmniWM.
public enum Permission: CaseIterable, Identifiable {
    case accessibility
    case screenRecording

    public var id: Self { self }

    /// Windows cannot be managed without it.
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

    /// When the switch is on but the grant does not take.
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

    /// Puts Mango Chutney in the System Settings list and shows macOS's own prompt.
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

/// What is granted now, and what the window shows.
public struct PermissionState: Equatable {
    public var accessibility: Bool
    public var screenRecording: Bool
    /// The user chose to go on without Screen Recording; it is not asked for again.
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

    /// At launch: whenever Accessibility is missing, and for Screen Recording until the user
    /// has said to go on without it.
    public var showAtLaunch: Bool { !accessibility || (!screenRecording && !skipScreenRecording) }

    /// When a picture of a window is wanted (the overview): unless the user said no.
    public var showForCapture: Bool { !screenRecording && !skipScreenRecording }

    public var allGranted: Bool { accessibility && screenRecording }
}

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var state: PermissionState
    /// A first start: the window also asks for the Hyper key and offers Start at Login.
    @Published var firstStart = false
    /// The key held as Hyper (chutney_hyper_key), chosen on a first start; nil: not yet.
    @Published var hyperKey: String?
    /// The Hyper key pressed alone is Escape (chutney_hyper_tap).
    @Published var hyperTapEscape = false
    /// Offered on a first start: `mmsg service install` on Continue.
    @Published var startAtLogin = false
    /// After a first start's Continue: the welcome, with the first lines of config to try.
    @Published var welcome = false
    var onContinue: () -> Void = {}
    var onOpenStart: () -> Void = {}
    var onDone: () -> Void = {}
    var onRestart: () -> Void = {}
    var onQuit: () -> Void = {}

    init(state: PermissionState) { self.state = state }
}

/// The permissions window. It refreshes when System Settings reports a change or another
/// app is activated (leaving System Settings is one); no timer.
@MainActor
public final class Permissions {
    public static let shared = Permissions()

    /// The app's own restart and quit (set by the app at launch).
    public var restart: () -> Void = {}
    public var quit: () -> Void = { NSApp.terminate(nil) }
    /// The login service (`mmsg service install`; set by the app at launch).
    public var installLoginService: () -> Void = {}

    private static let skipKey = "skipScreenRecording"
    private var window: NSWindow?
    private var model: PermissionsModel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var askedForCapture = false
    /// A first start's config, where the chosen keys are written.
    private var firstStartConfig: URL?
    /// The first lines to try (start.conf), opened from the welcome.
    private var startConfig: URL?
    private static let gettingStarted =
        URL(string: "https://github.com/kim-raaschou/mangochutney/blob/main/docs/chutney/getting-started.md")!

    /// The docs' Getting Started: the two keys to remember, the menu bar, the config.
    public static func openGettingStarted() { NSWorkspace.shared.open(gettingStarted) }

    public var state: PermissionState {
        PermissionState(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted,
                        skipScreenRecording: UserDefaults.standard.bool(forKey: Self.skipKey))
    }

    /// At launch, before mango writes its default config: on a first start the window also
    /// asks for the Hyper key and offers Start at Login.
    public func prepareFirstStart(_ configURL: URL) {
        guard ConfigFiles.isFirstStart(configURL) else { return }
        firstStartConfig = configURL
    }

    /// At launch: shows the window when something is missing, or on a first start.
    public func showIfNeeded() {
        if state.showAtLaunch || firstStartConfig != nil { show() }
    }

    /// A picture of a window was wanted without Screen Recording: the window, once per run.
    public func askForCapture() {
        guard !askedForCapture, state.showForCapture else { return }
        askedForCapture = true
        show()
    }

    /// The window, from the menu or when something is missing.
    public func show() {
        let model = self.model ?? PermissionsModel(state: state)
        model.state = state
        model.firstStart = firstStartConfig != nil
        model.onContinue = { [weak self] in self?.continueOn() }
        model.onRestart = { [weak self] in self?.restart() }
        model.onQuit = { [weak self] in self?.quit() }
        model.onOpenStart = { [weak self] in self?.openStart() }
        model.onDone = { [weak self] in self?.window?.close() }
        self.model = model
        if window == nil {
            let host = NSHostingView(rootView: PermissionsView(model: model))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Mango Chutney Permissions"
            w.isReleasedWhenClosed = false
            // Above other apps' windows, System Settings among them, while the grants are given.
            // The app's own windows are never mango's clients, so it is never tiled.
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

    /// Reads the grants again (the window updates).
    public func refresh() {
        model?.state = state
    }

    private func continueOn() {
        if !state.screenRecording { UserDefaults.standard.set(true, forKey: Self.skipKey) }
        if let url = firstStartConfig, let model {
            ConfigFiles.ensure(url)
            ConfigFiles.setHyperKey(model.hyperKey ?? "caps_lock", tapEscape: model.hyperTapEscape, configURL: url)
            if model.startAtLogin { installLoginService() }
            firstStartConfig = nil
            startConfig = ConfigFiles.startURL(url)
            model.firstStart = false
            model.welcome = true
            window?.title = "Welcome to Mango Chutney"
            // The docs open behind the welcome, which floats above them.
            Self.openGettingStarted()
            return
        }
        window?.close()
    }

    /// The first lines to try, or the config when start.conf is gone.
    private func openStart() {
        guard let start = startConfig else { return }
        let fm = FileManager.default
        let url = fm.fileExists(atPath: start.path) ? start
            : start.deletingLastPathComponent().appendingPathComponent("config.conf")
        ConfigFiles.open(url)
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
                // The mango logo from the bundle (the app has no icon of its own).
                Image(nsImage: Bundle.main.url(forResource: "mango", withExtension: "svg")
                    .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.welcome ? "Remember two keys" : "Mango Chutney needs your permission")
                        .font(.title3.bold())
                    Text(model.welcome ? "Everything else is found from them. Getting Started is open in your browser."
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
                    Button("Open Your Config", action: model.onOpenStart)
                    Button("Done", action: model.onDone)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            } else {
                VStack(spacing: 10) {
                    ForEach(Permission.allCases) { p in
                        PermissionRow(permission: p, granted: model.state.isGranted(p), onRestart: model.onRestart)
                    }
                }
                .padding(20)

                if model.firstStart {
                    Divider()
                    FirstStartChoices(model: model)
                        .padding(20)
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

/// A first start's choices: Caps Lock as Hyper, and Start at Login.
private struct FirstStartChoices: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your Hyper key").font(.headline)
            Text("The key you hold for mango's keys; it acts as Control, Option and Command (⌃⌥⌘). macOS's own shortcuts stay as they are. Change it later in the menu bar (Learn › Hyper Key).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $model.hyperKey) {
                option("Caps Lock (recommended)", "Under your little finger. Caps Lock no longer types capitals.")
                    .tag(Optional("caps_lock"))
                option("Right ⌘", "The right Command key is Hyper; the left one stays Command.")
                    .tag(Optional("right_command"))
                option("Right ⌥", "The right Option key is Hyper; the left one stays Option and types special characters.")
                    .tag(Optional("right_option"))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Toggle("Pressed alone, it is Escape", isOn: $model.hyperTapEscape)
                .padding(.leading, 20)
                .disabled(model.hyperKey == nil)

            Text("Remember two keys").font(.headline)
                .padding(.top, 10)
            TwoKeys(hyperKey: model.hyperKey)
            Toggle("Start Mango Chutney at login", isOn: $model.startAtLogin)
                .padding(.top, 6)
            Text("Later from the menu bar (Start at Login) or with mmsg service install and uninstall.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func option(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// After a first start's Continue: the two keys to remember, then the config.
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
                    Text("Open Your Config shows the first lines to try: take away a #, save, and see the change. The menu bar's mango has the layouts, gaps and borders, and Learn.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

/// The two keys to remember, Hyper K and Hyper L, as key caps; on the first start and in
/// the welcome.
private struct TwoKeys: View {
    let hyperKey: String?

    private var hyper: String {
        switch hyperKey {
        case "caps_lock": "⇪"
        case "right_command": "⌘"
        case "right_option": "⌥"
        default: "Hyper"
        }
    }

    private var hyperText: String {
        switch hyperKey {
        case "caps_lock": "Hyper is Caps Lock held: it acts as Control, Option and Command (⌃⌥⌘)."
        case "right_command": "Hyper is the right ⌘ held: it acts as Control, Option and Command (⌃⌥⌘)."
        case "right_option": "Hyper is the right ⌥ held: it acts as Control, Option and Command (⌃⌥⌘)."
        default: "Hyper is the key you choose above."
        }
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

    /// One of the two keys: Hyper and the letter as key caps, then what it does.
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
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
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
                    // macOS's own prompt, whose button opens System Settings; the second
                    // button for when macOS does not prompt again.
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
