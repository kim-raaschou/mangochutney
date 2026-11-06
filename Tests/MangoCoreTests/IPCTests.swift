import XCTest
import Foundation
import Darwin
@testable import Mango
@testable import Port

// MARK: - Raw socket client (runs off the main thread)

final class RawIPCClient {
    let fd: Int32
    private var buffer: [UInt8] = []

    init?(path: String) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            for (i, b) in bytes.enumerated() { dst[i] = UInt8(bitPattern: b) }
        }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard r == 0 else { close(fd); return nil }
    }

    deinit { close(fd) }

    func send(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
    }

    /// Next line without "\n"; nil on EOF/timeout.
    func readLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Tests

@MainActor
final class IPCTests: MangoTestCase {
    var rig: EngineRig!
    var server: IPCServer!
    var dp1: Monitor { rig.server.monitors[0] }
    var hdmi: Monitor { rig.server.monitors[1] }

    /// A window of `app` titled `title` on `m`, mapped as mango maps a new one.
    func add(_ id: CGWindowID, _ title: String, _ app: String, on m: Monitor) -> Client {
        rig.server.selectedMonitor = m
        let frame = CGRect(x: m.screen.frame.minX + 100, y: 100, width: 800, height: 600)
        rig.app.frames[id] = frame
        rig.server.mac.windowDiscovered(DiscoveredWindow(
            id: id, pid: getpid(), element: rig.app.element(for: id), bundleId: app, appName: app, title: title,
            subrole: "AXStandardWindow", isDialog: false, frame: frame, isMinimized: false,
            isFullscreen: false, isAppHidden: false))
        return rig.server.clientByIdAll(id)!
    }

    /// Two monitors, DP-1 and HDMI-A-1: Terminal (focused) and Safari on DP-1 tags 1 and 2,
    /// Notes on HDMI-A-1 tag 1; the pointer at (12.5, 40).
    override func setUp() async throws {
        try await super.setUp()
        try await MainActor.run {
            rig = EngineRig()
            rig.server.rebuildMonitors(screens: [
                Screen(displayID: 1, name: "DP-1", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                       workArea: CGRect(x: 0, y: 0, width: 2560, height: 1440), scale: 2, isMain: true),
                Screen(displayID: 2, name: "HDMI-A-1", frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
                       workArea: CGRect(x: 2560, y: 0, width: 1920, height: 1080), scale: 1.5, isMain: false),
            ])
            let c1 = add(1, "Terminal", "com.apple.Terminal", on: dp1)
            let c2 = add(2, "Safari \"quoted\"", "com.apple.Safari", on: dp1)
            c2.tags = 1 << 1
            c2.scrollerProportion = 0.8
            _ = add(3, "Notes", "com.apple.Notes", on: hdmi)
            rig.server.selectedMonitor = dp1
            rig.server.arrange(dp1, .none)
            rig.server.arrange(hdmi, .none)
            rig.server.clientFocus(c1)
            (rig.server.system as! FakeWindowSystem).fakePointer = CGPoint(x: 12.5, y: 40)
            let path = "/tmp/mango-test-\(getpid())-\(Int.random(in: 0..<100000)).sock"
            server = IPCServer(server: rig.server, loop: MainEventLoop(), socketPath: path, version: "0.0-test")
            try server.ipcInit()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            server.ipcCleanup()
            server = nil
            rig = nil
        }
        try await super.tearDown()
    }

    /// One-shot request on a background thread; the main run loop spins in `wait`.
    func query(_ line: String) -> String? {
        let path = server.socketPath
        let result = Box<String?>(nil)
        let done = expectation(description: line)
        DispatchQueue.global().async {
            if let c = RawIPCClient(path: path) {
                c.send(line)
                result.value = c.readLine()
                // get/dispatch close the connection after the reply.
                if c.readLine() != nil { result.value = "unexpected second line" }
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return result.value
    }

    func object(_ line: String?) throws -> [String: Any] {
        let data = try XCTUnwrap(line).data(using: .utf8)!
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSocketCreatedAndEnvironmentSet() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: server.socketPath))
        XCTAssertEqual(ProcessInfo.processInfo.environment["MANGO_INSTANCE_SIGNATURE"], server.socketPath)
        XCTAssertTrue(server.socketPath.utf8.count < 100)
    }

