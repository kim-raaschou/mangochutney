import CoreGraphics
import Mango

struct WindowBook<Element, Discovered> {
    var windows: [CGWindowID: Element] = [:]
    var orphans: [CGWindowID: Element] = [:]
    var rejected: [CGWindowID: Int] = [:]
    static var maxRechecks: Int { 5 }
    var unsubscribed: Set<CGWindowID> = []

    struct Answers {
        var subscribe: (Element) -> Bool
        var unsubscribe: (Element) -> Void
        var isInvalid: (Element) -> Bool
        var onScreen: (CGWindowID) -> Bool
        var classify: (Element, CGWindowID) -> Discovered?
    }

    struct Outcome {
        var reacquired: [(CGWindowID, Element)] = []
        var found: [Discovered] = []
        var orphaned: [CGWindowID] = []
        var gone: [(CGWindowID, GoneBecause)] = []
    }

    enum GoneBecause: Equatable {
        case elementInvalid
        case notOnScreen
    }

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
        let appAnswers = !listed.isEmpty
        for (id, el) in windows where !seen.contains(id) && a.isInvalid(el) {
            windows.removeValue(forKey: id)
            unsubscribed.remove(id)
            if !appAnswers && a.onScreen(id) {
                orphans[id] = el
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

    mutating func forget(_ id: CGWindowID) {
        windows.removeValue(forKey: id)
        orphans.removeValue(forKey: id)
        unsubscribed.remove(id)
    }
}
