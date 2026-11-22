import CoreGraphics
import Foundation
@testable import Mango

/// A scenario of Tests/MangoFacit and mango's own answers to it: what `mmsg get` said in mango 0.18.5
/// at each `check` (Tests/MangoFacit/record wrote them). The screens are in the order the backend
/// gave them to mango.
package struct Facit {
    /// The answers at one `check`: lists of fields, as mmsg printed them. Checks go by their order in
    /// the scenario, so a comment or an `ours` line needs no new recording.
    package struct Check {
        package let line: Int
        package var clients: [[String: Any]]
        package var monitors: [[String: Any]]
        package var cursor: [String: Any]
    }

    package let name: String
    package let lines: [String]
    package let screens: [Screen]
    /// Where wlroots put the pointer when mango started.
    package let pointer: CGPoint
    package let checks: [Check]

    package static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("MangoFacit")

    package static var all: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("scenarios").path)) ?? []
        return files.filter { $0.hasSuffix(".mango") }.map { String($0.dropLast(6)) }.sorted()
    }

    package init(_ name: String) throws {
        self.name = name
        let scenario = Facit.directory.appendingPathComponent("scenarios/\(name).mango")
        lines = try String(contentsOf: scenario, encoding: .utf8).components(separatedBy: "\n")
        let data = try Data(contentsOf: Facit.directory.appendingPathComponent("facit/\(name).json"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        screens = (json["screens"] as! [[String: Any]]).enumerated().map { i, s in
            let frame = CGRect(x: s["x"] as! Int, y: s["y"] as! Int, width: s["width"] as! Int, height: s["height"] as! Int)
            return Screen(displayID: CGDirectDisplayID(i + 1), name: s["name"] as! String, frame: frame, workArea: frame,
                          scale: 1, isMain: frame.origin == .zero)
        }
        let p = json["pointer"] as! [String: Any]
        pointer = CGPoint(x: p["x"] as! Double, y: p["y"] as! Double)
        var checks = (json["checks"] as! [[String: Any]]).map {
            Check(line: $0["after_line"] as! Int, clients: $0["clients"] as! [[String: Any]],
                  monitors: $0["monitors"] as! [[String: Any]], cursor: $0["cursor"] as! [String: Any])
        }
        // `ours <title|monitor|cursor>.<field> <json>` after a check: where we answer otherwise on purpose
        // (a mango bug we fix, docs/afvigelser.md §6, or a listed deviation).
        var c = -1
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "check" { c += 1; continue }
            guard line.hasPrefix("ours "), checks.indices.contains(c) else { continue }
            let words = line.split(separator: " ", maxSplits: 3).map(String.init)
            let item = String(words[1].prefix { $0 != "." })
            let field = String(words[1].drop { $0 != "." }.dropFirst())
            let value = try JSONSerialization.jsonObject(with: Data(words[2].utf8), options: .fragmentsAllowed)
            for j in checks[c].clients.indices where "\(checks[c].clients[j]["title"]!)" == item { checks[c].clients[j][field] = value }
            for j in checks[c].monitors.indices where "\(checks[c].monitors[j]["name"]!)" == item { checks[c].monitors[j][field] = value }
            if item == "cursor" { checks[c].cursor[field] = value }
        }
        self.checks = checks
    }
}

extension TestMango {
    /// Plays a scenario as the recorder played it on mango, and answers each `check` as mmsg would:
    /// the fields mango's facit holds, of `get all-clients`, `get all-monitors` and `get cursorpos`.
    package static func play(_ facit: Facit) -> [Facit.Check] {
        let steps = facit.lines.enumerated().map { ($0.offset + 1, $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.1.isEmpty && !$0.1.hasPrefix("#") }
        let config = steps.compactMap { $0.1.hasPrefix("config ") ? String($0.1.dropFirst(7)) : nil }
        let mango = TestMango(config.joined(separator: "\n"), screens: facit.screens)
        mango.wlroots.pointer = facit.pointer

        var answers: [Facit.Check] = []
        for (line, step) in steps {
            let word = step.prefix { $0 != " " }
            let rest = step.dropFirst(word.count).trimmingCharacters(in: .whitespaces)
            switch word {
            case "open":
                let dialog = rest.hasSuffix(" dialog")
                let title = dialog ? String(rest.dropLast(7)) : rest
                mango.map(title, size: dialog ? CGSize(width: 400, height: 300) : CGSize(width: 800, height: 600), dialog: dialog)
            case "close":
                mango.unmap(rest)
            case "dispatch":
                mango.mmsg("dispatch", mango.target(rest))
            case "check":
                let expected = facit.checks.indices.contains(answers.count) ? facit.checks[answers.count] : nil
                answers.append(Facit.Check(line: line,
                                           clients: mango.get("all-clients", "clients", like: expected?.clients.first),
                                           monitors: mango.get("all-monitors", "monitors", like: expected?.monitors.first),
                                           cursor: mango.cursor()))
            default:
                break
            }
            // The facit client goes when mango asks it to close (xdg_toplevel close).
            for id in mango.wlroots.closed { if let c = mango.server.clientByIdAll(id) { mango.server.handleClientUnmap(c) } }
            mango.wlroots.closed = []
            mango.frame()
        }
        return answers
    }

    /// `mmsg get <what>`'s list under `key`, with the fields `like` has. active_client is its title.
    func get(_ what: String, _ key: String, like: [String: Any]?) -> [[String: Any]] {
        let fields = like.map { Set($0.keys) }
        return (json(mmsg("get", what))[key] as? [[String: Any]] ?? []).map { item in
            var item = item
            if let active = item["active_client"] as? [String: Any] { item["active_client"] = active["title"] }
            return item.filter { fields?.contains($0.key) ?? true }
        }
    }

    /// `@b func,args` is mango's `func,args client,<id>`, with the id of the window titled b.
    func target(_ rest: String) -> String {
        guard rest.hasPrefix("@") else { return rest }
        let title = rest.dropFirst().prefix { $0 != " " }
        let clients = json(mmsg("get", "all-clients"))["clients"] as? [[String: Any]] ?? []
        guard let id = clients.first(where: { "\($0["title"]!)" == title })?["id"] else { return rest }
        return rest.dropFirst(title.count + 1).trimmingCharacters(in: .whitespaces) + " client,\(id)"
    }

    /// `mmsg get cursorpos`, its place.
    func cursor() -> [String: Any] { json(mmsg("get", "cursorpos")).filter { $0.key == "x" || $0.key == "y" } }

    func json(_ answer: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any]) ?? [:]
    }
}
