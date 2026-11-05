import CoreGraphics
import Mango
/// The port's own extensions, joined to mango through PortHooks. Each is off until its
/// option is set (or, for a dispatcher, until it is bound): with none of them set the
/// port behaves as mango.
extension MangoServer {
    func registerPortExtensions() {
        portHooks = PortHooks()   // once, whoever calls it again
        portHooks.extraDispatchers["chutney_focus_app"] = { server, d in
            guard let app = d.args.first, !app.isEmpty, app != "0" else { return "missing app" }
            server.focusApp(app, command: d.args.dropFirst().joined(separator: ","))
            return nil
        }
        // chutney_set_proportion_all: mango's set_proportion for every column of the tag in
        // view, with its conditions; without a value, back to scroller_default_proportion.
        portHooks.extraDispatchers["chutney_set_proportion_all"] = { server, d in
            guard let m = server.selectedMonitor, m.layout.isScroller, server.overviewState?.monitor !== m else { return nil }
            let tiled = server.tiledClients(m)
            if tiled.count == 1 && !server.config.scrollerIgnoreProportionSingle { return nil }
            let p = d.args.first.flatMap(Double.init).map { CGFloat($0) } ?? m.current.settings.scrollerDefaultProportion
            for c in tiled { server.scrollGetStackHeadClient(c).scrollerProportion = p }
            server.arrange(m)
            return nil
        }
        // chutney_restart: mango's quit, with hidden windows left where they are (make
        // install, `mmsg service restart`); the next mango restores them from the saved
        // layout instead of every hidden window flashing up in between.
        portHooks.extraDispatchers["chutney_restart"] = { server, _ in
            (server.system as? MacWindowSystem)?.restarting = true
            return server.dispatch(Dispatch(name: "quit"))
        }
        // chutney_toggle_hotkeys_palette: the hotkeys palette (search and run a binding).
        portHooks.extraDispatchers["chutney_toggle_hotkeys_palette"] = { server, _ in
            HotkeysPalette.shared.toggle(server)
            return nil
        }
        // chutney_toggle_layout_palette: the layout palette (pick a layout with the keys).
        portHooks.extraDispatchers["chutney_toggle_layout_palette"] = { server, _ in
            LayoutPalette.shared.toggle(server)
            return nil
        }
        // Windows that leave and come back (sleep, a restart): the macOS layer's memory.
        func memory(_ server: MangoServer) -> WindowMemory? { (server.system as? MacWindowSystem)?.memory }
        portHooks.windowLeaving = { server, c, group, focus, order in
            memory(server)?.leaving(server, c, group: group, groupFocus: focus, order: order)
            (server.system as? MacWindowSystem)?.focusHistory.removeAll { $0 == c.id }
        }
        // chutney_focus_app's "used last": the windows in the order they had the focus.
        portHooks.clientFocused = { server, c in
            guard let mac = server.system as? MacWindowSystem else { return }
            mac.focusHistory.removeAll { $0 == c.id }
            mac.focusHistory.insert(c.id, at: 0)
        }
        portHooks.saveLayout = { server, final in memory(server)?.save(server, final: final) }
        portHooks.restoreLayout = { server in memory(server)?.restore(server) }
        // get binds (mmsg binds): the bindings as readable rows.
        portHooks.ipcGets["get binds"] = { server in ShortcutFormatter.bindsReply(server.shortcutRows) }
        portHooks.borderColor = { server, c in server.floatingBorderColor(c) }
        // chutney_style: what no decorate key sets is drawn the macOS way (nil fields).
        portHooks.overlayLook = { server, set in server.config.chutneyStyle ? set : nil }
        portHooks.borderRadius = { server, _ in server.config.chutneyStyle ? BorderGeometry.cornerRadius : nil }
        // chutney_border_unfocused off: borders around the focused window only.
        portHooks.focusedBorderOnly = { server in !server.config.chutneyBorderUnfocused }
        // chutney_physical_pixels: border_px and the gaps in the screen's pixels.
        portHooks.pixelScale = { server, m in
            server.config.chutneyPhysicalPixels ? 1 / max(1, m.screen.scale) : 1
        }
        // chutney_ignore_apps: the apps the watcher leaves alone.
        portHooks.configLoaded.append { server in server.mac.watcher.ignoredBundleIds = Set(server.config.chutneyIgnoreApps) }
        // The macOS layer: what macOS cannot do is said once.
        portHooks.configLoaded.append { server in (server.system as? MacWindowSystem)?.configLoaded(server.config) }
        // chutney_style: chutney_theme.conf follows macOS's accent colour and light/dark, and the
        // key itself when a reload sets or clears it (the config is then read once more).
        portHooks.configLoaded.append { server in
            guard ChutneyTheme.sync(configURL: server.configURL, style: server.config.chutneyStyle) else { return }
            Log.info("chutney_style: \(ChutneyTheme.fileName) written for chutney_style=\(server.config.chutneyStyle ? 1 : 0)")
            DispatchQueue.main.async { MainActor.assumeIsolated { server.reloadConfig() } }
        }
        observeMacOSTheme()
    }
}
