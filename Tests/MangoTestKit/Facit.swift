import CoreGraphics
import Foundation
@testable import Mango

/// A scenario of Tests/MangoFacit and mango's own answers to it: what `mmsg get` said in mango 0.18.5
/// at each `check` (Tests/MangoFacit/record wrote them). The screens are in the order the backend
/// gave them to mango.
package struct Facit {
    /// An mmsg answer without mango's bookkeeping (ids, pids, a foreign toplevel's random id), as the
    /// recorder keeps it.
    package static func answer(_ value: Any) -> Any {
        if let d = value as? [String: Any] {
            return d.filter { !["id", "pid", "foreign_toplevel_id"].contains($0.key) }.mapValues(answer)
        }
        if let a = value as? [Any] { return a.map(answer) }
        return value
    }

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
    /// mango's answers at the `get` steps, without its bookkeeping (Facit.answer).
    package let gets: [(line: Int, answer: Any)]
    /// The outputs `output add` gave mango, where mango placed them.
    package let outputs: [Screen]

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
        var gets = (json["gets"] as? [[String: Any]] ?? []).map { (line: $0["after_line"] as! Int, answer: $0["answer"]!) }
        outputs = (json["outputs"] as? [[String: Any]] ?? []).enumerated().map { i, s in
            let frame = CGRect(x: s["x"] as! Int, y: s["y"] as! Int, width: s["width"] as! Int, height: s["height"] as! Int)
            return Screen(displayID: CGDirectDisplayID(100 + i), name: s["name"] as! String, frame: frame, workArea: frame,
                          scale: 1, isMain: false)
        }
        let p = json["pointer"] as! [String: Any]
        pointer = CGPoint(x: p["x"] as! Double, y: p["y"] as! Double)
        var checks = (json["checks"] as! [[String: Any]]).map {
            Check(line: $0["after_line"] as! Int, clients: $0["clients"] as! [[String: Any]],
                  monitors: $0["monitors"] as! [[String: Any]], cursor: $0["cursor"] as! [String: Any])
        }
        // `ours <title|monitor|cursor>.<field> <json>` after a check, or `ours <path> <json>` after a get
        // (`clients.3.height`): where we answer otherwise on purpose (a mango bug we fix,
        // docs/afvigelser.md §6, or a listed deviation).
        var c = -1, g = -1, afterGet = false
        for line in lines {
            let step = line.trimmingCharacters(in: .whitespaces)
            if step == "check" { c += 1; afterGet = false; continue }
            if step.hasPrefix("get ") { g += 1; afterGet = true; continue }
            guard line.hasPrefix("ours ") else { continue }
            let words = line.split(separator: " ", maxSplits: 2).map(String.init)
            if afterGet {
                let value = try JSONSerialization.jsonObject(with: Data(words[2].utf8), options: .fragmentsAllowed)
                gets[g].answer = Facit.set(gets[g].answer, at: words[1].split(separator: ".").map(String.init), to: value)
                continue
            }
            guard checks.indices.contains(c) else { continue }
            let item = String(words[1].prefix { $0 != "." })
            let field = String(words[1].drop { $0 != "." }.dropFirst())
            let value = try JSONSerialization.jsonObject(with: Data(words[2].utf8), options: .fragmentsAllowed)
            for j in checks[c].clients.indices where "\(checks[c].clients[j]["title"]!)" == item { checks[c].clients[j][field] = value }
            for j in checks[c].monitors.indices where "\(checks[c].monitors[j]["name"]!)" == item { checks[c].monitors[j][field] = value }
            if item == "cursor" { checks[c].cursor[field] = value }
        }
        self.checks = checks
        self.gets = gets
    }

    /// `value` with the field at `path` (keys, or indices of a list) set to `new`.
    static func set(_ value: Any, at path: [String], to new: Any) -> Any {
        guard let key = path.first else { return new }
        if var d = value as? [String: Any] {
            d[key] = set(d[key] as Any, at: Array(path.dropFirst()), to: new)
            return d
        }
        if var a = value as? [Any], let i = Int(key), a.indices.contains(i) {
            a[i] = set(a[i], at: Array(path.dropFirst()), to: new)
            return a
        }
        return value
    }
}

