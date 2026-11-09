import CoreGraphics

package struct PortHooks {
    package var extraDispatchers: [String: @MainActor (MangoServer, Dispatch) -> String?] = [:]
    package var barsInsideBorder: (@MainActor (MangoServer) -> Bool)?
    package var ipcGets: [String: @MainActor (MangoServer) -> JSONValue] = [:]
    package var windowLeaving: (@MainActor (MangoServer, Client, [ClientID], ClientID?, [ClientID]) -> Void)?
    package var saveLayout: (@MainActor (MangoServer, Bool) -> Void)?
    package var restoreLayout: (@MainActor (MangoServer) -> Void)?
    package var clientFocused: (@MainActor (MangoServer, Client) -> Void)?
    package var configLoaded: [@MainActor (MangoServer) -> Void] = []

    package init() {}
}
