// Compares the shipped config (Resources/config.conf) with mango's assets/config.conf:
// value differences of options both have active (for bindings: the dispatcher's arguments),
// mango options the port comments out,
// mango entries missing or out of order, and the port's own additions. Bindings are
// compared by dispatcher, since their keys differ on purpose (see the config's comments).
//
//   swift script/config-diff.swift <mango-dir> [port-config]      (make config-diff)
import Foundation

struct Entry { var id: String; var value: String; var active: Bool }

func entries(_ path: String, keepComments: Bool) -> [Entry] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!); exit(2)
    }
    return text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").compactMap { raw in
        var line = raw.trimmingCharacters(in: .whitespaces)
        var active = true
        if line.hasPrefix("#") {
            guard keepComments else { return nil }
            active = false
            line = String(line.drop { $0 == "#" || $0 == " " })
        }
        if let c = line.range(of: " #") { line = String(line[..<c.lowerBound]) }   // inline comment
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        if key.hasPrefix("bind") || key.hasSuffix("bind") {
            let f = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let skip = key == "gesturebind" ? 3 : 2
            guard f.count > skip else { return nil }
            // Matched by dispatcher; its arguments are the value (the keys differ on purpose).
            return Entry(id: "\(key):\(f[skip])", value: f[(skip + 1)...].joined(separator: ","), active: active)
        }
        if key == "tag_rule" || key == "layer_rule" { return Entry(id: "\(key)=\(value)", value: "", active: active) }
        return Entry(id: key, value: value, active: active)
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: config-diff.swift <mango-dir> [port-config]"); exit(2) }
let mango = entries(args[1] + "/assets/config.conf", keepComments: false)
let port = entries(args.count > 2 ? args[2] : "Resources/config.conf", keepComments: true)

// Walk mango's file in order, matching each entry with the next equal one in the port's.
var cursor = 0
var missing: [String] = []
var differ: [(String, String, String)] = []
var commented: [String] = []
var used = Set<Int>()
for m in mango {
    guard let i = port[cursor...].firstIndex(where: { $0.id == m.id }) else { missing.append(m.id); continue }
    cursor = i + 1
    used.insert(i)
    let p = port[i]
    if !p.active { commented.append(m.id) }
    else if p.value != m.value { differ.append((m.id, p.value, m.value)) }
}
let additions = port.indices.filter { !used.contains($0) && port[$0].active }.map { port[$0].id }

print("Values that differ (port, mango):")
for (k, p, m) in differ {
    print(k.contains(":") ? "  \(k) \(p)   mango: \(m)" : "  \(k)=\(p)   mango: \(m)")
}
if differ.isEmpty { print("  none") }
print("\nmango options commented out in the port (\(commented.count)):")
print("  " + (commented.isEmpty ? "none" : commented.joined(separator: " ")))
print("\nPort lines that are not in mango's file (\(additions.count)):")
print("  " + (additions.isEmpty ? "none" : additions.joined(separator: " ")))
print("\nmango entries missing from the port, or out of mango's order (\(missing.count)):")
print("  " + (missing.isEmpty ? "none" : missing.joined(separator: " ")))
exit(missing.isEmpty ? 0 : 1)
