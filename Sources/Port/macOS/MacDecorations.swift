import AppKit
import Mango

/// mango's borders and bars as the port shows them: drawn where the windows stand on the screen (not
/// where mango has written them, till their apps answer), and shown again when an app answers.
extension MacWindowSystem {
    /// The borders and bars mango last drew, shown again where the windows stand now: an app answered,
    /// and nothing of mango's changed.
    func showAgain() {
        showBorders()
        if let d = drawnTabBars { showTabBars(d.strips, style: d.style) }
        if let d = drawnGroupBars { showGroupBars(d.strips, style: d.style) }
    }

    func showBorders() {
        let specs = MacOSAppearance.borders(shownBorders(drawnBorders), server.config)
        borders.update(specs)
        for c in server.clientsAll where c.mac.placed.offEdge { panels.setEdgePlateBorder(c.windowID, plateBorder(c)) }
    }

    /// The borders macOS shows now: mango's, around the window where it stands. A parked window has
    /// none, and a window coming back from parking gets its border when the app has moved it
    /// (comingBack). Port extension: chutney_fullscreen_tag. No border for a window in its own
    /// fullscreen Space.
    func shownBorders(_ specs: [BorderSpec]) -> [BorderSpec] {
        specs.compactMap { s in
            guard let c = server.clientByWindowID(s.id) else { return s }
            if c.parked || leftToMacOS(c) || c.mac.placed.comingBack { return nil }
            guard let d = lag(c) else { return nil }
            var s = s
            s.frame = CGRect(x: s.frame.minX + d.dx, y: s.frame.minY + d.dy,
                             width: s.frame.width + d.dw, height: s.frame.height + d.dh)
            return s
        }
    }

    /// How far the window as macOS shows it is from mango's box this frame (c->animation.current without
    /// the border): origin and size differences, a smaller window's negative (no CGRect, which would read
    /// them as a rect of its own).
    struct Lag: Equatable {
        var dx: CGFloat, dy: CGFloat, dw: CGFloat, dh: CGFloat
    }

    /// The window's lag: till its app has answered, where the app last put it; then, standing still, where
    /// it stands (an app may refuse its size); while it animates, none. Nil out of view.
    func lag(_ c: Client) -> Lag? {
        let box = c.animation.current.insetBy(dx: c.bw, dy: c.bw)
        let shown: CGRect
        if !c.mac.placed.inSync {
            guard let a = c.mac.placed.applied else { return nil }
            shown = a
        } else if c.animation.running {
            return Lag(dx: 0, dy: 0, dw: 0, dh: 0)
        } else {
            shown = c.frame
        }
        return Lag(dx: shown.minX - box.minX, dy: shown.minY - box.minY, dw: shown.width - box.width, dh: shown.height - box.height)
    }

    /// A strip moves with its window's border (lag): bars and border lie together. A parked window's tab
    /// bar is not shown.
    func followingWindows(_ strips: [TabStrip], tabs: Bool) -> [TabStrip] {
        strips.compactMap { strip in
            guard let c = server.clientByWindowID(strip.above) else { return strip }
            if tabs && c.parked { return nil }
            guard let d = lag(c), d.dx != 0 || d.dy != 0 else { return strip }
            var s = strip
            s.frame.origin.x += d.dx
            s.frame.origin.y += d.dy
            for i in s.segments.indices {
                s.segments[i].frame.origin.x += d.dx
                s.segments[i].frame.origin.y += d.dy
            }
            return s
        }
    }

    func showTabBars(_ strips: [TabStrip], style: TabStripStyle) {
        let strips = followingWindows(strips, tabs: true)
        var style = withAppIcons(style, server.config.chutneyTabBarDecorateIcon)
        style.decorate = MacOSAppearance.bar(style.decorate, set: server.config.tabbardata, server.config)
        tabBars.update(strips, style: style, keyFocus: server.focused?.windowID)
        let frames = strips.map { CGRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.barHeight) }
        router.publish { $0.tabBarFrames = frames }
    }

    func showGroupBars(_ strips: [TabStrip], style: TabStripStyle) {
        let strips = followingWindows(strips, tabs: false)
        var style = withAppIcons(style, server.config.chutneyGroupBarDecorateIcon)
        style.decorate = MacOSAppearance.bar(style.decorate, set: server.config.groupbardata, server.config)
        groupBars.update(strips, style: style, keyFocus: server.focused?.windowID)
        let frames = strips.map { CGRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.barHeight) }
        router.publish { $0.groupBarFrames = frames }
    }
}
