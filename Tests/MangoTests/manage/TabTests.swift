import XCTest
@testable import Mango
import MangoTestKit

/// mango's src/manage/tab.c
@MainActor
final class TabTests: XCTestCase {

    // MARK: tab_chain_focus

    func testTheChainHoldsAFullscreenMemberAndFocusesTheOneShownLast() {
        let mango = TestMango()
        mango.server.config.monocleTabMode = true
        mango.monitor.pertag.ltidxs[getMonCurtag(mango.monitor)] = .monocle
        let a = mango.map("a"), b = mango.map("b"), c = mango.map("c")
        c.isfloating = true
        mango.server.arrange(mango.monitor, false, false)
        a.isfullscreen = true
        mango.server.arrange(mango.monitor, false, false)

        XCTAssertTrue(mango.server.tabChain(mango.monitor).contains { $0 === a }, "fullscreen: a member")
        mango.server.clientFocus(b, true)
        XCTAssertTrue(mango.server.tabFocus(mango.monitor) === b)
        mango.server.clientFocus(c, true)
        XCTAssertTrue(mango.server.tabFocus(mango.monitor) === b, "the one shown last")
    }
}

private extension MangoServer {
    /// The tab chain on m, head first.
    func tabChain(_ m: Monitor) -> [Client] {
        guard let head = clients.first(where: { $0.mon === m && $0.tabPrev == nil && $0.tabNext != nil }) else { return [] }
        var out: [Client] = []
        var it: Client? = head
        while let x = it { out.append(x); it = x.tabNext }
        return out
    }

    /// The member of m's tab chain that is shown.
    func tabFocus(_ m: Monitor) -> Client? { tabChain(m).first { $0.isTabFocus } }
}
