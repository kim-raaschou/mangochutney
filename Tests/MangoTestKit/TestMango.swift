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

    package init(_ config: String = "", screen: Screen = TestMango.screen, file: StaticString = #filePath, line: UInt = #line) {
        server = MangoServer(configURL: URL(fileURLWithPath: "/nonexistent/config.conf"))
        let parsed = ConfigParser.parse(text: "animations=0\n" + config,
                                        baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()), fileName: "config.conf")
        for error in parsed.errors { XCTFail("config: \(error)", file: file, line: line) }
        server.config = parsed.config
        wlroots = FakeWlroots(server, screens: [screen])
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
        let c = Client(id: nextID, pid: 1, platform: FakeSurface(frame: frame, isFloatType: dialog), bundleId: "",
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

    /// One output frame on every monitor mango asked to draw on.
    package func frame() {
        let due = wlroots.takeFramesDue()
        for m in server.monitors where due.contains(m.screen.displayID) { server.handleOutputFrame(m) }
    }
}
