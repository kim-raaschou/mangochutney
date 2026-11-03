import CoreGraphics
import Mango

/// Not in mango: why macOS has a window away. Minimized in the Dock (with ignore_minimize,
/// mango's default, mango refuses the minimize; macOS has done it), in native fullscreen on a
/// Space of its own, of a hidden app (⌘H), or parked by an app that does not answer.
enum AwayReason: Hashable {
    case minimized, fullscreen, hidden, stuck
}

/// Not in mango: a window macOS has away is one mango would have unmapped. The port unmaps
/// it (mango's handle_client_unmap, which remembers what it had), keeps it here, and maps it
/// back to its place (mapBack) when no reason keeps it away any more.
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
        Log.info("\(c.appName): window \(c.id) is away (\(reason)); out of the layout until it is back")
    }

    /// A window found away (at start, or before mango saw it): kept until it is back.
    func foundAway(_ c: Client, _ reasons: Set<AwayReason>) {
        away[c.id] = (c, reasons)
        Log.debug("\(c.appName): window \(c.id) found away \(reasons)")
    }

    /// `reason` is over. `focus`: macOS has focused it (a click in the Dock).
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
        Log.info("\(c.appName): window \(c.id) is back from \(reason)")
        if focus { windowFocused(id: id) }
    }
}
