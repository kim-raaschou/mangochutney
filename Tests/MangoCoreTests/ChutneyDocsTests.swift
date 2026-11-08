import XCTest
@testable import Port
@testable import Mango

final class ChutneyDocsTests: MangoTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func pages() throws -> [(url: URL, text: String)] {
        try ["README.md", "docs/guide.md"].map { path in
            let url = root.appendingPathComponent(path)
            return (url, try String(contentsOf: url, encoding: .utf8))
        }
    }

    func testEveryPortKeyAndDispatcherHasItsRow() throws {
        let text = try pages().map(\.text).joined(separator: "\n")
        for name in MangoCompat.portExtensionOptions.keys.sorted() + MangoCompat.portDispatchers.sorted() {
            XCTAssertTrue(text.contains("| `\(name)` |"), "\(name) has no row in docs/guide.md")
        }
    }

    func testLinksBetweenPagesLeadToAPage() throws {
        let link = try Regex(#"\]\(([^)#:\s]+)(#[^)]*)?\)"#)
        for (url, text) in try pages() {
            for m in text.matches(of: link) {
                guard let path = m[1].substring.map(String.init) else { continue }
                let base = url.deletingLastPathComponent()
                let target = base.appendingPathComponent(path)
                let exists = FileManager.default.fileExists(atPath: target.path)
                    || FileManager.default.fileExists(atPath: target.path + ".md")
                XCTAssertTrue(exists, "\(url.lastPathComponent): \(path) leads nowhere")
            }
        }
    }
}
