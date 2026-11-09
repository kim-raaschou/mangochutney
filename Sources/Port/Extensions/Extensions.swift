import CoreGraphics
import Mango
extension MangoServer {
    func registerPortExtensions() {
        portHooks = PortHooks()
        portHooks.extraDispatchers["chutney_focus_app"] = { server, d in
            guard let app = d.args.first, !app.isEmpty, app != "0" else { return "missing app" }
            server.focusApp(app, command: d.args.dropFirst().joined(separator: ","))
            return nil
        }
        portHooks.extraDispatchers["chutney_set_proportion_all"] = { server, d in
            guard let m = server.selectedMonitor, m.layout.isScroller, server.overviewState?.monitor !== m else { return nil }
            let tiled = server.tiledClients(m)
            if tiled.count == 1 && !server.config.scrollerIgnoreProportionSingle { return nil }
            let p = d.args.first.flatMap(Double.init).map { CGFloat($0) } ?? m.current.settings.scrollerDefaultProportion
            for c in tiled { server.scrollGetStackHeadClient(c).scrollerProportion = p }
            server.arrange(m)
            return nil
        }
        portHooks.extraDispatchers["chutney_restart"] = { server, _ in
            (server.system as? MacWindowSystem)?.restarting = true
            return server.dispatch(Dispatch(name: "quit"))
        }
        portHooks.extraDispatchers["chutney_toggle_hotkeys_palette"] = { server, _ in
            HotkeysPalette.shared.toggle(server)
            return nil
        }
        portHooks.extraDispatchers["chutney_toggle_layout_palette"] = { server, _ in
            LayoutPalette.shared.toggle(server)
            return nil
        }
        func memory(_ server: MangoServer) -> WindowMemory? { (server.system as? MacWindowSystem)?.memory }
        portHooks.windowLeaving = { server, c, group, focus, order in
            memory(server)?.leaving(server, c, group: group, groupFocus: focus, order: order)
            (server.system as? MacWindowSystem)?.focusHistory.removeAll { $0 == c.id }
        }
        portHooks.clientFocused = { server, c in
            guard let mac = server.system as? MacWindowSystem else { return }
            mac.focusHistory.removeAll { $0 == c.id }
            mac.focusHistory.insert(c.id, at: 0)
        }
        portHooks.saveLayout = { server, final in memory(server)?.save(server, final: final) }
        portHooks.restoreLayout = { server in memory(server)?.restore(server) }
        portHooks.ipcGets["get binds"] = { server in ShortcutFormatter.bindsReply(server.shortcutRows) }
        portHooks.borderColor = { server, c in server.floatingBorderColor(c) }
        portHooks.overlayLook = { server, set in server.config.chutneyStyle ? set : nil }
        portHooks.borderRadius = { server, _ in server.config.chutneyStyle ? BorderGeometry.cornerRadius : nil }
        portHooks.focusedBorderOnly = { server in !server.config.chutneyBorderUnfocused }
        portHooks.configLoaded.append { server in server.mac.watcher.ignoredBundleIds = Set(server.config.chutneyIgnoreApps) }
        portHooks.configLoaded.append { server in (server.system as? MacWindowSystem)?.configLoaded(server.config) }
        portHooks.configLoaded.append { server in
            guard ChutneyTheme.sync(configURL: server.configURL, style: server.config.chutneyStyle) else { return }
            mangoError(true, .info, "chutney_style: \(ChutneyTheme.fileName) written for chutney_style=\(server.config.chutneyStyle ? 1 : 0)")
            DispatchQueue.main.async { MainActor.assumeIsolated { server.reloadConfig() } }
        }
        observeMacOSTheme()
    }
}