extension TestMango {
    /// Plays a scenario as the recorder played it on mango, and answers each `check` as mmsg would:
    /// the fields mango's facit holds, of `get all-clients`, `get all-monitors` and `get cursorpos`.
    /// Our answers at the `get` steps come with them, as the recorder keeps mango's.
    package static func play(_ facit: Facit) -> (checks: [Facit.Check], gets: [(line: Int, answer: Any)]) {
        let steps = facit.lines.enumerated().map { ($0.offset + 1, $0.element.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.1.isEmpty && !$0.1.hasPrefix("#") }
        var config = steps.compactMap { $0.1.hasPrefix("config ") ? String($0.1.dropFirst(7)) : nil }
        let mango = TestMango(config.joined(separator: "\n"), screens: facit.screens)
        mango.wlroots.pointer = facit.pointer
        // The config file a reload reads, as the recorder keeps it beside mango.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("facit-\(facit.name)-\(UUID().uuidString).conf")
        mango.server.configURL = file
        defer { try? FileManager.default.removeItem(at: file) }
        let port = ConfigParser.port
        ConfigParser.port = FakeKeymap()   // the binds' keys, at a reload as at the start
        defer { ConfigParser.port = port }

        var answers: [Facit.Check] = []
        var gets: [(line: Int, answer: Any)] = []
        var added = 0
        for (line, step) in steps {
            let word = step.prefix { $0 != " " }
            let rest = step.dropFirst(word.count).trimmingCharacters(in: .whitespaces)
            switch word {
            case "open":
                let words = rest.split(separator: " ").map(String.init)
                let dialog = words.contains("dialog")
                let own = words.dropFirst().first { $0.contains("x") }.map { $0.split(separator: "x").compactMap { Double($0) } }
                let size = own.map { CGSize(width: $0[0], height: $0[1]) }
                    ?? (dialog ? CGSize(width: 400, height: 300) : CGSize(width: 800, height: 600))
                mango.map(words[0], size: size, dialog: dialog)
            case "request":
                let words = rest.split(separator: " ").map(String.init)
                let c = mango.client(words[0])
                switch words[1] {
                case "minimize": mango.server.handleClientRequestMinimize(c, true)
                case "title": c.title = words[2]; mango.server.handleClientSetTitle(c)
                case "activate": mango.server.handleClientActivationRequest(c)   // with a token mango trusts
                default: break
                }
            case "output":
                // a display macOS adds, where mango's create_virtual_output adds an output
                mango.wlroots.screens.append(facit.outputs[added])
                added += 1
                mango.server.rebuildMonitors(screens: mango.wlroots.screens)
            case "reload":
                config.append(rest)
                try? ("animations=0\n" + config.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
                mango.mmsg("dispatch", "reload_config")
            case "close":
                mango.unmap(rest)
            case "dispatch":
                mango.mmsg("dispatch", mango.target(rest))
            case "key":
                let keys = rest.split(separator: "+").map(String.init)
                for k in keys { mango.key(k, down: true) }
                for k in keys.reversed() { mango.key(k, down: false) }
            case "keydown", "keyup":
                mango.key(rest, down: word == "keydown")
            case "pointer":
                let xy = rest.split(separator: ",").compactMap { Double($0) }
                mango.pointer(to: CGPoint(x: xy[0], y: xy[1]))
            case "move":
                let d = rest.split(separator: ",").compactMap { Double($0) }
                mango.move(by: CGVector(dx: d[0], dy: d[1]))
            case "click", "button":
                let words = rest.split(separator: " ")
                let button = ["left": 0, "right": 1, "middle": 2][String(words[0])]!
                if word == "click" || words[1] == "down" { mango.button(button, down: true) }
                if word == "click" || words[1] == "up" { mango.button(button, down: false) }
            case "scroll":
                mango.scroll(vertical: rest == "up" || rest == "down", delta: rest == "up" || rest == "left" ? -15 : 15)
            case "get":
                let words = rest.split(separator: " ").map { w in
                    w.hasPrefix("@") ? "\(mango.client(String(w.dropFirst())).windowID)" : String(w)
                }
                gets.append((line, Facit.answer(mango.json(mango.mmsg(["get"] + words)))))
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
            for id in mango.wlroots.closed { if let c = mango.server.clientByWindowID(id) { mango.server.handleClientUnmap(c) } }
            mango.wlroots.closed = []
            mango.frame()
        }
        return (answers, gets)
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

/// A config file of Tests/MangoFacit/configs (.conf or .toml) and how mango 0.18.5 judged it: `mango -c <file> -p`, its
/// exit and its errors as it printed them.
package struct ConfigFacit {
    /// One mango_error: its tag, its message and the line report_config_line_error named (nil for none).
    package struct Error: Equatable, CustomStringConvertible {
        package var tag: String
        package var message: String
        package var line: Int?
        package var description: String { "[\(tag)]: \(message)" + (line.map { " (line \($0))" } ?? "") }
    }

    package let name: String
    package let url: URL
    package let exit: Int
    package let errors: [Error]

    package static var all: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Facit.directory.appendingPathComponent("configs").path)) ?? []
        return files.filter { $0.hasSuffix(".conf") || $0.hasSuffix(".toml") }.sorted()
    }

    package init(_ name: String) throws {
        self.name = name
        url = Facit.directory.appendingPathComponent("configs/\(name)")
        let data = try Data(contentsOf: Facit.directory.appendingPathComponent("facit/configs/\(name).json"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        exit = json["exit"] as! Int
        errors = ConfigFacit.errors(in: (json["output"] as! String).replacingOccurrences(of: "/configs/\(name)", with: name))
    }

    /// mango's output read back: `[ERROR]: <message>`, then `╰─[Index] <file>:<line>` and the line.
    static func errors(in output: String) -> [Error] {
        var errors: [Error] = []
        var message: [String] = []
        func end() {
            guard !errors.isEmpty, !message.isEmpty else { return }
            errors[errors.count - 1].message = message.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            message = []
        }
        for line in output.components(separatedBy: "\n") {
            if let tag = ["ERROR", "WARN"].first(where: { line.hasPrefix("[\($0)]: ") }) {
                end()
                errors.append(Error(tag: tag, message: "", line: nil))
                message = [String(line.dropFirst(tag.count + 4))]
            } else if line.hasPrefix("╰─[Index] ") {
                // an [Index] with no message before it: mango_error printed an empty one
                if message.isEmpty { errors.append(Error(tag: "ERROR", message: "", line: nil)) }
                end()
                errors[errors.count - 1].line = Int(line.split(separator: ":").last ?? "")
            } else if !message.isEmpty {
                message.append(line)
            }
        }
        end()
        return errors
    }

    /// `# ours: drop <error>` and `# ours: add <error>` in the file: where we judge otherwise on purpose
    /// (a listed deviation), the error as `description` writes it.
    package var expected: [Error] {
        let lines = ((try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: "\n") ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let drop = Set(lines.compactMap { $0.hasPrefix("# ours: drop ") ? String($0.dropFirst(13)) : nil })
        let add = lines.compactMap { $0.hasPrefix("# ours: add ") ? String($0.dropFirst(12)) : nil }
        return errors.filter { !drop.contains($0.description) } + add.compactMap { ConfigFacit.errors(in: $0).first }
    }

    /// Our mango's judgement of the same file, read as mango -p reads it, with `port` the config's
    /// boundary (the macOS port's, as `mango -p` has it).
    package static func ours(_ url: URL, port: any ConfigPort) -> (exit: Int, errors: [Error]) {
        let saved = ConfigParser.port
        ConfigParser.port = port
        defer { ConfigParser.port = saved }
        let parsed = ConfigParser.parseConfig(fileAt: url)
        let errors = parsed.errors.map { e in
            Error(tag: e.verbosity == .error ? "ERROR" : "WARN",
                  message: e.message.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                      .replacingOccurrences(of: url.path, with: url.lastPathComponent)
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  line: e.reportsLine ? e.line : nil)
        }
        return (errors.isEmpty ? 0 : 1, errors)
    }
}
