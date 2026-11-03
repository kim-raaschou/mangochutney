import XCTest
@testable import Port
@testable import Mango

/// The port's docs (docs/chutney) keep up with the code: every chutney_ key and dispatcher has
/// its row, and the links between the pages lead somewhere.
final class ChutneyDocsTests: MangoTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/chutney")

    private func pages() throws -> [(url: URL, text: String)] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "md" } ?? []
        XCTAssertFalse(files.isEmpty, "no pages in \(root.path)")
        return try files.map { ($0, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// A key or dispatcher is documented by a table row of its own: "| `name` | …".
    func testEveryPortKeyAndDispatcherHasItsRow() throws {
        let text = try pages().map(\.text).joined(separator: "\n")
        for name in MangoCompat.portExtensionOptions.keys.sorted() + MangoCompat.portDispatchers.sorted() {
            XCTAssertTrue(text.contains("| `\(name)` |"), "\(name) has no row in docs/chutney")
        }
    }

    /// Relative links name a page without .md, as mango's docs do (or a file that exists).
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
