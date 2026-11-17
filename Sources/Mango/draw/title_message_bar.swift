import CoreGraphics

/* One title_message_bar per monitor; it follows the focused client in
 * overcircle mode and the highlighted client below the switcher panel. */
package extension MangoServer {
    private func titleMessageBarText(_ c: Client) -> String {
        "\(c.title)\n\(c.appid)"
    }

    private func titleMessageBarInit(_ m: Monitor?) {
        guard let m, m.titleMessageBar == nil else { return }

        // not in mango: the port's side (mango_bar_decoration_create)
        m.titleMessageBar = system.mangoBarDecorationCreate(
            m, mangoBarDecorationApplyConfig(config.titleMessageBardata, mango: .mangoTitleMessageBar), 0, 0)
        guard let bar = m.titleMessageBar else { return }

        bar.setFocus(true)
        bar.setCenterSecondaryLine(true)
        bar.setEnabled(false)
    }

    private func titleMessageBarSetText(_ bar: MangoBarDecoration, _ c: Client, _ scale: Double) {
        let text = titleMessageBarText(c)
        if bar.lastText == text && bar.lastScale == scale { return }

        bar.update(text, scale)
    }

    private func overcircleTitleBarGeometry(_ m: Monitor, _ useAnimation: Bool) -> (client: Client, box: CGRect)? {
        guard isOvercircleMode(m), let id = m.sel, let c = clientByIdAll(id),
              config.titleMessageBarHeight != 0 else { return nil }

        // not in mango: the client's card, not c->geom or c->animation.current
        guard let geo = m.ovCards[id], geo.width > 0 else { return nil }

        return (c, CGRect(x: geo.minX, y: geo.maxY + CGFloat(config.titleMessageBarGap),
                          width: geo.width, height: CGFloat(config.titleMessageBarHeight)))
    }

    private func titleMessageBarGeometry(_ m: Monitor, _ useAnimation: Bool) -> (client: Client, box: CGRect)? {
        if let g = portHooks.titleMessageBarGeometry?(self, m) { return g }   // Port extension: chutney_launch_or_focus
        if let g = switcherTitleMessageBarGeometry(m) { return g }
        return overcircleTitleBarGeometry(m, useAnimation)
    }

    func titleMessageBarFinish(_ m: Monitor?) {
        guard let m, let bar = m.titleMessageBar else { return }

        bar.destroy()
        m.titleMessageBar = nil
    }

    func titleMessageBarApplyConfig(_ m: Monitor?) {
        guard let m, let bar = m.titleMessageBar else { return }

        bar.applyConfig(mangoBarDecorationApplyConfig(config.titleMessageBardata, mango: .mangoTitleMessageBar))
        bar.setFocus(true)
    }

    func titleMessageBarHide(_ m: Monitor?) {
        guard let m, let bar = m.titleMessageBar else { return }
        if bar.enabled { bar.setEnabled(false) }
    }

    func titleMessageBarUpdateTitle(_ c: Client?) {
        guard let c, let m = c.mon, let bar = m.titleMessageBar else { return }
        if !bar.enabled { return }

        if let target = portHooks.titleMessageBarGeometry?(self, m)?.client ?? switcherTitleMessageBarGeometry(m)?.client {   // Port extension: chutney_launch_or_focus
            if target !== c { return }
        } else if isOvercircleMode(m) {
            if m.sel != c.id { return }
        } else {
            return
        }

        titleMessageBarSetText(bar, c, m.screen.scale)
    }

    private func titleMessageBarRefresh(_ m: Monitor?, _ useAnimation: Bool) {
        guard let m else { return }

        guard let (c, box) = titleMessageBarGeometry(m, useAnimation), box.width > 0, box.height > 0 else {
            titleMessageBarHide(m)
            return
        }

        titleMessageBarInit(m)
        guard let bar = m.titleMessageBar else { return }

        let wasEnabled = bar.enabled
        if !wasEnabled { bar.setEnabled(true) }

        titleMessageBarSetText(bar, c, m.screen.scale)
        bar.setSize(box.width, box.height)

        bar.setPosition(box.minX, box.minY)
        if !wasEnabled { bar.raiseToTop() }
    }

    func titleMessageBarUpdate(_ m: Monitor?) {
        titleMessageBarRefresh(m, false)
    }

    func titleMessageBarUpdateGeometry(_ m: Monitor?) {
        titleMessageBarRefresh(m, true)
    }
}
