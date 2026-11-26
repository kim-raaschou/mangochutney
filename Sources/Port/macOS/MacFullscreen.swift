import CoreGraphics
import Mango

/// A window mango manages in macOS fullscreen: read into it or out of it, away from the layout (or on
/// its own tag, chutney_fullscreen_tag) while there, and placed again once macOS has moved it back.
extension MacWindowSystem {
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
            FullscreenTag.notTaken(server, c)
            return true
        }
        guard fullscreen != nativeFullscreen(c) else { return false }
        fullscreenChanged(c, fullscreen, late: late)
        return true
    }

    /// The active Space changed: each window back from fullscreen meanwhile is placed again, now that
    /// macOS has finished moving it.
    func spaceChanged() {
        FullscreenTag.followSpace(server)   // Port extension: chutney_fullscreen_tag
        let back = fullscreenReturns
        fullscreenReturns.removeAll()
        for id in back { placeAgain(id) }
    }

    /// A window mango manages went into macOS fullscreen (out of the layout, or to its own tag) or out of it.
    func fullscreenChanged(_ c: Client, _ fullscreen: Bool, late: Bool = false) {
        if fullscreen {
            if FullscreenTag.enter(server, c, discovered: late) { return }   // Port extension: chutney_fullscreen_tag
            goAway(c, .fullscreen)
        } else {
            FullscreenTag.leave(server, c)   // Port extension: chutney_fullscreen_tag
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
