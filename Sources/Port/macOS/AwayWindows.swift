import CoreGraphics
import Mango

enum AwayReason: Hashable {
    case minimized, fullscreen, hidden
}

extension MacWindowSystem {
    func goAway(_ c: Client, _ reason: AwayReason) {
        if var entry = away[c.windowID] {
            entry.reasons.insert(reason)
            away[c.windowID] = entry
            return
        }
        guard server.clientByWindowID(c.windowID) === c else { return }
        away[c.windowID] = (c, [reason])
        hideEdgePlate(c.windowID)
        memory.departed.away.insert(c.windowID)
        c.parked = false
        forgetPlacement(c)
        server.handleClientUnmap(c)
        wlrLog(.info, "\(c.appName): window \(c.windowID) is away (\(reason)); out of the layout until it is back")
    }

    func foundAway(_ c: Client, _ reasons: Set<AwayReason>) {
        away[c.windowID] = (c, reasons)
    }

    func comeBack(_ id: ClientID, _ reason: AwayReason, focus: Bool = false) {
        guard var entry = away[id] else { return }
        entry.reasons.remove(reason)
        guard entry.reasons.isEmpty else { away[id] = entry; return }
        away.removeValue(forKey: id)
        let c = entry.client
        c.parked = false
        forgetPlacement(c)
        if let real = windowServerFrame(c.windowID) { c.frame = real }
        let d = memory.back(c)
        memory.departed.away.remove(id)
        // Port extension: chutney_fullscreen_tag. Back from another reason still in fullscreen: onto its F tag.
        let onFTag = reason != .fullscreen && fullscreenHooks.takesWindows && fullscreenNow(c) == true
        fullscreenHooks.mapInFullscreen(c, onFTag) {
            if let d {
                mapBack(c, d, initial: false)
            } else {
                server.handleClientMap(c)
            }
        }
        if onFTag { return }
        wlrLog(.info, "\(c.appName): window \(c.windowID) is back from \(reason)")
        if focus { windowFocused(id: id) }
    }
}
