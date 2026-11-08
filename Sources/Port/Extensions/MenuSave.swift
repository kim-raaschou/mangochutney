import Foundation
import Mango

public enum MenuSave {
    public static func url(_ config: Config, configURL: URL) -> URL? {
        let path = config.chutneyMenuConfig
        guard !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return configURL.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL
    }

    static let header = """
    # Written by Mango Chutney's menu (chutney_menu_config), not for editing: its choices,
    # read last by config.conf, so they win. Your own settings are in config.conf. To give a
    # key back to config.conf, delete its line here.
    """

    public static func set(_ key: String, _ value: String, in url: URL) {
        var lines = read(url)
        if let i = lines.lastIndex(where: { keyOf($0) == key }) {
            lines[i] = "\(key)=\(value)"
        } else {
            lines.append("\(key)=\(value)")
        }
        write(lines, to: url)
    }

    public static func setTagRule(tag: Int, _ field: String, _ value: String, in url: URL) {
        var lines = read(url)
        if let i = lines.lastIndex(where: { keyOf($0) == "tag_rule" && fields(of: $0)["id"] == "\(tag)" }) {
            var f = fieldList(of: lines[i]).filter { $0.0 != field }
            f.append((field, value))
            lines[i] = "tag_rule=" + f.map { "\($0.0):\($0.1)" }.joined(separator: ",")
        } else {
            lines.append("tag_rule=id:\(tag),\(field):\(value)")
        }
        write(lines, to: url)
    }

    static func read(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return lines(text).filter { keyOf($0) != nil }
    }

    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    nonisolated(unsafe) static var lastWritten: [String: String] = [:]

    public static func isOwnWrite(_ url: URL) -> Bool {
        guard let written = lastWritten[url.standardizedFileURL.path] else { return false }
        return (try? String(contentsOf: url, encoding: .utf8)) == written
    }

    static func write(_ lines: [String], to url: URL) {
        let text = header + "\n" + lines.joined(separator: "\n") + "\n"
        lastWritten[url.standardizedFileURL.path] = text
        try? text.write(to: url, atomically: false, encoding: .utf8)
    }

    static func keyOf(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return nil }
        return t[..<eq].trimmingCharacters(in: .whitespaces)
    }

    static func valueOf(_ line: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let eq = t.firstIndex(of: "=") else { return "" }
        var v = String(t[t.index(after: eq)...])
        if let hash = v.range(of: " #") { v = String(v[..<hash.lowerBound]) }
        return v.trimmingCharacters(in: .whitespaces)
    }

    static func fieldList(of line: String) -> [(String, String)] {
        valueOf(line).split(separator: ",").compactMap { part in
            let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return kv.count == 2 ? (kv[0], kv[1]) : nil
        }
    }

    static func fields(of line: String) -> [String: String] {
        Dictionary(fieldList(of: line), uniquingKeysWith: { _, b in b })
    }
}
