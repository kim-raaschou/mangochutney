import Darwin
import Foundation
import MmsgPort   // Port extension: not in mango (mmsg service, logs, reload, binds)

func usage() {
    print("Usage: mmsg <command> [args...]\n")
    print("One-shot queries (get):")
    print("  get version                              Show compositor version")
    print("  get cursorpos                            Show pointer position + monitor")
    print("  get keymode                              Show current keymode")
    print("  get keyboardlayout                       Show current keyboard layout")
    print("  get last_open_surface [monitor]          Show last open surface (default focused monitor)")
    print("  get monitor <name>                       Show monitor details")
    print("  get focusing-client                      Show focused client details")
    print("  get client <id>                          Show client details by ID")
    print("  get tag <monitor> <index>                Show tag details (1‑based index)")
    print("  get all-clients                          List all clients")
    print("  get all-monitors                         List all monitors")
    print("  get all-devices                          List physical input devices")
    print("  get all-layers                           List all open layer surfaces")
    print("  get all-tags                             List all tags (all monitors)")
    print("  get layouts                              List all available layouts")
    print("  get tags <monitor>                       List tags for a monitor")
    print("  dispatch <func>[,arg...] [client,<id>]   Call a compositor function")
    print("     <func> and arguments are separated by commas.")
    print("     Add 'client,<id>' at the beginning or end to target a specific client.")
    print("     Examples:")
    print("       dispatch togglefloating")
    print("       dispatch movewin,10,100")
    print("       dispatch movewin,10,100 client,4")
    print("Persistent streams (watch):")
    print("  watch monitor <name>                     Stream monitor changes")
    print("  watch focusing-client                    Stream focused client changes")
    print("  watch client <id>                        Stream client changes")
    print("  watch tags <monitor>                     Stream tag changes for a monitor")
    print("  watch all-monitors                       Stream all monitors changes")
    print("  watch all-tags                           Stream all tags changes")
    print("  watch all-clients                        Stream all clients changes")
    print("  watch all-devices                        Stream the last input device that triggered an event")
    print("  watch keymode                            Stream keymode changes")
    print("  watch keyboardlayout                     Stream keyboard layout changes")
    print("  watch last_open_surface [monitor]        Stream last open surface changes\n")
    print("Environment:")
    print("  MANGO_INSTANCE_SIGNATURE  IPC socket path (set by the compositor)\n")
    mmsgPortUsage()   // Port extension: not in mango
    print("Run 'mmsg --help', '-h' or 'help' to see this message.")
}

let argv = CommandLine.arguments
let argc = argv.count

if argc >= 2 && (argv[1] == "--help" || argv[1] == "-h" || argv[1] == "help") {
    usage()
    exit(EXIT_SUCCESS)
}

if argc < 2 {
    mangoError(false, .info,
               "Usage: mmsg <command> [args...]\n"
               + "  get <type> ...      one-shot request\n"
               + "  watch <type> ...    persistent stream\n")
    exit(EXIT_FAILURE)
}

if let rc = mmsgPortCommand(Array(argv.dropFirst())) { exit(rc) }   // Port extension: not in mango

// not in mango: without MANGO_INSTANCE_SIGNATURE the socket mango makes, /tmp/mango-<user>.sock
// (a program the Dock or Terminal starts is not mango's child)
let socketPath = ProcessInfo.processInfo.environment["MANGO_INSTANCE_SIGNATURE"] ?? "/tmp/mango-\(NSUserName()).sock"

let sock = socket(AF_UNIX, SOCK_STREAM, 0)
if sock < 0 {
    perror("socket")
    exit(EXIT_FAILURE)
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { dst in
    for (i, b) in socketPath.utf8.prefix(dst.count - 1).enumerated() { dst[i] = b }
}

let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
if connected < 0 {
    perror("connect")
    close(sock)
    exit(EXIT_FAILURE)
}

let cmdSize = 4096
var cmd: [UInt8] = []
for i in 1..<argc {
    let part = Array((argv[i] + (i == argc - 1 ? "" : " ")).utf8)
    if part.count >= cmdSize - cmd.count {
        mangoError(false, .error, "command too long.\n")
        close(sock)
        exit(EXIT_FAILURE)
    }
    cmd += part
}

if 1 >= cmdSize - cmd.count {
    mangoError(false, .error, "command too long to append newline.\n")
    close(sock)
    exit(EXIT_FAILURE)
}
cmd.append(10)

var one: Int32 = 1   // not in mango: SO_NOSIGPIPE, as macOS has no MSG_NOSIGNAL
setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
if send(sock, cmd, cmd.count, 0) < 0 {
    perror("send")
    close(sock)
    exit(EXIT_FAILURE)
}

guard let stream = fdopen(sock, "r") else {
    perror("fdopen")
    close(sock)
    exit(EXIT_FAILURE)
}

var line: UnsafeMutablePointer<CChar>? = nil
var len = 0
while getline(&line, &len, stream) != -1 {
    fputs(line!, stdout)
    fflush(stdout)
}

if ferror(stream) != 0 {
    perror("recv")
    free(line)
    fclose(stream)
    exit(EXIT_FAILURE)
}

free(line)
fclose(stream)
exit(EXIT_SUCCESS)
