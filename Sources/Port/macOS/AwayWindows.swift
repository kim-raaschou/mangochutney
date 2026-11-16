import CoreGraphics
import Mango

enum AwayReason: Hashable {
    case minimized, fullscreen, hidden, stuck
}

extension MacWindowSystem {
    func goAway(_ c: Client, _ reason: AwayReason) {
        if var entry = away[c.id] {
            entry.reasons.insert(reason)
            away[c.id] = entry
            return
        }
        guard server.clientByIdAll(c.id) === c else { return }
        away[c.id] = (c, [reason])
        hideEdgePlate(c.id)
        memory.departed.away.insert(c.id)
        c.parked = false
        forgetPlacement(c)
        server.handleClientUnmap(c)
        wlrLog(.info, "\(c.appName): window \(c.id) is away (\(reason)); out of the layout until it is back")
    }

    func foundAway(_ c: Client, _ reasons: Set<AwayReason>) {
        away[c.id] = (c, reasons)
    }

    func comeBack(_ id: ClientID, _ reason: AwayReason, focus: Bool = false) {
        guard var entry = away[id] else { return }
        entry.reasons.remove(reason)
        guard entry.reasons.isEmpty else { away[id] = entry; return }
        away.removeValue(forKey: id)
        let c = entry.client
        c.parked = false
        forgetPlacement(c)
        if let real = windowServerFrame(c.id) { c.frame = real }
        let d = memory.back(c)
        memory.departed.away.remove(id)
        // Port extension: chutney_fullscreen_tag. Back from another reason still in fullscreen: onto its F tag.
        let onFTag = reason != .fullscreen && FullscreenTag.isOn(server) && fullscreenNow(c) == true
        FullscreenTag.mapInFullscreen(server, c, onFTag) {
            if let d {
                mapBack(c, d, initial: false)
            } else {
                server.handleClientMap(c)
            }
        }
        if onFTag { return }
        wlrLog(.info, "\(c.appName): window \(c.id) is back from \(reason)")
        if focus { windowFocused(id: id) }
    }

    /// What the port knew of the window's place: the size its app kept it at and the writes it was
    /// retrying are not the ones it comes back to.
    func forgetPlacement(_ c: Client) {
        c.refusedSize = nil
        c.retryTarget = nil
        c.retryCount = 0
    }
}
