// Builds Resources/config-mac.conf, the first start's "macOS" choice, from the shipped
// config and the Mac set of mango's bindings: config.conf with mango's key, mouse and scroll
// bindings commented out (gestures stay), mac-bindings.conf in their place among the port's
// keys, and Caps Lock as the Hyper key. MacConfigTests checks that the file is up to date.
//
//   swift script/mac-config.swift            (make mac-config)
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func read(_ name: String) -> String {
    guard let s = try? String(contentsOf: root.appendingPathComponent("Resources/\(name)"), encoding: .utf8) else {
        FileHandle.standardError.write("cannot read Resources/\(name)\n".data(using: .utf8)!); exit(2)
    }
    return s
}

let portMarker = "# Mango Chutney: the macOS port's own keys"
let config = read("config.conf").components(separatedBy: "\r\n")
let port = config.firstIndex { $0.hasPrefix(portMarker) } ?? config.endIndex

var lines: [String] = []
var marked = false
for (i, line) in config.enumerated() {
    if i < port, ["bind=", "mousebind=", "axisbind="].contains(where: line.lowercased().hasPrefix) {
        if !marked { lines.append("# Mango Chutney: these are on Hyper, among the port's keys below.") }
        marked = true
        lines.append("# " + line)
    } else {
        lines.append(line)
    }
}

// mac-bindings.conf without its opening comment, and without its closing note on gestures
// (mango's stay above).
var keys = read("mac-bindings.conf").components(separatedBy: "\n")
while let first = keys.first, first.hasPrefix("#") { keys.removeFirst() }
while let last = keys.last, last.isEmpty || last.hasPrefix("#") { keys.removeLast() }
keys.insert("# mango's keys on Hyper: $mod is Hyper, $mods Hyper+Shift", at: 0)
keys.append("")

guard let hyper = lines.firstIndex(where: { $0.hasPrefix("# chutney_hyper_modifier=") }),
      let own = lines.firstIndex(where: { $0.hasPrefix("# Your own settings") }) else {
    FileHandle.standardError.write("config.conf: the port's keys have changed\n".data(using: .utf8)!); exit(2)
}
lines.insert(contentsOf: keys, at: own)
lines.insert(contentsOf: [
    "# Caps Lock is Hyper. Hyper from Karabiner-Elements or a keyboard of its own: delete this line.",
    "xkb_rules_options=caps:hyper",
], at: hyper + 1)

try! lines.joined(separator: "\r\n").write(to: root.appendingPathComponent("Resources/config-mac.conf"),
                                          atomically: true, encoding: .utf8)
print("wrote Resources/config-mac.conf")
