import Foundation

public enum Log {
    public static var verbose = false
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
/// mango mango_error_impl (log.c)
    public static func info(_ s: @autoclosure () -> String) { print("[\(fmt.string(from: Date()))] \(s())"); fflush(stdout) }
/// mango mango_error_impl (log.c)
    public static func debug(_ s: @autoclosure () -> String) { if verbose { info("debug: " + s()) } }
/// mango mango_error_impl (log.c)
    public static func error(_ s: @autoclosure () -> String) { info("error: " + s()) }
}
