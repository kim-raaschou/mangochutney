import CoreGraphics
import Foundation
import XCTest
@testable import Mango

/// mango on one 1920x1080 monitor, with wlroots faked and no port. Its config is mango's defaults
/// with the test's lines on top; animations are off unless a line turns them on.
///
///     let mango = TestMango("new_is_master=0")
///     mango.map("a"); mango.map("b")
///     mango.run("focusstack", "next")
///     XCTAssertEqual(mango.focused, "a")
@MainActor
package final class TestMango {
    package let server: MangoServer
    package let wlroots: FakeWlroots

    nonisolated package static let screen = Screen(displayID: 1, name: "DP-1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                               workArea: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: 1, isMain: true)

    package convenience init(_ config: String = "", screen: Screen = TestMango.screen, file: StaticString = #filePath, line: UInt = #line) {
        self.init(config, screens: [screen], file: file, line: line)
    }

    /// mango started with these outputs, in the order the backend gives them.
    package init(_ config: String, screens: [Screen], file: StaticString = #filePath, line: UInt = #line) {
        server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/config.conf"))
        let port = ConfigParser.port
        ConfigParser.port = FakeKeymap()   // the binds' keys as xkb's us keymap has them
        defer { ConfigParser.port = port }
        let parsed = ConfigParser.parse(text: "animations=0\n" + config,
                                        baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()), fileName: "config.conf")
        for error in parsed.errors where error.verbosity == .error { XCTFail("config: \(error)", file: file, line: line) }   // mango starts on warnings
        server.config = parsed.config
        wlroots = FakeWlroots(server, screens: screens)
        server.system = wlroots
        server.started = true
        server.rebuildMonitors(screens: wlroots.screens)
    }

    // MARK: Monitors

    package var monitor: Monitor { server.selectedMonitor }

    /// A second monitor, to the right of the first.
    @discardableResult
    package func addMonitorOnTheRight(name: String = "DP-2") -> Monitor {
        let last = wlroots.screens.last!.frame
        let frame = CGRect(x: last.maxX, y: 0, width: 1920, height: 1080)
        wlroots.screens.append(Screen(displayID: CGDirectDisplayID(wlroots.screens.count + 1), name: name,
                                      frame: frame, workArea: frame, scale: 1, isMain: false))
        server.rebuildMonitors(screens: wlroots.screens)
        return server.monitors.first { $0.screen.name == name }!
    }

    // MARK: Clients

    private var nextID: ClientID = 1

    /// A new toplevel, mapped as mango's mapnotify maps it. The title names it in the tests.
    @discardableResult
    package func map(_ title: String, size: CGSize = CGSize(width: 800, height: 600), dialog: Bool = false) -> Client {
        let frame = CGRect(origin: .zero, size: size)
        let surface = FakeSurface(frame: frame, isFloatType: dialog)
        if dialog {   // a dialog has a fixed size: its min and max are its size
            surface.sizeHints.minWidth = size.width; surface.sizeHints.maxWidth = size.width
            surface.sizeHints.minHeight = size.height; surface.sizeHints.maxHeight = size.height
        }
        let c = Client(id: nextID, pid: 1, platform: surface, bundleId: "",
                       appName: title, title: title, monitor: server.selectedMonitor, tags: 0, frame: frame)
        nextID += 1
        server.handleClientMap(c)
        return c
    }

    package func unmap(_ title: String) { server.handleClientUnmap(client(title)) }

    package func client(_ title: String) -> Client {
        guard let c = server.clientsAll.first(where: { $0.title == title }) else { fatalError("no client \(title)") }
        return c
    }

    // MARK: Dispatchers

    /// A dispatcher as a key binding runs it: `run("focusstack", "next")` is `bind=…,focusstack,next`.
    package func run(_ name: String, _ args: String..., file: StaticString = #filePath, line: UInt = #line) {
        if let error = server.dispatch(Dispatch(name: name, args: args), rescan: false) {
            XCTFail("\(name): \(error)", file: file, line: line)
        }
    }

    // MARK: Keys

    private var keyboard = KeyboardState()
    /// The modifiers the keyboard holds, as a virtual keyboard tells mango after each key.
    private var held: Modifiers = []

    /// A key of a virtual keyboard: `key("super", down: true)`. mango sees the modifiers held before the
    /// key; a modifier key's own goes on after it.
    package func key(_ name: String, down: Bool) {
        guard let code = FakeKeymap.code(name) else { fatalError("no key \(name)") }
        let own = FakeKeymap.modifiers[code]
        var mods = held
        if let own { if down { mods.formUnion(own) } else { mods.subtract(own) } }
        server.publishInputState()
        let s = wlroots.input
        // keyboard.c leaves overcircle and the switcher on a mode key's release only for a real
        // keyboard (!group->virtual_keyboard)
        let k = KeyInput(keyCode: code, mods: mods, isDown: down, isRepeat: false, keyModifier: own)
        let d = Keyboard.handleKeyboardKey(k, state: &keyboard, bindings: s.bindings, mode: s.keymode,
                                           overcircleActive: false, switcherActive: false, tagCombo: s.tagCombo,
                                           cursorHideOnKeypress: s.cursorHideOnKeypress)
        server.handleKeyboardKey(d.actions)
        if !d.handled {
            let u = Keyboard.handleUnboundKey(k, state: &keyboard, jumpMode: s.jumpMode, isEscape: code == FakeKeymap.code("escape"),
                                              isJumpKey: s.jumpKeycodes.contains(code), globalKeys: [])
            if let a = u.action { server.handleKeyboardKey([a]) }
        }
        held = mods
    }

    // MARK: The pointer

    /// A virtual pointer's clock: its events are a second apart, as a test's steps are.
    private var time: UInt32 = 0
    private var axisApplyTime: UInt32 = 0
    private var axisApplyDir: Int32 = 0

    /// The pointer to `p`, as mango's handle_cursor_motion_absolute takes a virtual pointer's motion.
    package func pointer(to p: CGPoint) {
        time += 1000
        let from = wlroots.pointer
        wlroots.pointer = p
        cursorMoved()
        server.pointerProcessMotion(time, p.x - from.x, p.y - from.y)
    }

    /// wlroots draws the cursor itself on a headless output: a move damages the output it is on.
    private func cursorMoved() {
        if let m = server.monitorAtPoint(wlroots.pointer) { wlroots.outputScheduleFrame(m) }
    }

    /// The pointer moved by `d`, as mango's handle_cursor_motion takes a relative motion.
    package func move(by d: CGVector) {
        time += 1000
        wlroots.pointer = CGPoint(x: wlroots.pointer.x + d.dx, y: wlroots.pointer.y + d.dy)
        cursorMoved()
        server.handleCursorMotion(time, d.dx, d.dy)
    }

    /// A button down or up where the pointer is (0 left, 1 right, 2 middle). A virtual keyboard's
    /// modifiers do not count for the pointer (keyboard_hard_modifiers).
    package func button(_ button: Int, down: Bool) {
        time += 1000
        server.pointerProcessButtonPress(button: button, pressed: down, at: wlroots.pointer, mods: wlroots.keyboardHardModifiers())
    }

    /// One notch of a wheel, as handle_cursor_axis takes it: an axis binding runs, else nothing here.
    package func scroll(vertical: Bool, delta: Double) {
        time += 1000
        server.publishInputState()
        let s = wlroots.input
        guard let axis = Pointer.handleCursorAxis(vertical: vertical, delta: delta, timeMsec: time,
                                                  mods: wlroots.keyboardHardModifiers(), axisBindings: s.axisBindings,
                                                  mode: s.keymode, axisBindApplyTimeout: s.axisBindApplyTimeout,
                                                  axisApplyTime: &axisApplyTime, axisApplyDir: &axisApplyDir) else { return }
        wlroots.keyboardCancelPendingReleaseBind()
        if axis.fires { _ = server.dispatch(axis.binding.dispatch) }
    }

    // MARK: mmsg

    /// mango's answer to mmsg: `mmsg("get", "all-clients")` is `mmsg get all-clients`. The line goes
    /// through mango's ipc handle_command as mmsg sends it, and its answer comes back as mmsg prints it.
    @discardableResult
    package func mmsg(_ args: String...) -> String { mmsg(args) }

    @discardableResult
    package func mmsg(_ args: [String]) -> String {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { fatalError("socketpair") }
        defer { close(fds[0]); close(fds[1]) }
        ipc.handleCommand(fds[0], args.joined(separator: " ") + "\n")
        shutdown(fds[0], SHUT_WR)
        var answer: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65536)
        while case let n = read(fds[1], &buffer, buffer.count), n > 0 { answer += buffer[0..<n] }
        return String(decoding: answer, as: UTF8.self)
    }

    private lazy var ipc = IPCServer(server: server, loop: wlroots.eventLoop, socketPath: "")

    // MARK: What a test looks at

    /// The focused client's title.
    package var focused: String? { server.focused?.title }

    /// mango's clients list, by title.
    package var clients: [String] { server.clients.map(\.title) }

    /// mango's focus stack, by title, the last focused first.
    package var focusStack: [String] { server.focusStack.compactMap { server.clientByIdAll($0)?.title } }

    /// The tags viewed on the selected monitor.
    package var viewedTags: UInt32 { monitor.tagset[monitor.seltags] }

    /// A client's box, with its border (mango's geom).
    package func geom(_ title: String) -> CGRect { client(title).geom }

    /// The clients' commits of the sizes mango configured, then one output frame on every monitor mango
    /// asked to draw on.
    package func frame() {
        wlroots.commitConfigured()
        let due = wlroots.takeFramesDue()
        for m in server.monitors where due.contains(m.screen.displayID) { server.handleOutputFrame(m) }
    }
}
