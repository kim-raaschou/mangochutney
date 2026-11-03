import CoreGraphics
import Foundation
import Mango

/// What mango knows about its windows, kept on disk so that restarting mango (an update,
/// or the LaunchAgent starting it again after a crash) does not put every window on the
/// current tag. mango itself cannot have this problem: when the compositor goes, its
/// clients go with it. Window ids are the window server's and last one login session,
/// so the file carries the session's id and every window its app; a window that does
/// not match both is left alone.
struct SavedLayout: Codable, Equatable {
    struct Window: Codable, Equatable {
        var id: CGWindowID
        var bundleId: String
        var tags: UInt32
        var displayID: CGDirectDisplayID?
        var homeDisplayID: CGDirectDisplayID?
        var isFloating: Bool
        var isGlobal: Bool
        var isOverlay: Bool
        var isMinimized: Bool
        var isScratchpad: Bool
        var isNamedScratchpad: Bool
        var floatFrame: CGRect
        var scrollerProportion: CGFloat?
        /// Only for a window that is away (around sleep): the order when it left.
        var orderSnapshot: [CGWindowID]?
        /// Its floating place was given (nil in a file from before it was kept).
        var isCustomSize: Bool? = nil
    }

    /// A tag's layout, kept as a reload keeps it: the runtime layout, unless the tag_rule
    /// that set it has changed since (`configuredLayout`). Layouts by name.
    struct TagLayout: Codable, Equatable {
        var layout: String
        var prevLayout: String
        var configuredLayout: String?
    }

    var session: String
    /// The client order (index 0 = master).
    var order: [CGWindowID]
    var windows: [Window]
    /// The tags each display showed, by display id.
    var tagsets: [String: UInt32]
    /// Each display's tag layouts (index 0 = the special tag), the tags it showed before
    /// (`view` goes back to them) and its previous tag, by display id; nil in a file from
    /// before they were kept.
    var tagLayouts: [String: [TagLayout]]? = nil
    var previousTagsets: [String: UInt32]? = nil
    var prevTags: [String: Int]? = nil
    /// Window groups, head first, with the member in view (nil in a file from before).
    var groups: [DepartedGroup]? = nil

    /// `$XDG_STATE_HOME/mango/windows.json`, else `~/.local/state/mango/windows.json`.
    static var defaultURL: URL {
        let env = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
        let base = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("mango/windows.json")
    }

    /// The window server's id for this login session; window ids from another session
    /// mean other windows.
    static var currentSession: String {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (dict?["CGSSessionUniqueSessionUUID"] as? String) ?? ""
    }

    /// Not in mango: the saved layout across restarts.
    /// The saved layout, or nil when there is none, it cannot be read, or it is from
    /// another session.
    static func load(from url: URL, session: String) -> SavedLayout? {
        guard !session.isEmpty, let data = try? Data(contentsOf: url) else { return nil }
        guard let saved = try? JSONDecoder().decode(SavedLayout.self, from: data) else {
            Log.info("ignoring \(url.path): cannot be read")
            return nil
        }
        guard saved.session == session else { return nil }
        return saved
    }

    /// Not in mango: the saved layout across restarts.
    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Not in mango: the saved layout across restarts.
    /// The saved windows as departed ones, so the first scan restores them the way a
    /// window that comes back after sleep is restored.
    func departed(at now: CFTimeInterval) -> [(CGWindowID, DepartedWindow)] {
        windows.map { w in
            (w.id, DepartedWindow(
                tags: w.tags, displayID: w.displayID, isFloating: w.isFloating, isGlobal: w.isGlobal,
                isOverlay: w.isOverlay, isMinimized: w.isMinimized, isScratchpad: w.isScratchpad,
                isNamedScratchpad: w.isNamedScratchpad, floatFrame: w.floatFrame,
                scrollerProportion: w.scrollerProportion, orderSnapshot: w.orderSnapshot ?? order, at: now,
                bundleId: w.bundleId, homeDisplayID: w.homeDisplayID, fromSavedLayout: true,
                isCustomSize: w.isCustomSize ?? false))
        }
    }
}
