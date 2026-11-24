import XCTest
@testable import Mango
@testable import Port

final class MangoCoverageTests: MangoTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func list(_ name: String) -> [String] {
        let url = repo.appendingPathComponent("Tests/mango-keys/\(name).txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("missing \(url.path); run script/mango-keys.sh <mango-dir> Tests/mango-keys")
            return []
        }
        return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func source(_ path: String) -> String {
        (try? String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    static var engineSources: String {
        let base = repo.appendingPathComponent("Sources")
        let skip = ["Mango/config/"]
        let engine = ["Mango/config/watcher.swift", "Mango/config/reapply.swift"]
        var out = ""
        let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        while let f = files?.nextObject() as? URL {
            guard f.pathExtension == "swift" else { continue }
            let rel = String(f.path.dropFirst(base.path.count + 1))
            if skip.contains(where: { rel.hasPrefix($0) }) && !engine.contains(rel) { continue }
            out += (try? String(contentsOf: f, encoding: .utf8)) ?? ""
            out += "\n"
        }
        return out
    }

    static func isRead(_ property: String, in text: String) -> Bool {
        text.range(of: "\\.\(property)\\b", options: .regularExpression) != nil
    }

    func testVersionIsRecorded() {
        let v = Self.source("Tests/mango-keys/VERSION")
        XCTAssertTrue(v.hasPrefix("mango "), "Tests/mango-keys/VERSION: \(v)")
    }

    func testEveryMangoOptionIsClassified() {
        let options = Self.list("options")
        XCTAssertGreaterThan(options.count, 200)
        var wrong: [String] = []
        for k in options {
            switch MangoCompat.status(ofOption: k) {
            case .implemented, .noEffect, .ignored: break
            case .unknown, .keyword, .portExtension: wrong.append(k)
            }
        }
        XCTAssertEqual(wrong, [], "mango options without a class in MangoCompat")
    }

    func testEveryMangoOptionLoadsWithoutUnknownKeyword() {
        var unknown: [String] = []
        for k in Self.list("options") {
            let parsed = ConfigParser.parse(text: "\(k)=1\n", baseDirectory: nil, fileName: "t")
            if parsed.errors.contains(where: { $0.message.hasPrefix("Unknown keyword") }) { unknown.append(k) }
        }
        XCTAssertEqual(unknown, [])
    }

    func testEveryMangoKeywordIsHandled() {
        var wrong: [String] = []
        for k in Self.list("keywords") {
            switch MangoCompat.status(ofOption: k) {
            case .keyword, .ignored: break
            default: wrong.append(k)
            }
            let parsed = ConfigParser.parse(text: "\(k)=x\n", baseDirectory: nil, fileName: "t")
            if parsed.errors.contains(where: { $0.message.hasPrefix("Unknown keyword") }) { wrong.append(k) }
        }
        XCTAssertEqual(wrong, [])
    }

    func testRuleKeywordsWithoutMacOSCounterpartAreIgnoredWhole() {
        for k in ["monitor_rule", "layer_rule", "device_rule"] {
            XCTAssertFalse(Self.list(k).isEmpty, "\(k).txt is empty")
            guard case .ignored = MangoCompat.status(ofOption: k) else {
                XCTFail("\(k) is not ignored"); continue
            }
        }
    }

    func testEveryWindowRuleFieldIsKnown() {
        let fields = Self.list("window_rule")
        XCTAssertGreaterThan(fields.count, 40)
        var unknown: [String] = []
        for f in fields {
            let errors = ConfigParser.parse(text: "window_rule=\(f):1,app_id:x", baseDirectory: nil, fileName: "t.conf").errors
            if errors.contains(where: { $0.message.hasPrefix("Unknown window rule option") }) { unknown.append(f) }
        }
        XCTAssertEqual(unknown, [])
    }

    func testEveryTagRuleFieldIsKnown() {
        var unknown: [String] = []
        for f in Self.list("tag_rule") {
            let errors = ConfigParser.parse(text: "tag_rule=id:1,\(f):1", baseDirectory: nil, fileName: "t.conf").errors
            if errors.contains(where: { $0.message.hasPrefix("Unknown tag rule option") }) { unknown.append(f) }
        }
        XCTAssertEqual(unknown, [])
    }

    func testDispatcherNamesMatchMango() {
        let mango = Set(Self.list("dispatchers"))
        XCTAssertGreaterThan(mango.count, 80)
        XCTAssertEqual(mango.subtracting(Dispatch.knownNames).sorted(), [], "mango dispatchers the port rejects")
        XCTAssertEqual(Dispatch.knownNames.subtracting(mango).sorted(), [], "names the port claims mango has")
    }

    /// Every name in mango's parse_func_name has a function; the ones macOS cannot do (MangoCompat) are
    /// the functions marked `not in mango` that do nothing else.
    @MainActor
    func testUnsupportedDispatchersAreTheMarkedFunctions() throws {
        var arg = Arg()
        for name in Dispatch.knownNames {
            XCTAssertNotNil(BindingParser.parseFuncName(name, &arg, "0", "0", "0", "0", "0"), name)
        }
        XCTAssertNil(BindingParser.parseFuncName("frobnicate", &arg, "0", "0", "0", "0", "0"))

        let parse = Self.source("Sources/Mango/config/binding_parse.swift")
        let functions = Self.source("Sources/Mango/dispatch/bind.swift") + Self.source("Sources/Mango/ext-protocol/hdr.swift")
            + Self.source("Sources/Mango/common/server.swift") + Self.source("Sources/Mango/switcher/switcher.swift")
            + Self.source("Sources/Mango/config/reapply.swift")
        let re = try NSRegularExpression(pattern: #"funcName == "([a-z_]+)" \{\n(?:\s*/\*.*\*/\n)?\s*`func` = MangoServer\.(\w+)\(_:\)"#)
        var withoutEffect = Set<String>()
        let matches = re.matches(in: parse, range: NSRange(parse.startIndex..., in: parse))
        XCTAssertEqual(matches.count, Dispatch.knownNames.count)
        for m in matches {
            let name = String(parse[Range(m.range(at: 1), in: parse)!])
            let fn = String(parse[Range(m.range(at: 2), in: parse)!])
            guard let start = functions.range(of: "func \(fn)(_ arg: Arg") else {
                XCTFail("no function \(fn) for \(name)")
                continue
            }
            let body = functions[start.upperBound...].prefix { $0 != "}" }
            let lines = body.split(separator: "\n").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.count == 2 && lines[0].hasPrefix("// not in mango:") && lines[1].hasPrefix("return") {
                withoutEffect.insert(name)
            }
        }
        XCTAssertEqual(withoutEffect.sorted(), MangoCompat.unsupportedDispatchers.keys.sorted())
    }

    func testPortExtensionsAreNotMangoNames() {
        let options = Set(Self.list("options"))
        let dispatchers = Set(Self.list("dispatchers"))
        for k in MangoCompat.portExtensionOptions.keys {
            XCTAssertFalse(options.contains(k), "\(k) is a mango option, not a port extension")
            XCTAssertTrue(ConfigOptions.hasSetter(k), "\(k) has no setter")
        }
        for d in MangoCompat.portDispatchers { XCTAssertFalse(dispatchers.contains(d)) }
        let extra = Set(ConfigOptions.knownKeys).subtracting(options).subtracting(MangoCompat.portExtensionOptions.keys)
        XCTAssertEqual(extra.sorted(), [], "options of the port that mango lacks and that are not marked as extensions")
    }

    func testClassificationNamesOnlyMangoNamesOnce() {
        let options = Set(Self.list("options"))
        var seen = Set<String>()
        for g in MangoCompat.ignoredOptionGroups {
            for k in g.keys {
                XCTAssertTrue(options.contains(k), "\(k) (\(g.name)) is not a mango option")
                XCTAssertFalse(ConfigOptions.hasSetter(k), "\(k) is ignored but has a setter")
                XCTAssertTrue(seen.insert(k).inserted, "\(k) is in two groups")
            }
        }
        for k in MangoCompat.optionsWithoutEffect.keys {
            XCTAssertTrue(options.contains(k), "\(k) is not a mango option")
            XCTAssertTrue(ConfigOptions.hasSetter(k), "\(k) is listed without effect but has no setter")
        }
        XCTAssertEqual(Set(MangoCompat.ignoredKeywords.keys).subtracting(Self.list("keywords")).sorted(), [])
        let fields = Set(Self.list("window_rule"))
        let ruleTables = Set(MangoCompat.ignoredWindowRuleFields.keys).union(MangoCompat.windowRuleFieldsWithoutEffect.keys)
        XCTAssertEqual(ruleTables.subtracting(fields).sorted(), [])
        XCTAssertTrue(Set(MangoCompat.ignoredWindowRuleFields.keys).isDisjoint(with: MangoCompat.windowRuleFieldsWithoutEffect.keys))
        XCTAssertEqual(Set(MangoCompat.unsupportedDispatchers.keys).subtracting(Self.list("dispatchers")).sorted(), [])
    }

    /// Read as mango reads them, with no effect here: the warning for the opacities, and no_size_hint
    /// before a size hint macOS does not give.
    static let readOnlyToWarn: Set<String> = ["focused_opacity", "unfocused_opacity", "no_size_hint"]

    func testOptionsWithoutEffectAreExactlyTheUnreadOnes() throws {
        let setters = Self.source("Sources/Mango/config/option_defs.swift")
        let engine = Self.engineSources
        let re = try NSRegularExpression(pattern: #"t\["([a-z_0-9]+)"\] = \w+\(\\\.(\w+)"#)
        var unreadButNotListed: [String] = [], listedButRead: [String] = []
        for m in re.matches(in: setters, range: NSRange(setters.startIndex..., in: setters)) {
            let key = String(setters[Range(m.range(at: 1), in: setters)!])
            let prop = String(setters[Range(m.range(at: 2), in: setters)!])
            let read = Self.isRead(prop, in: engine) && !Self.readOnlyToWarn.contains(key)
            let listed = MangoCompat.optionsWithoutEffect[key] != nil
            if !read && !listed { unreadButNotListed.append(key) }
            if read && listed { listedButRead.append(key) }
        }
        XCTAssertEqual(unreadButNotListed, [], "options the engine never reads: add them to optionsWithoutEffect")
        XCTAssertEqual(listedButRead, [], "options the engine reads: remove them from optionsWithoutEffect")
    }

    func testWindowRuleFieldsWithoutEffectAreExactlyTheUnreadOnes() throws {
        let parser = Self.source("Sources/Mango/config/option_defs.swift")
        let engine = Self.engineSources
        let re = try NSRegularExpression(pattern: #"key == "([a-z_]+)" \{\n\s*rule\.(\w+) ="#)
        var unreadButNotListed: [String] = [], listedButRead: [String] = []
        let start = parser.range(of: "func parseWindowRule(")!.lowerBound
        let end = parser.range(of: "func parseDeviceRule(")!.lowerBound
        let body = String(parser[start..<end])
        for m in re.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            let field = String(body[Range(m.range(at: 1), in: body)!])
            let prop = String(body[Range(m.range(at: 2), in: body)!])
            let read = Self.isRead(prop, in: engine) && !Self.readOnlyToWarn.contains(field)
            let listed = MangoCompat.windowRuleFieldsWithoutEffect[field] != nil
            if !read && !listed { unreadButNotListed.append(field) }
            if read && listed { listedButRead.append(field) }
        }
        XCTAssertEqual(unreadButNotListed, [], "window-rule fields the engine never reads: add them to windowRuleFieldsWithoutEffect")
        XCTAssertEqual(listedButRead, [], "window-rule fields the engine reads: remove them from windowRuleFieldsWithoutEffect")
    }

    func testTheTalliesAddUpToMangosNames() {
        let options = Self.list("options")
        let o = MangoCompat.optionTally
        XCTAssertEqual(o.total, options.count)
        XCTAssertEqual(o.works, options.filter { MangoCompat.status(ofOption: $0) == .implemented }.count)

        let fields = Self.list("window_rule")
        XCTAssertEqual(MangoCompat.mangoWindowRuleFieldCount, fields.count)
        let w = MangoCompat.windowRuleTally
        XCTAssertEqual(w.works, fields.filter { MangoCompat.windowRuleNote($0) == nil }.count)

        let keywords = Self.list("keywords")
        XCTAssertEqual(MangoCompat.mangoKeywordCount, keywords.count)
        XCTAssertEqual(MangoCompat.keywordTally.works, keywords.filter { MangoCompat.ignoredKeywords[$0] == nil }.count)

        let d = MangoCompat.dispatcherTally
        XCTAssertEqual(d.total, Self.list("dispatchers").count)
        XCTAssertTrue(MangoCompat.dispatchersNotYet.isSubset(of: Set(MangoCompat.unsupportedDispatchers.keys)))
    }

    func testNotesNameWhatHasNoEffect() {
        let text = """
        blur=1
        gesture_live=1
        chutney_hyper_modifier=super+ctrl
        gesture_swipe_distance=300
        bind=SUPER,a,chutney_launch_or_focus,com.apple.Safari
        window_rule=no_shadow:1,shield_when_capture:1,is_floating:1,app_id:x
        monitor_rule=name:eDP-1,scale:2
        """
        let parsed = ConfigParser.parse(text: text, baseDirectory: nil, fileName: "t")
        XCTAssertEqual(parsed.errors, [])
        let byName = Dictionary(grouping: parsed.notes, by: \.name)
        XCTAssertEqual(byName["blur"]?.first?.kind, .noEffect)
        XCTAssertNil(byName["gesture_live"], "works: no note")
        XCTAssertEqual(byName["chutney_hyper_modifier"]?.first?.kind, .portExtension)
        XCTAssertNil(byName["gesture_swipe_distance"], "works: no note")
        XCTAssertEqual(byName["chutney_launch_or_focus"]?.first?.kind, .portExtension)
        XCTAssertNotNil(byName["window_rule no_shadow"])
        XCTAssertNotNil(byName["window_rule shield_when_capture"])
        XCTAssertNil(byName["window_rule is_floating"])
        XCTAssertEqual(byName["monitor_rule"]?.first?.kind, .noEffect)
        XCTAssertEqual(byName["blur"]?.first?.line, 1)
    }

    func testMisspeltIgnoredKeyIsUnknownLikeInMango() {
        let parsed = ConfigParser.parse(text: "cursor_sise=24\nblurr=1\n", baseDirectory: nil, fileName: "t")
        XCTAssertEqual(parsed.errors.map(\.message.plain), ["Unknown keyword: cursor_sise", "Unknown keyword: blurr"])
    }

    func testListIgnoredMentionsEveryIgnoredName() {
        let md = MangoCompat.markdown()
        for g in MangoCompat.ignoredOptionGroups { for k in g.keys { XCTAssertTrue(md.contains("`\(k)`"), k) } }
        for k in MangoCompat.optionsWithoutEffect.keys { XCTAssertTrue(md.contains("`\(k)`"), k) }
        for k in MangoCompat.unsupportedDispatchers.keys { XCTAssertTrue(md.contains("`\(k)`"), k) }
        for k in MangoCompat.portExtensionOptions.keys { XCTAssertTrue(md.contains("`\(k)`"), k) }
    }
}
