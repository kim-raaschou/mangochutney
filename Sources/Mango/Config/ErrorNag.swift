import Foundation

private func nagStripAnsi(_ src: String) -> String {
    var dst = String.UnicodeScalarView()
    var it = src.unicodeScalars.makeIterator()
    while let c = it.next() {
        if c == "\u{1B}" {
            guard let n = it.next() else { break }
            if n == "[" {
                while let t = it.next(), !(t.value >= 0x40 && t.value <= 0x7E) {}
            }
            continue
        }
        dst.append(c)
    }
    return String(dst)
}

private func nagFirstTarget() -> (path: String, line: Int)? {
    guard let file = fopen(configErrorStorePath(), "r") else { return nil }
    defer { fclose(file) }

    var raw: UnsafeMutablePointer<CChar>?
    var cap = 0
    defer { free(raw) }
    while getline(&raw, &cap, file) != -1, let raw {
        let line = nagStripAnsi(String(cString: raw))
        if let r = line.range(of: "[Index] ") {
            var p = line[r.upperBound...].drop { $0 == " " || $0 == "\t" }
            while let last = p.last, last == "\n" || last == "\r" || last == " " || last == "\r\n" { p.removeLast() }
            var lineOut = 0
            if let colon = p.lastIndex(of: ":"), let d = p[p.index(after: colon)...].first, d.isASCII, d.isNumber {
                lineOut = Int(atoi(String(p[p.index(after: colon)...])))
                p = p[..<colon]
            }
            return (String(p), lineOut)
        }
        if let r = line.range(of: "File \"") {
            let p = line[r.upperBound...]
            if let end = p.firstIndex(of: "\"") {
                var lineOut = 0
                if let lp = p[end...].range(of: "line ") { lineOut = Int(atoi(String(p[lp.upperBound...]))) }
                return (String(p[..<end]), lineOut)
            }
        }
    }
    return nil
}

private func nagShellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func nagEditCommand() -> String? {
    guard let target = nagFirstTarget(), !target.path.isEmpty else { return nil }
    var path = target.path
    let line = target.line

    if !path.hasPrefix("/"), let resolved = realpath(path, nil) {
        path = String(cString: resolved)
        free(resolved)
    }

    let env = ProcessInfo.processInfo.environment
    var editor = env["EDITOR"] ?? ""
    if editor.isEmpty { editor = env["VISUAL"] ?? "" }
    if editor.isEmpty { editor = "vi" }

    let name = editor.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? editor
    let base = String(name.prefix { $0 != " " })

    let pathArg = nagShellQuote(path)

    if line <= 0 { return "\(editor) \(pathArg)" }

    let lineArg = nagShellQuote("\(path):\(line)")

    let plus = ["vi", "vim", "nvim", "gvim", "emacs", "emacsclient", "nano"]
    let colon = ["hx", "helix", "micro", "zed"]
    let code = ["code", "codium"]

    if plus.contains(base) { return "\(editor) +\(line) \(pathArg)" }
    if colon.contains(base) { return "\(editor) \(lineArg)" }
    if code.contains(base) { return "\(editor) -g \(lineArg)" }
    return "\(editor) \(pathArg)"
}

private func nagPipeText() -> String {
    guard let text = try? String(contentsOfFile: configErrorStorePath(), encoding: .utf8) else { return "" }
    var lines = text.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    let total = lines.filter { !$0.isEmpty }.count

    var out = ""
    var shown = 0
    for line in lines where shown < 3 {
        if line.isEmpty { continue }
        out += line + "\n"
        shown += 1
    }

    let hidden = total - shown
    if hidden > 0 {
        out += "\u{2026} (+\(hidden) more line\(hidden == 1 ? "" : "s"))\n"
    }
    return out
}

extension MangoServer {
    private func nagSpawn() {
        guard started else { return }   // not in mango: started, for server.display

        system.nagKill()

        let edit = nagEditCommand()

        let out = selectedMonitor?.screen.name
        var argv = ["mangonag"]
        if let out { argv += ["-o", out] }
        argv += ["-t", "error", "-e", "top", "-l", "-s", "Close"]
        if let edit { argv += ["-b", "Edit", edit] }
        // not in mango: the port shows the bar in mango's process (mangonag is a Wayland client)
        system.nagSpawn(argv, input: nagPipeText())
    }

    func configErrorNagUpdate() {
        guard started else { return }   // not in mango: started, for server.event_loop

        var hasError = false
        if let file = fopen(configErrorStorePath(), "r") {
            if fgetc(file) != EOF { hasError = true }
            fclose(file)
        }

        system.nagKill()
        if hasError { nagSpawn() }
    }

    func configErrorNagInit() {
        configErrorNagUpdate()   // not in mango: at once, not on a 1 ms timer (setup has finished)
    }

    func configErrorNagDestroy() {
        system.nagKill()
    }
}
