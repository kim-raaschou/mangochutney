import CoreGraphics
import Mango

/// One app's windows as its `AppWorker` keeps them, and what a refresh decides: a new
/// window, one listed again after its element died (an orphan, around sleep), one that is
/// gone, one rejected (a popup) and checked again. No Accessibility here: the worker
/// answers the questions, so the tests can use plain values for elements.
struct WindowBook<Element, Discovered> {
    var windows: [CGWindowID: Element] = [:]
    /// Windows whose element went invalid while the window server still shows them and
    /// the app lists no windows at all: around sleep every app's elements go invalid at
    /// once and come back seconds later. An app that lists windows has working
    /// accessibility, so a window of it with a dead element that it does not list is
    /// closed, even while the window server still shows its closing animation.
    /// Kept (not reported gone) until the app lists them again, or until the window server
    /// no longer shows them: it answers nothing for a closed, minimized or hidden window
    /// or one on another Space, so an orphan that stays is a window on screen (parked ones
    /// keep a sliver there). One that is not goes to DepartedWindows and gets its place
    /// back if it returns. No clock: a window the app never lists again but the window
    /// server shows is a real window, not a ghost. An orphan keeps its element and its
    /// registrations: the app's own destroyed notice for it ends it (`forget`), as when the
    /// app's last window is closed and the scan saw it still fading out on screen.
    var orphans: [CGWindowID: Element] = [:]
    /// Windows seen but rejected (popups), with how often a rescan re-checked them.
    /// Rescans give up after `maxRechecks` (an app that keeps a hidden helper window
    /// alive would otherwise cost ~15 AX calls on every click, all day); the app's own
    /// notifications (window created, focus, activation) still re-check them. A held
    /// key does not rescan (see `MangoServer.dispatch`), so the budget is five user
    /// actions, not five key repeats.
    var rejected: [CGWindowID: Int] = [:]
    static var maxRechecks: Int { 5 }
    /// Windows whose notifications could not be registered yet.
    var unsubscribed: Set<CGWindowID> = []

    /// What the worker answers for a refresh.
    struct Answers {
        /// Register the window's notifications; false when that failed (retried later).
        var subscribe: (Element) -> Bool
        var unsubscribe: (Element) -> Void
        /// The element is dead (its role read says invalid), not just slow.
        var isInvalid: (Element) -> Bool
        /// The window server shows the window (see `orphans`).
        var onScreen: (CGWindowID) -> Bool
        /// A manageable window, or nil for a popup and the like.
        var classify: (Element, CGWindowID) -> Discovered?
    }

    struct Outcome {
        /// Listed again with a new element, in listing order.
        var reacquired: [(CGWindowID, Element)] = []
        var found: [Discovered] = []
        /// Element dead, window still on screen: kept as an orphan.
        var orphaned: [CGWindowID] = []
        var gone: [(CGWindowID, GoneBecause)] = []
    }

    enum GoneBecause: Equatable {
        /// Not listed and its element is invalid.
        case elementInvalid
        /// An orphan the window server no longer shows.
        case notOnScreen
    }

    /// `listed`: the app's kAXWindows answer. `recheck`: re-classify rejected windows,
    /// bounded (a rescan); `notified`: the app's own notification, always re-checks.
    mutating func refresh(listed: [(CGWindowID, Element)], recheck: Bool, notified: Bool,
                          answers a: Answers) -> Outcome {
        var out = Outcome()
        var seen: Set<CGWindowID> = []
        for (id, el) in listed {
            seen.insert(id)
            if let known = windows[id] {
                if unsubscribed.contains(id), a.subscribe(known) { unsubscribed.remove(id) }
                continue
            }
            if let old = orphans.removeValue(forKey: id) {
                a.unsubscribe(old)
                windows[id] = el
                if !a.subscribe(el) { unsubscribed.insert(id) }
                out.reacquired.append((id, el))
                continue
            }
            if let tries = rejected[id] {
                guard notified || (recheck && tries < Self.maxRechecks) else { continue }
                if !notified { rejected[id] = tries + 1 }
            }
            guard let d = a.classify(el, id) else {
                if rejected[id] == nil { rejected[id] = 0 }
                continue
            }
            rejected.removeValue(forKey: id)
            windows[id] = el
            if !a.subscribe(el) { unsubscribed.insert(id) }
            out.found.append(d)
        }
        // kAXWindowsAttribute omits minimized and other-Space windows. A window is
        // only gone when the element itself is invalid; a timeout says nothing.
        let appAnswers = !listed.isEmpty
        for (id, el) in windows where !seen.contains(id) && a.isInvalid(el) {
            windows.removeValue(forKey: id)
            unsubscribed.remove(id)
            if !appAnswers && a.onScreen(id) {
                orphans[id] = el   // the element is dead but the window is not (sleep)
                out.orphaned.append(id)
            } else {
                a.unsubscribe(el)
                out.gone.append((id, .elementInvalid))
            }
        }
        for (id, el) in orphans where !seen.contains(id) && (appAnswers || !a.onScreen(id)) {
            orphans.removeValue(forKey: id)
            a.unsubscribe(el)
            out.gone.append((id, appAnswers ? .elementInvalid : .notOnScreen))
        }
        rejected = rejected.filter { seen.contains($0.key) }
        return out
    }

    /// The app reported the window destroyed: gone, an orphan too (the app knows better
    /// than the window server's closing animation).
    mutating func forget(_ id: CGWindowID) {
        windows.removeValue(forKey: id)
        orphans.removeValue(forKey: id)
        unsubscribed.remove(id)
    }
}
