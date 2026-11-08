import AppKit
import ApplicationServices
import CoreGraphics
import MangoPrivate

public enum AxUiElementWindowType: String {
    case window
    case dialog
    case popup

    static func new(isWindow: Bool, isDialog: () -> Bool) -> AxUiElementWindowType {
        switch true {
            case !isWindow: .popup
            case isDialog(): .dialog
            default: .window
        }
    }
}

public enum KnownBundleId: String, Equatable {
    case _1password = "com.1password.1password"
    case activityMonitor = "com.apple.ActivityMonitor"
    case alacritty = "org.alacritty"
    case braveBrowser = "com.brave.Browser"
    case chrome = "com.google.Chrome"
    case cleanshotx = "pl.maketheweb.cleanshotx"
    case codex = "com.openai.codex"
    case emacs = "org.gnu.Emacs"
    case finder = "com.apple.finder"
    case ghostty = "com.mitchellh.ghostty"
    case gimp = "org.gimp.gimp-2.10"
    case iphonesimulator = "com.apple.iphonesimulator"
    case iterm2 = "com.googlecode.iterm2"
    case kitty = "net.kovidgoyal.kitty"
    case outlook = "com.microsoft.Outlook"
    case photoBooth = "com.apple.PhotoBooth"
    case qutebrowser = "org.qutebrowser.qutebrowser"
    case screenstudio = "com.timpler.screenstudio"
    case slack = "com.tinyspeck.slackmacgap"
    case steam = "com.valvesoftware.steam.helper"
    case wezterm = "com.github.wez.wezterm"
    case wisprFlow = "com.electron.wispr-flow"
    case xcode = "com.apple.dt.Xcode"
    case zenBrowser = "app.zen-browser.zen"
    case zoom = "us.zoom.xos"

    case mozillaFirefox = "org.mozilla.firefox"
    case mozillaFirefoxDeveloperEdition = "org.mozilla.firefoxdeveloperedition"
    case mozillaFirefoxNightly = "org.mozilla.nightly"

    case vscode = "com.microsoft.VSCode"
    case vscodium = "com.vscodium"

    var isFirefox: Bool {
        self == .mozillaFirefox
            || self == .mozillaFirefoxDeveloperEdition
            || self == .mozillaFirefoxNightly
            || self == .zenBrowser
    }

    var isVscode: Bool {
        self == .vscode || self == .vscodium
    }
}

public enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
            case 0: .normalWindow
            case 3: .alwaysOnTopWindow
            default: .unknown(windowLevel: windowLevel)
        }
    }

    static func of(_ windowId: CGWindowID) -> MacOsWindowLevel? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowId) as? [[String: Any]],
              let dict = info.first, dict[kCGWindowIsOnscreen as String] as? Bool == true,
              let layer = dict[kCGWindowLayer as String] as? Int else { return nil }
        return .new(windowLevel: layer)
    }
}

public protocol ReadableAttr: Sendable {
    associatedtype T
    var getter: @Sendable (AnyObject) -> T? { get }
    var key: String { get }
}

public protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    func containingWindowId() -> CGWindowID?
}

public typealias WindowIdAndAxUiElementMock = (windowId: CGWindowID, ax: any AxUiElementMock)

public enum Ax {
    public struct ReadableAttrImpl<T>: ReadableAttr {
        public var key: String
        public var getter: @Sendable (AnyObject) -> T?
    }

    static let titleAttr = ReadableAttrImpl<String>(key: kAXTitleAttribute, getter: { $0 as? String })
    static let subroleAttr = ReadableAttrImpl<String>(key: kAXSubroleAttribute, getter: { $0 as? String })
    static let identifierAttr = ReadableAttrImpl<String>(key: kAXIdentifierAttribute, getter: { $0 as? String })
    static let enabledAttr = ReadableAttrImpl<Bool>(key: kAXEnabledAttribute, getter: { $0 as? Bool })
    static let isFocused = ReadableAttrImpl<Bool>(key: kAXFocusedAttribute, getter: { $0 as? Bool })
    static let isMainAttr = ReadableAttrImpl<Bool>(key: kAXMainAttribute, getter: { $0 as? Bool })
    static let focusedWindowAttr = ReadableAttrImpl<WindowIdAndAxUiElementMock>(key: kAXFocusedWindowAttribute, getter: windowOrNil)
    static let closeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(key: kAXCloseButtonAttribute, getter: castToAxUiElementMock)
    static let fullscreenButtonAttr = ReadableAttrImpl<any AxUiElementMock>(key: kAXFullScreenButtonAttribute, getter: castToAxUiElementMock)
    static let zoomButtonAttr = ReadableAttrImpl<any AxUiElementMock>(key: kAXZoomButtonAttribute, getter: castToAxUiElementMock)
    static let minimizeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(key: kAXMinimizeButtonAttribute, getter: castToAxUiElementMock)
}

@Sendable private func castToAxUiElementMock(_ a: AnyObject) -> (any AxUiElementMock)? {
    if let mock = a as? any AxUiElementMock { return mock }
    return CFGetTypeID(a as CFTypeRef) == AXUIElementGetTypeID() ? (a as! AXUIElement) : nil
}

