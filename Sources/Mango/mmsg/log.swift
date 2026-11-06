import Foundation

enum WlrLogImportance { case error, info, debug }

/// mango mango_error (common/log.c), with log false: printed to stderr for the user.
func mangoError(_ log: Bool, _ verbosity: WlrLogImportance, _ message: String) {
    let colorTag: String
    switch verbosity {
    case .error: colorTag = "\u{1B}[1m\u{1B}[31m[ERROR]:\u{1B}[0m "
    case .info: colorTag = "\u{1B}[1m\u{1B}[33m[WARN]:\u{1B}[0m "
    case .debug: colorTag = "\u{1B}[1;32m[DEBUG]:\u{1B}[0m "
    }
    FileHandle.standardError.write(Data((colorTag + message).utf8))
}
