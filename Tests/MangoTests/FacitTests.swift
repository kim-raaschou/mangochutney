import XCTest
@testable import Mango
import MangoTestKit

/// mango's own answers. Each scenario in Tests/MangoFacit/scenarios was played on mango 0.18.5
/// (Tests/MangoFacit/record); played on our mango, mmsg must get the same answers.
@MainActor
final class FacitTests: XCTestCase {

    func testEveryScenarioAnswersAsMango() throws {
        XCTAssertFalse(Facit.all.isEmpty)
        for name in Facit.all {
            let facit = try Facit(name)
            let (ours, gets) = TestMango.play(facit)

            for (mango, us) in zip(facit.checks, ours) {
                compare(mango.clients, us.clients, "\(name).mango:\(us.line)", key: "title")
                compare(mango.monitors, us.monitors, "\(name).mango:\(us.line)", key: "name")
                compare([mango.cursor.merging(["name": "cursor"]) { a, _ in a }], [us.cursor.merging(["name": "cursor"]) { a, _ in a }],
                        "\(name).mango:\(us.line)", key: "name")
            }
            XCTAssertEqual(ours.count, facit.checks.count, "\(name).mango: checks")
            for (mango, us) in zip(facit.gets, gets) { differ(mango.answer, us.answer, "\(name).mango:\(us.line)") }
            XCTAssertEqual(gets.count, facit.gets.count, "\(name).mango: gets")
        }
    }

    /// mango's answer and ours to a `get`, field by field: `ipc-get.mango:9 all_tags.0.tags.2.client_count: mango 1, ours 0`.
    func differ(_ mango: Any?, _ ours: Any?, _ at: String) {
        if let m = mango as? [String: Any], let o = ours as? [String: Any] {
            for key in Set(m.keys).union(o.keys).sorted() { differ(m[key], o[key], at + (at.contains(" ") ? "." : " ") + key) }
        } else if let m = mango as? [Any], let o = ours as? [Any], m.count == o.count {
            for (i, (a, b)) in zip(m, o).enumerated() { differ(a, b, at + (at.contains(" ") ? "." : " ") + "\(i)") }
        } else if !(mango as AnyObject).isEqual(ours) {
            XCTFail("\(at): mango \(json(mango)), ours \(json(ours))")
        }
    }

    func json(_ value: Any?) -> String {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { return "nil" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Item by item and field by field, so a failure says what differs: `tile.mango:9 b.x: mango 1068, ours 10`.
    func compare(_ mango: [[String: Any]], _ ours: [[String: Any]], _ at: String, key: String) {
        let names = { (list: [[String: Any]]) in list.map { "\($0[key] ?? "?")" } }
        guard names(mango) == names(ours) else {
            return XCTFail("\(at) \(key)s: mango \(names(mango)), ours \(names(ours))")
        }
        for (m, o) in zip(mango, ours) {
            for field in m.keys.sorted() where !(m[field] as AnyObject).isEqual(o[field]) {
                XCTFail("\(at) \(m[key] ?? "").\(field): mango \(json(m[field])), ours \(json(o[field]))")
            }
        }
    }
}