@Sendable private func windowOrNil(_ any: AnyObject) -> WindowIdAndAxUiElementMock? {
    guard let potentialWindow = castToAxUiElementMock(any) else { return nil }
    return switch potentialWindow.containingWindowId() {
        case let windowId?: (windowId, potentialWindow)
        case nil: nil
    }
}

extension AXUIElement: AxUiElementMock {
    public func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        var raw: AnyObject?
        return AXUIElementCopyAttributeValue(self, attr.key as CFString, &raw) == .success
            ? raw.flatMap(attr.getter)
            : nil
    }

    public func containingWindowId() -> CGWindowID? {
        var cgWindowId = CGWindowID()
        return _AXUIElementGetWindow(self, &cgWindowId) == .success && cgWindowId != kCGNullWindowID
            ? cgWindowId
            : nil
    }
}

public extension AxUiElementMock {
    func isDialogHeuristic(
        _ id: KnownBundleId?,
        _ windowLevel: MacOsWindowLevel?,
    ) -> Bool {
        if id == ._1password && windowLevel != .normalWindow {
            return true
        }

        if id == .iphonesimulator {
            return true
        }

        if get(Ax.subroleAttr) != kAXStandardWindowSubrole &&
            id != .qutebrowser
        {
            return true
        }
        if id?.isFirefox == true && get(Ax.minimizeButtonAttr)?.get(Ax.enabledAttr) != true {
            return true
        }
        if id == .photoBooth { return true }
        if id == .ghostty {
            return get(Ax.fullscreenButtonAttr)?.get(Ax.enabledAttr) != true &&
                get(Ax.closeButtonAttr)?.get(Ax.enabledAttr) == true
        }
        if get(Ax.fullscreenButtonAttr)?.get(Ax.enabledAttr) != true &&
            id != .gimp &&

            id != .chrome &&

            id != .activityMonitor &&

            id != .alacritty &&
            id != .kitty &&
            id != .wezterm &&
            id != .qutebrowser &&
            id != .iterm2 &&
            id != .emacs &&
            id?.isVscode != true &&
            id != .steam
        {
            return true
        }
        return false
    }

    func isWindowHeuristic(
        axApp: any AxUiElementMock,
        _ id: KnownBundleId?,
        _ activationPolicy: NSApplication.ActivationPolicy,
        _ windowLevel: MacOsWindowLevel?,
    ) -> Bool {
        if windowLevel != .normalWindow &&
            (id == .slack || id == .chrome || id?.isFirefox == true || id == .braveBrowser || id == .screenstudio || id == .cleanshotx || id == .iterm2 || id == .outlook || id == .codex || id == .wisprFlow)
        {
            return false
        }

        if id == .ghostty && get(Ax.identifierAttr) == "com.mitchellh.ghostty.quickTerminal" {
            return false
        }

        lazy var fullscreenButton = get(Ax.fullscreenButtonAttr)

        if id == .xcode && get(Ax.identifierAttr) == "open_quickly" {
            return false
        }

        if id == .iterm2 && fullscreenButton == nil {
            return false
        }

        if activationPolicy == .accessory && get(Ax.closeButtonAttr) == nil && id != .steam {
            return false
        }

        if id == .emacs && get(Ax.subroleAttr) == kAXFloatingWindowSubrole {
            return false
        }

        if id?.isFirefox != true {
            return isWindowHeuristicOld(axApp: axApp, id)
        }

        return get(Ax.closeButtonAttr) != nil ||
            fullscreenButton != nil ||
            get(Ax.zoomButtonAttr) != nil ||
            get(Ax.minimizeButtonAttr) != nil ||

            get(Ax.isFocused) == true ||
            get(Ax.isMainAttr) == true ||
            axApp.get(Ax.focusedWindowAttr)?.windowId == self.containingWindowId() ||

            get(Ax.subroleAttr) == kAXStandardWindowSubrole
    }

    private func isWindowHeuristicOld(axApp: any AxUiElementMock, _ id: KnownBundleId?) -> Bool {
        lazy var subrole = get(Ax.subroleAttr)
        lazy var title = get(Ax.titleAttr) ?? ""

        if get(Ax.closeButtonAttr) == nil &&
            get(Ax.fullscreenButtonAttr) == nil &&
            get(Ax.zoomButtonAttr) == nil &&
            get(Ax.minimizeButtonAttr) == nil &&

            get(Ax.isFocused) == false &&
            get(Ax.isMainAttr) == false &&
            axApp.get(Ax.focusedWindowAttr)?.windowId != containingWindowId() &&

            subrole != kAXStandardWindowSubrole &&
            (title.isEmpty || title == "Window")
        {
            return false
        }
        return subrole == kAXStandardWindowSubrole ||
            subrole == kAXDialogSubrole ||
            subrole == kAXFloatingWindowSubrole ||
            id == .finder && subrole == "Quick Look"
    }

    func getWindowType(
        axApp: any AxUiElementMock,
        _ id: KnownBundleId?,
        _ activationPolicy: NSApplication.ActivationPolicy,
        _ windowLevel: MacOsWindowLevel?,
    ) -> AxUiElementWindowType {
        .new(
            isWindow: isWindowHeuristic(axApp: axApp, id, activationPolicy, windowLevel),
            isDialog: { isDialogHeuristic(id, windowLevel) },
        )
    }
}
