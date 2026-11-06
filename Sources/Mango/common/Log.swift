import Foundation

/**
 * This is just a wrapper around wlr_log_init.
 */
public func mangoLogInit(_ verbosity: WlrLogImportance) {
    wlrLogInit(verbosity)
}

private func mangoTagColor(_ verbosity: WlrLogImportance) -> String {
    switch verbosity {
    case .error: return "\u{1B}[1m\u{1B}[31m[ERROR]:\u{1B}[0m "
    case .info: return "\u{1B}[1m\u{1B}[33m[WARN]:\u{1B}[0m "
    case .debug: return "\u{1B}[1;32m[DEBUG]:\u{1B}[0m "
    default: return ""
    }
}

private func mangoTagPlain(_ verbosity: WlrLogImportance) -> String {
    switch verbosity {
    case .error: return "[ERROR]: "
    case .info: return "[WARN]: "
    case .debug: return "[DEBUG]: "
    default: return ""
    }
}

private func mangoEmit(_ log: Bool, _ tagged: Bool, _ verbosity: WlrLogImportance, _ file: String, _ line: Int,
                       _ message: () -> String) {
    if !log {
        let capture = configErrorStoreActive()
        let printable = verbosity == .error || verbosity == .info || verbosity == .debug
        let colorTag = tagged ? mangoTagColor(verbosity) : ""
        let text = message()

        if printable {
            if !colorTag.isEmpty { fputs(colorTag, stderr) }
            fputs(text, stderr)
        }

        if capture {
            let plainTag = tagged ? mangoTagPlain(verbosity) : ""
            configErrorStoreRecord(plainTag + text)
        }
    } else {
        wlrVlog(verbosity, "[\(file):\(line)] " + message())
    }
}

/**
 * Unified error/log output interface.
 * @param log if true, the message is sent through the wlroots logging system
 *            (a [file:line] prefix is automatically prepended); if false, the
 *            message is printed directly to stderr for the user.
 */
public func mangoError(_ log: Bool, _ verbosity: WlrLogImportance, _ message: @autoclosure () -> String,
                       file: String = #fileID, line: Int = #line) {
    mangoEmit(log, true, verbosity, file, line, message)
}

public func mangoErrorUntagged(_ verbosity: WlrLogImportance, _ message: @autoclosure () -> String) {
    mangoEmit(false, false, verbosity, "", 0, message)
}
