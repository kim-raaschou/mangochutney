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
    /// The keys to start with, offered on a first start only: mango's, or the Mac set
    /// (config-mac.conf).
    @Published var offerKeys = false
    @Published var macKeys = false
    var onContinue: () -> Void = {}
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

    private static let skipKey = "skipScreenRecording"
    private var window: NSWindow?
    private var model: PermissionsModel?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var askedForCapture = false
    /// A first start's config, where the chosen keys are written.
    private var firstStartConfig: URL?

    public var state: PermissionState {
        PermissionState(accessibility: Permission.accessibility.isGranted,
                        screenRecording: Permission.screenRecording.isGranted,
                        skipScreenRecording: UserDefaults.standard.bool(forKey: Self.skipKey))
    }

    /// At launch, before mango writes its default config: on a first start the window also
    /// offers the keys to start with.
    public func offerKeysOnFirstStart(_ configURL: URL) {
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
        model.offerKeys = firstStartConfig != nil
        model.onContinue = { [weak self] in self?.continueOn() }
        model.onRestart = { [weak self] in self?.restart() }
        model.onQuit = { [weak self] in self?.quit() }
        self.model = model
        if window == nil {
            let host = NSHostingView(rootView: PermissionsView(model: model))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Mango Chutney Permissions"
            w.isReleasedWhenClosed = false
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
            if model.macKeys { ConfigFiles.useMacKeys(configURL: url) }
            firstStartConfig = nil
            model.offerKeys = false
        }
        window?.close()
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
                    Text("Mango Chutney needs your permission").font(.title3.bold())
                    Text("macOS asks you to allow these in System Settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

            Divider()

            VStack(spacing: 10) {
                ForEach(Permission.allCases) { p in
                    PermissionRow(permission: p, granted: model.state.isGranted(p), onRestart: model.onRestart)
                }
            }
            .padding(20)

            if model.offerKeys {
                Divider()
                KeysChoice(model: model)
                    .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Quit Mango Chutney", action: model.onQuit)
                Spacer()
                Button(model.state.allGranted ? "Done"
                       : model.state.accessibility ? "Continue without Screen Recording" : "Waiting for Accessibility…",
                       action: model.onContinue)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.state.accessibility)
            }
            .padding(16)
        }
        .frame(width: 560)
    }
}

/// The keys to start with, on a first start: mango's, or macOS's with mango's on Hyper.
private struct KeysChoice: View {
    @ObservedObject var model: PermissionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keys to start with").font(.headline)
            Picker("", selection: $model.macKeys) {
                option("mango", "mango's own keys: ⌥ arrows, ⌃ 1–9, ⌘ N … Some of them are also macOS shortcuts.")
                    .tag(false)
                option("macOS", "macOS's shortcuts stay as they are; mango's keys are on Hyper, Caps Lock held.")
                    .tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("Written to ~/.config/mango/config.conf when you continue. Hyper K lists every key.")
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
