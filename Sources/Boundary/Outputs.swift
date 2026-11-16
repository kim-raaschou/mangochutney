import CoreGraphics

// The screens macOS reports, as wlroots' output events: a new screen is handle_new_output, a
// screen that went away is handle_output_destroy, and every change ends in
// handle_output_layout_change, as wlr_output_layout's change event does. New screens come
// first, so a monitor is left when every screen is replaced at once.
package extension MangoServer {
    func rebuildMonitors(screens given: [Screen]? = nil) {
        let screens = given ?? system.screens
        guard !screens.isEmpty else { return }
        let gone = monitors.filter { m in !screens.contains { $0.displayID == m.screen.displayID } }
        for s in screens {
            if let m = monitors.first(where: { $0.screen.displayID == s.displayID }) {
                m.screen = s
            } else {
                handleNewOutput(s)
            }
        }
        for m in gone { handleOutputDestroy(m) }
        handleOutputLayoutChange()
    }
}
