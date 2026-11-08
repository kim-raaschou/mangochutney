import Foundation

public enum WlrLogImportance: Int, Sendable {
    case silent = 0, error = 1, info = 2, debug = 3
}

private var logImportance: WlrLogImportance = .error
private var startTime: TimeInterval = -1

private let verbosityColors: [WlrLogImportance: String] = [
    .silent: "", .error: "\u{1B}[1;31m", .info: "\u{1B}[1;34m", .debug: "\u{1B}[1;90m",
]
private let verbosityHeaders: [WlrLogImportance: String] = [
    .silent: "", .error: "[ERROR]", .info: "[INFO]", .debug: "[DEBUG]",
]

private func initStartTime() {
    if startTime >= 0 { return }
    startTime = ProcessInfo.processInfo.systemUptime
}

private func logStderr(_ verbosity: WlrLogImportance, _ message: () -> String) {
    initStartTime()
    if verbosity.rawValue > logImportance.rawValue { return }
    let ts = ProcessInfo.processInfo.systemUptime - startTime
    let sec = Int(ts)
    var out = String(format: "%02d:%02d:%02d.%03d ", sec / 60 / 60, sec / 60 % 60, sec % 60,
                     Int((ts - Double(sec)) * 1000))
    let colored = isatty(STDERR_FILENO) != 0
    out += colored ? verbosityColors[verbosity, default: ""] : verbosityHeaders[verbosity, default: ""] + " "
    out += message()
    if colored { out += "\u{1B}[0m" }
    out += "\n"
    fputs(out, stderr)
}

public func wlrLogInit(_ verbosity: WlrLogImportance) {
    initStartTime()
    logImportance = verbosity
}

public func wlrLogGetVerbosity() -> WlrLogImportance { logImportance }

public func wlrVlog(_ verbosity: WlrLogImportance, _ message: @autoclosure () -> String) {
    logStderr(verbosity, message)
}

public func wlrLog(_ verbosity: WlrLogImportance, _ message: @autoclosure () -> String,
                   file: String = #fileID, line: Int = #line) {
    logStderr(verbosity) { "[\(file):\(line)] " + message() }
}