    func testSecondServerOnLiveSocketFails() {
        let other = IPCServer(server: rig.server, loop: MainEventLoop(), socketPath: server.socketPath, version: "x")
        XCTAssertThrowsError(try other.ipcInit())
    }

    func testGetVersion() throws {
        XCTAssertEqual(query("get version"), #"{"version":"0.0-test"}"#)
    }

    func testGetAllTags() throws {
        let line = try XCTUnwrap(query("get all-tags"))
        XCTAssertTrue(line.hasPrefix(#"{"all_tags":[{"monitor":"DP-1","tags":[{"index":1,"is_active":true,"is_urgent":false,"layout":"T","client_count":1}"#), line)
        let all = try XCTUnwrap(object(line)["all_tags"] as? [[String: Any]])
        XCTAssertEqual(all.map { $0["monitor"] as? String }, ["DP-1", "HDMI-A-1"])
        XCTAssertEqual((all[0]["tags"] as? [Any])?.count, 9)
    }

    func testGetTagsForMonitor() throws {
        let obj = try object(query("get tags HDMI-A-1"))
        XCTAssertEqual(obj["monitor"] as? String, "HDMI-A-1")
        XCTAssertEqual(obj["active_tags"] as? [Int], [1])
        XCTAssertEqual((obj["tags"] as? [Any])?.count, 9)
        XCTAssertEqual(query("get tags nope"), #"{"error":"monitor not found"}"#)
    }

    func testGetClient() throws {
        let line = try XCTUnwrap(query("get client 2"))
        XCTAssertTrue(line.hasPrefix(#"{"id":2,"pid":\#(getpid()),"foreign_toplevel_id":"2","title":"Safari \"quoted\"","appid":"com.apple.Safari","monitor":"DP-1","tags":[2]"#), line)
        let obj = try object(line)
        // mango stores the proportion as a C float and cJSON prints it as the double it widens to.
        XCTAssertEqual(try XCTUnwrap(obj["scroller_proportion"] as? Double), 0.8, accuracy: 1e-6)
        XCTAssertTrue(line.contains(#""scroller_proportion":0.800000011920929"#), line)
        XCTAssertEqual(obj["is_floating"] as? Bool, false)
        XCTAssertEqual(query("get client 42"), #"{"error":"client not found"}"#)
    }

    func testGetFocusingClient() throws {
        let obj = try object(query("get focusing-client"))
        XCTAssertEqual(obj["id"] as? Int, 1)
        XCTAssertEqual(obj["is_focused"] as? Bool, true)

        dp1.sel = nil
        XCTAssertEqual(query("get focusing-client"), #"{"error":"no focused client"}"#)
    }

    func testGetMonitorAndMisc() throws {
        let mon = try object(query("get monitor DP-1"))
        XCTAssertEqual(mon["scale"] as? Int, 2)
        XCTAssertEqual(mon["transform"] as? String, "normal", "mango 57a48e6")
        XCTAssertEqual(mon["active"] as? Bool, true)
        XCTAssertEqual(query("get monitor X"), #"{"error":"monitor not found"}"#)
        XCTAssertEqual(query("get cursorpos"), #"{"x":12.5,"y":40,"monitor":"DP-1"}"#)
        XCTAssertEqual(query("get keymode"), #"{"keymode":"default"}"#)
        XCTAssertEqual(query("get tag DP-1 2"),
                       #"{"monitor":"DP-1","tag_index":2,"is_active":false,"is_urgent":false,"client_count":1,"focused_client":false}"#)
        XCTAssertEqual(query("get tag DP-1 10"), #"{"error":"invalid monitor or tag index"}"#)
        XCTAssertEqual((try object(query("get all-monitors"))["monitors"] as? [Any])?.count, 2)
        XCTAssertEqual((try object(query("get all-clients"))["clients"] as? [Any])?.count, 3)
        XCTAssertEqual(query("get all-layers"), #"{"layers":[]}"#)
    }

    /// macOS display names contain spaces; `get tag` must take the last field as the index.
    func testGetTagWithSpacesInMonitorName() throws {
        rig.server.rebuildMonitors(screens: [
            Screen(displayID: 1, name: "Built-in Retina Display", frame: dp1.screen.frame, workArea: dp1.screen.workArea,
                   scale: 2, isMain: true),
            hdmi.screen,
        ])
        XCTAssertEqual(query("get tag Built-in Retina Display 2"),
                       #"{"monitor":"Built-in Retina Display","tag_index":2,"is_active":false,"is_urgent":false,"client_count":1,"focused_client":false}"#)
        XCTAssertEqual(query("get tag Built-in Retina Display,1"),
                       #"{"monitor":"Built-in Retina Display","tag_index":1,"is_active":true,"is_urgent":false,"client_count":1,"focused_client":true}"#)
        XCTAssertEqual(query("get tag Built-in Retina Display 10"), #"{"error":"invalid monitor or tag index"}"#)
        XCTAssertEqual(query("get tag Other Display 1"), #"{"error":"invalid monitor or tag index"}"#)
        XCTAssertEqual(query("get tag Built-in Retina Display"), #"{"error":"usage: get tag <monitor> <index>"}"#)
        XCTAssertEqual(query("get tag HDMI-A-1 1"),
                       #"{"monitor":"HDMI-A-1","tag_index":1,"is_active":true,"is_urgent":false,"client_count":1,"focused_client":true}"#)
        XCTAssertEqual(query("get tag HDMI-A-1"), #"{"error":"usage: get tag <monitor> <index>"}"#)
        XCTAssertEqual(query("get tag"), #"{"error":"unknown command"}"#)
    }

    func testDispatchWithTargetClient() throws {
        XCTAssertEqual(query("dispatch togglefloating client,2"), #"{"success":true}"#)
        XCTAssertTrue(rig.server.clientByIdAll(2)!.isFloating, "the target, not the focused window")
        XCTAssertFalse(rig.server.clientByIdAll(1)!.isFloating)
        XCTAssertEqual(query("dispatch killclient client,99"), #"{"error":"no client found"}"#)
        XCTAssertEqual(query("dispatch frobnicate,1"), #"{"error":"unknown function"}"#)
    }

    /// mango handle_command dispatch: a parked member is a target only for focusid; a known
    /// dispatcher answers success whatever it did.
    func testDispatchTargetsAParkedMemberOnlyForFocusid() throws {
        rig.server.clientGroupJoin(rig.server.clientByIdAll(2)!, into: rig.server.clientByIdAll(1)!)
        let parked = [1, 2].compactMap { rig.server.clientByIdAll($0) }.first { $0.groupParked }!
        XCTAssertEqual(query("dispatch togglefloating client,\(parked.id)"), #"{"error":"no client found"}"#)
        XCTAssertEqual(query("dispatch focusid client,\(parked.id)"), #"{"success":true}"#)
        XCTAssertEqual(query("dispatch focusdir,sideways"), #"{"success":true}"#)
    }

    /// mango ipc.c: group members say so, and a parked member is listed after its group.
    func testAllClientsListsGroupsAsMango() throws {
        rig.server.clientGroupJoin(rig.server.clientByIdAll(2)!, into: rig.server.clientByIdAll(1)!)
        let clients = try XCTUnwrap(object(query("get all-clients"))["clients"] as? [[String: Any]])
        XCTAssertEqual(Set(clients.compactMap { $0["id"] as? Int }), [1, 2, 3], "the parked member is listed")
        let group = clients.filter { ($0["is_group"] as? Bool) == true }
        XCTAssertEqual(group.count, 2)
        XCTAssertEqual(group.filter { ($0["is_group_focus"] as? Bool) == true }.count, 1)
    }

    func testUnknownCommand() {
        XCTAssertEqual(query("bogus"), #"{"error":"unknown command"}"#)
        XCTAssertEqual(query("get bogus"), #"{"error":"unknown command"}"#)
    }

    func testWatchTagsStreamsChanges() throws {
        let path = server.socketPath
        let first = expectation(description: "initial")
        let second = expectation(description: "update")
        let lines = Box<[String]>([])
        DispatchQueue.global().async {
            guard let c = RawIPCClient(path: path) else { first.fulfill(); second.fulfill(); return }
            c.send("watch tags DP-1")
            if let l = c.readLine() { lines.value.append(l) }
            first.fulfill()
            if let l = c.readLine() { lines.value.append(l) }
            second.fulfill()
        }
        wait(for: [first], timeout: 10)
        XCTAssertEqual(lines.value.count, 1)
        XCTAssertEqual(try object(lines.value.first)["active_tags"] as? [Int], [1])
        XCTAssertEqual(server.watcherCount, 1)

        // No change: nothing is sent.
        server.notifyChanged()
        // A change to another monitor only: still nothing for this watcher.
        rig.server.clientViewOnMonitor(1 << 2, on: hdmi)
        server.notifyChanged()
        // Spin the run loop so the coalesced flushes run before the real change.
        let spin = expectation(description: "spin")
        DispatchQueue.main.async { spin.fulfill() }
        wait(for: [spin], timeout: 5)

        rig.server.clientViewOnMonitor(1 << 1, on: dp1)
        server.notifyChanged()
        wait(for: [second], timeout: 10)
        XCTAssertEqual(lines.value.count, 2)
        let obj = try object(lines.value.last)
        XCTAssertEqual(obj["monitor"] as? String, "DP-1")
        XCTAssertEqual(obj["active_tags"] as? [Int], [2])
    }

    func testWatcherRemovedOnDisconnect() {
        let path = server.socketPath
        let got = expectation(description: "initial")
        DispatchQueue.global().async {
            if let c = RawIPCClient(path: path) {
                c.send("watch keymode")
                _ = c.readLine()
            } // client deallocated -> socket closed
            got.fulfill()
        }
        wait(for: [got], timeout: 10)
        let gone = expectation(description: "watcher removed")
        func poll(_ n: Int) {
            if server.watcherCount == 0 || n == 0 { gone.fulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll(n - 1) }
        }
        poll(200)
        wait(for: [gone], timeout: 10)
        XCTAssertEqual(server.watcherCount, 0)
    }

    // MARK: Pure parsing

    func testParseDispatch() {
        func p(_ s: String) -> (Dispatch, ClientID?) { IPCRequest.parseDispatch(s) }
        XCTAssertEqual(p("togglefloating").0, Dispatch(name: "togglefloating"))
        XCTAssertEqual(p("movewin,10,100 client,4").1, 4)
        XCTAssertEqual(p("movewin,10,100 client,4").0, Dispatch(name: "movewin", args: ["10", "100"]))
        XCTAssertEqual(p("client,7,focusdir,left").1, 7)
        XCTAssertEqual(p("client,7,focusdir,left").0, Dispatch(name: "focusdir", args: ["left"]))
        XCTAssertNil(p("movewin,client,abc").1)
        XCTAssertEqual(p("spawn,sh -c 'echo a,b',x").0, Dispatch(name: "spawn", args: ["sh -c 'echo a,b',x"]))
        XCTAssertEqual(p("spawn_shell,echo hi").0, Dispatch(name: "spawn_shell", args: ["echo hi"]))
        // mango combine_args_until_empty: trimmed tokens, up to the first "0".
        XCTAssertEqual(p("spawn,foo,0,bar").0, Dispatch(name: "spawn", args: ["foo"]))
        XCTAssertEqual(p("spawn,a , b").0, Dispatch(name: "spawn", args: ["a,b"]))
        XCTAssertEqual(p("spawn_on_empty,foo --a=1,2,4").0, Dispatch(name: "spawn_on_empty", args: ["foo --a=1,2", "4"]))
        XCTAssertEqual(p("toggle_named_scratchpad,foot,none,foot -a x,y").0,
                       Dispatch(name: "toggle_named_scratchpad", args: ["foot", "none", "foot -a x,y"]))
        XCTAssertEqual(p("setoption,a,b,c,d,e,f").0, Dispatch(name: "setoption", args: ["a", "b", "c", "d", "e,f"]))
        if case .dispatch(let d, _) = IPCRequest.parse("dispatch,view,2\n") {
            XCTAssertEqual(d, Dispatch(name: "view", args: ["2"]))
        } else { XCTFail("dispatch,view should parse as dispatch") }
        XCTAssertEqual(IPCRequest.parse("watch client 5"), .watch(IPCWatch(kind: .client, clientID: 5)))
        XCTAssertEqual(IPCRequest.parse("get,tags,DP-1"), .get("get tags DP-1"))
    }

    func testJSONNumberFormatting() {
        XCTAssertEqual(JSONValue.formatNumber(2), "2")
        XCTAssertEqual(JSONValue.formatNumber(1.5), "1.5")
        XCTAssertEqual(JSONValue.formatNumber(0.1), "0.1")
        XCTAssertEqual(JSONValue.formatNumber(-0.0), "0")
        XCTAssertEqual(JSONValue.escaped("a\"b\\c\n\u{1}"), #""a\"b\\c\n\u0001""#)
    }
}
