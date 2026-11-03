// Logs, once a second, what can make key bindings feel dead: Secure Input (and who holds
// it), system load and the busiest process, and the event taps that see the keyboard
// (how many, whether mango's is enabled, which are disabled). Built and run by script/input-trace.sh.
import AppKit
import Carbon
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

func appName(_ pid: pid_t) -> String {
    if let n = NSRunningApplication(processIdentifier: pid)?.localizedName { return n }
    var buf = [CChar](repeating: 0, count: 256)
    return proc_name(pid, &buf, 256) > 0 ? String(cString: buf) : "pid \(pid)"
}

func secureInputHolder() -> pid_t? {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [[String: Any]] else { return nil }
    for u in users { if let p = (u["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, p > 0 { return p } }
    return nil
}

func busiest() -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-A", "-r", "-o", "%cpu=,comm="]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(2)
    return lines.map { l -> String in
        let parts = l.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return String(l) }
        return "\((parts[1] as NSString).lastPathComponent) \(parts[0])%"
    }.joined(separator: ", ")
}

let keyMask: UInt64 = (1 << 10) | (1 << 11) | (1 << 12)   // keyDown, keyUp, flagsChanged
let fmt = DateFormatter()
fmt.dateFormat = "HH:mm:ss"
let fine = DateFormatter()
fine.dateFormat = "HH:mm:ss.SSS"
var secureWas = IsSecureEventInputEnabled()

// Secure Input can be on for a fraction of a second (a Java password field taking and
// losing focus): check it ten times a second and print every change at once.
func watchSecureInput(for seconds: Double) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        let on = IsSecureEventInputEnabled()
        if on != secureWas {
            secureWas = on
            let who = on ? (secureInputHolder().map(appName) ?? "unknown") : ""
            print("\(fine.string(from: Date())) SECURE INPUT \(on ? "ON, held by \(who)" : "off")")
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
}

while true {
    var n: UInt32 = 0
    CGGetEventTapList(0, nil, &n)
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n))
    CGGetEventTapList(n, &taps, &n)
    // Active (filtering) taps that see the keyboard: every key passes through each of them.
    // Their latency figures are left out: mango's own measurement of key age showed keys
    // arriving in milliseconds while these figures claimed seconds, so they mislead.
    var active = 0
    var disabled: [String] = []
    var mangoTap = "none"
    for t in taps where t.eventsOfInterest & keyMask != 0 && t.options.rawValue == 0 {
        active += 1
        let name = appName(t.tappingProcess)
        if name.lowercased().hasPrefix("mango") { mangoTap = t.enabled ? "on" : "DISABLED" }
        if !t.enabled { disabled.append(name) }
    }
    let tapText = "mango tap \(mangoTap), \(active) active keyboard taps" + (disabled.isEmpty ? "" : ", disabled: \(disabled.joined(separator: " "))")
    let secure = IsSecureEventInputEnabled()
    let holder = secureInputHolder().map(appName) ?? "-"
    var load = [Double](repeating: 0, count: 3)
    getloadavg(&load, 3)
    print("\(fmt.string(from: Date())) secure=\(secure ? "ON(\(holder))" : "off") load=\(String(format: "%.1f", load[0])) top=[\(busiest())] \(tapText)")
    watchSecureInput(for: 1)
}
