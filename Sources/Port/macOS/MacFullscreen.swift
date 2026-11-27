import CoreGraphics
import Mango

/// What the macOS layer asks about a window in macOS fullscreen, and tells: whether it takes such a
/// window (onto a tag of its own), its state while macOS has it, what is saved for it, and the views
/// around it. NoFullscreenTag answers as plain mango, a window in fullscreen out of the layout;
/// chutney_fullscreen_tag hooks in its own (FullscreenTagHooks).
@MainActor
protocol MacFullscreenHooks: AnyObject {
    /// Whether a window in macOS fullscreen is taken onto a tag of its own.
    var takesWindows: Bool { get }
    /// A window mapped (`map`) while macOS has it in fullscreen (`taken`).
    func mapInFullscreen(_ c: Client, _ taken: Bool, map: () -> Void)
    /// Into macOS fullscreen: whether it is taken, rather than out of the layout.
    func enter(_ c: Client, discovered: Bool) -> Bool
    func leave(_ c: Client)
    /// After a Space change macOS has the window out of fullscreen, though it was told to go in.
    func notTaken(_ c: Client)
    /// macOS focused a window in fullscreen whose own view is not shown.
    func focusedByMacOS(_ c: Client)
    /// The active Space changed.
    func followSpace()
    /// mango said what it shows.
    func statusChanged()
    /// mango shows overview on `m`.
    func overviewShown(_ m: Monitor)
    /// mango tells the app it is fullscreen or not (client_notify_fullscreen).
    func notify(_ c: Client, _ fullscreen: Bool)
    /// mango's own window on `m`'s desktop Space focused, so macOS leaves a fullscreen Space.
    func focusSpaceAnchor(_ m: Monitor)
    /// The tags a window is saved on, and the views a monitor is saved with.
    func savedTags(_ c: Client) -> UInt32
    func savedView(_ m: Monitor) -> (now: UInt32, before: UInt32)
    /// In macOS fullscreen and taken: macOS places it.
    func native(_ c: Client) -> Bool
    /// Told to go into or out of macOS fullscreen, and macOS has yet to answer.
    func pending(_ c: Client) -> Bool
    /// While a fullscreen window's own view is shown the desktop's windows are in another Space.
    func desktopAway(_ c: Client) -> Bool
}

/// No window in macOS fullscreen is taken: it is out of the layout till it is back.
@MainActor
final class NoFullscreenTag: MacFullscreenHooks {
    var takesWindows: Bool { false }
    func mapInFullscreen(_ c: Client, _ taken: Bool, map: () -> Void) { map() }
    func enter(_ c: Client, discovered: Bool) -> Bool { false }
    func leave(_ c: Client) {}
    func notTaken(_ c: Client) {}
    func focusedByMacOS(_ c: Client) {}
    func followSpace() {}
    func statusChanged() {}
    func overviewShown(_ m: Monitor) {}
    func notify(_ c: Client, _ fullscreen: Bool) {}
    func focusSpaceAnchor(_ m: Monitor) {}
    func savedTags(_ c: Client) -> UInt32 { c.tags }
    func savedView(_ m: Monitor) -> (now: UInt32, before: UInt32) { (m.tagset[m.seltags], m.tagset[m.seltags ^ 1]) }
    func native(_ c: Client) -> Bool { false }
    func pending(_ c: Client) -> Bool { false }
    func desktopAway(_ c: Client) -> Bool { false }
}

/// A window mango manages in macOS fullscreen: read into it or out of it, away from the layout (or on
/// its own tag, chutney_fullscreen_tag) while there, and placed again once macOS has moved it back.
extension MacWindowSystem {
    /// In macOS fullscreen and taken onto a tag of its own (fullscreenHooks).
    func nativeFullscreen(_ c: Client) -> Bool { fullscreenHooks.native(c) }
    /// Told to go into or out of macOS fullscreen, and macOS has yet to answer.
    func fullscreenPending(_ c: Client) -> Bool { fullscreenHooks.pending(c) }
    /// In macOS fullscreen, or told to go in or out: macOS places it.
    func leftToMacOS(_ c: Client) -> Bool { fullscreenHooks.native(c) || fullscreenHooks.pending(c) }
    /// While a fullscreen window's own view is shown the desktop's windows are in another Space: they stay
    /// where they are.
    func fullscreenTagViewed(_ c: Client) -> Bool { fullscreenHooks.desktopAway(c) }

    /// macOS's fullscreen read again after a Space change: the resize that tells it can come while the
    /// port writes the window, and be missed.
    func windowFullscreen(id: CGWindowID, fullscreen: Bool) {
        windowFullscreenRead(id, fullscreen, late: true)
    }

    /// A window's macOS fullscreen as read: into it, or out of it, where that is news. Whether it was.
    /// `late`: read after a Space change, so macOS may show another Space by now.
    @discardableResult
    func windowFullscreenRead(_ id: CGWindowID, _ fullscreen: Bool, late: Bool = false) -> Bool {
        if !fullscreen, away[id]?.reasons.contains(.fullscreen) == true {
            backFromFullscreen(id)
            return true
        }
        guard let c = server.clientByWindowID(id) else { return false }
        if late, !fullscreen, fullscreenPending(c), !nativeFullscreen(c) {   // Port extension: chutney_fullscreen_tag
            fullscreenHooks.notTaken(c)
            return true
        }
        guard fullscreen != nativeFullscreen(c) else { return false }
        fullscreenChanged(c, fullscreen, late: late)
        return true
    }

    /// The active Space changed: each window back from fullscreen meanwhile is placed again, now that
    /// macOS has finished moving it.
    func spaceChanged() {
        fullscreenHooks.followSpace()   // Port extension: chutney_fullscreen_tag
        let back = fullscreenReturns
        fullscreenReturns.removeAll()
        for id in back { placeAgain(id) }
    }

    /// A window mango manages went into macOS fullscreen (out of the layout, or to its own tag) or out of it.
    func fullscreenChanged(_ c: Client, _ fullscreen: Bool, late: Bool = false) {
        if fullscreen {
            if fullscreenHooks.enter(c, discovered: late) { return }   // Port extension: chutney_fullscreen_tag
            goAway(c, .fullscreen)
        } else {
            fullscreenHooks.leave(c)   // Port extension: chutney_fullscreen_tag
            returnedFromFullscreen(c)
        }
    }

    /// An away window out of macOS fullscreen: back in the layout, and the app says which window has the keys.
    func backFromFullscreen(_ id: ClientID) {
        guard let c = away[id]?.client else { return }
        comeBack(id, .fullscreen)
        guard server.clientByWindowID(id) === c else { return }
        askFocus(c)
        returnedFromFullscreen(c)
    }

    /// macOS moves a window out of fullscreen until its Space change is done, which may come before or
    /// after this: it is placed now, and again at the next Space change.
    func returnedFromFullscreen(_ c: Client) {
        placeAgain(c.windowID)
        fullscreenReturns.insert(c.windowID)
    }

    /// The window's frame read again and its monitor's layout written.
    func placeAgain(_ id: ClientID) {
        guard let c = server.clientByWindowID(id), let m = c.mon else { return }
        if let real = windowServerFrame(c.windowID) {
            c.frame = real
            // macOS put it back where it stood before fullscreen: a window it shows is not parked
            if c.parked && !Hider.isParked(real, in: m.screen.frame) { shownByMacOS(c) }
        }
        server.arrange(m, false, false)
        // A window out of view was not parked while macOS had it in fullscreen; mango's scene is
        // unchanged, so it is parked now.
        showOrPark(c)
    }
}
