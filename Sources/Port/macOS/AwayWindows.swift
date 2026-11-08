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
        c.parked = false
        animator.cancel(c.id)
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
        if let real = windowServerFrame(c.id) { c.frame = real }
        if let d = memory.back(c) {
            mapBack(c, d, initial: false)
        } else {
            server.handleClientMap(c)
        }
        wlrLog(.info, "\(c.appName): window \(c.id) is back from \(reason)")
        if focus { windowFocused(id: id) }
    }
}
