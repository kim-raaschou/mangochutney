import CoreGraphics
import Foundation
import Mango

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
        var orderSnapshot: [CGWindowID]?
        var isCustomSize: Bool? = nil
    }

    struct TagLayout: Codable, Equatable {
        var layout: String
        var configuredLayout: String?
    }

    var session: String
    var order: [CGWindowID]
    var windows: [Window]
    var tagsets: [String: UInt32]
    var tagLayouts: [String: [TagLayout]]? = nil
    var previousTagsets: [String: UInt32]? = nil
    var prevTags: [String: Int]? = nil
    var groups: [DepartedGroup]? = nil

    static var defaultURL: URL {
        let env = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
        let base = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("mango/windows.json")
    }

    static var currentSession: String {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (dict?["CGSSessionUniqueSessionUUID"] as? String) ?? ""
    }

    static func load(from url: URL, session: String) -> SavedLayout? {
        guard !session.isEmpty, let data = try? Data(contentsOf: url) else { return nil }
        guard let saved = try? JSONDecoder().decode(SavedLayout.self, from: data) else {
            wlrLog(.info, "ignoring \(url.path): cannot be read")
            return nil
        }
        guard saved.session == session else { return nil }
        return saved
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

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
