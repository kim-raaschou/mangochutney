import XCTest
@testable import Mango
@testable import Port
import MangoTestKit

/// CLAUDE.md: the port's extensions are off when their key is absent and change nothing of mango's
/// behaviour when off. The same steps on mango alone and on mango with the port give the same mango.
@MainActor
final class ExtensionsOffTests: MangoTestCase {

    enum Step {
        case map(ClientID)
        case unmap(ClientID)
        case run(String, String = "")
    }

    /// Clients come, are focused, moved, floated and go, on two tags.
    let steps: [Step] = [
        .map(1), .map(2), .map(3), .map(4),
        .run("focusstack", "next"),
        .run("zoom"),
        .run("tag", "2"),
        .run("view", "2"),
        .map(5),
        .run("view", "1"),
        .run("togglefloating"),
        .run("focusstack", "prev"),
        .run("togglefullscreen"),
        .run("togglefullscreen"),
        .run("incnmaster", "1"),
        .run("setmfact", "+0.1"),
        .unmap(2),
        .run("focusstack", "next"),
    ]

    func testWithNoChutneyKeysThePortChangesNothingOfMango() {
        for layout in layouts.map(\.name) {
            let alone = TestMango(screen: EngineRig().screen)
            let ported = EngineRig()

            for step in [.run("setlayout", layout)] + steps {
                play(step, on: alone)
                play(step, on: ported)
            }

            XCTAssertEqual(MangoState(ported.server), MangoState(alone.server), layout)
        }
    }

    // MARK: Playing a step

    func play(_ step: Step, on mango: TestMango) {
        switch step {
        case .map(let id): mango.map("t\(id)")
        case .unmap(let id): mango.unmap("t\(id)")
        case .run(let name, ""): mango.run(name)
        case .run(let name, let arg): mango.run(name, arg)
        }
    }

    func play(_ step: Step, on rig: EngineRig) {
        switch step {
        case .map(let id): rig.map(id, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        case .unmap(let id): rig.server.mac.windowDestroyed(id: id)
        case .run(let name, let arg): rig.server.dispatch(Dispatch(name: name, args: arg.isEmpty ? [] : [arg]), rescan: false)
        }
    }
}

/// What mango holds, as a test compares it: its lists, its tags and each client's state.
struct MangoState: Equatable {
    struct ClientState: Equatable {
        var id: ClientID
        var tags: UInt32
        var geom: CGRect
        var isfloating: Bool
        var isfullscreen: Bool
    }
    var clients: [ClientState]
    var focusStack: [ClientID]
    var focused: ClientID?
    var viewedTags: UInt32
    var layout: String

    @MainActor
    init(_ server: MangoServer) {
        let m = server.selectedMonitor!
        clients = server.clients.map {
            ClientState(id: $0.id, tags: $0.tags, geom: $0.geom, isfloating: $0.isfloating, isfullscreen: $0.isfullscreen)
        }
        focusStack = server.focusStack
        focused = server.focused?.id
        viewedTags = m.tagset[m.seltags]
        layout = m.pertag.ltidxs[getMonCurtag(m)].name
    }
}
