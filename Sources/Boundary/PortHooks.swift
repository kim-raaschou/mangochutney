import CoreGraphics

/// Port extension: not in mango. The few places where the port's own extensions join
/// mango's code, all here. Empty, mango behaves exactly as mango; each place mango's
/// code uses one is marked "Port extension: not in mango". The port fills them in one
/// place, at start (registerPortExtensions, Port/Extensions/Extensions.swift).
package struct PortHooks {
    /// Dispatchers mango does not have, by name (chutney_focus_app). Return an error, or nil.
    package var extraDispatchers: [String: @MainActor (MangoServer, Dispatch) -> String?] = [:]
    /// A border colour of the port's own for a window (chutney_floating_color); nil keeps mango's.
    package var borderColor: (@MainActor (MangoServer, Client) -> RGBA?)?
    /// The border's corner radius of the port's own (chutney_style: macOS's window corners);
    /// nil keeps mango's border_radius.
    package var borderRadius: (@MainActor (MangoServer, Client) -> CGFloat?)?
    /// How the bars are drawn: the decorate keys that are set, the rest left nil for the
    /// port's own look (chutney_style); nil keeps mango's defaults for the rest.
    package var overlayLook: (@MainActor (MangoServer, DecorateStyle) -> DecorateStyle?)?
    /// Borders around the focused window only (chutney_border_unfocused off); nil: mango's, around
    /// every window.
    package var focusedBorderOnly: (@MainActor (MangoServer) -> Bool)?
    /// Points per pixel of border_px and the gaps on a monitor (chutney_physical_pixels: 1 / the
    /// screen's scale); nil: mango's, one.
    package var pixelScale: (@MainActor (MangoServer, Monitor) -> CGFloat)?
    /// IPC `get` commands mango does not have (get binds, for mmsg binds): each one's reply,
    /// by command. Empty: mango's, none.
    package var ipcGets: [String: @MainActor (MangoServer) -> JSONValue] = [:]
    /// Windows that leave and come back (WindowMemory): a window leaving with its group
    /// (members, the one in view) and the client order, and the layout kept across a restart
    /// (saved on a change, `true` at quit; restored at start). nil: mango's, none.
    package var windowLeaving: (@MainActor (MangoServer, Client, [ClientID], ClientID?, [ClientID]) -> Void)?
    package var saveLayout: (@MainActor (MangoServer, Bool) -> Void)?
    package var restoreLayout: (@MainActor (MangoServer) -> Void)?
    /// A window was focused (client_focus): chutney_focus_app's "used last".
    package var clientFocused: (@MainActor (MangoServer, Client) -> Void)?
    /// The config was read (at start and on every reload): the port takes its own options.
    package var configLoaded: [@MainActor (MangoServer) -> Void] = []

    package init() {}
}
