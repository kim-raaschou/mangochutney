import CoreGraphics
import Mango
extension MangoServer {
    func registerPortExtensions() {
        portHooks = PortHooks()
        portHooks.extraDispatchers["chutney_launch_or_focus"] = { server, d in
            guard let app = d.args.first, !app.isEmpty, app != "0" else { return "missing app" }
            server.launchOrFocus(app, command: d.args.dropFirst().joined(separator: ","))
            return nil
        }
        portHooks.extraDispatchers["chutney_restart"] = { server, _ in
            (server.system as? MacWindowSystem)?.restarting = true
            return server.dispatch(Dispatch(name: "quit"))
        }
        portHooks.extraDispatchers["chutney_keybindings"] = { server, _ in
            HotkeysPalette.shared.toggle(server)
            return nil
        }
        portHooks.extraDispatchers["chutney_layout_switcher"] = { server, _ in
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
        portHooks.barsInsideBorder = { server in server.config.chutneyMacOSAppearance }
        portHooks.configLoaded.append { server in (server.system as? MacWindowSystem)?.configLoaded(server.config) }
        portHooks.configLoaded.append { server in
            guard ChutneyTheme.sync(configURL: server.configURL, style: server.config.chutneyMacOSAppearance) else { return }
            mangoError(true, .info, "chutney_macos_appearance: \(ChutneyTheme.fileName) written for chutney_macos_appearance=\(server.config.chutneyMacOSAppearance ? 1 : 0)")
            DispatchQueue.main.async { MainActor.assumeIsolated { server.reloadConfig() } }
        }
        observeMacOSTheme()
    }
}
