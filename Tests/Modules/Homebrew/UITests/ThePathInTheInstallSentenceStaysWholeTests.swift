import XCTest
import AppKit
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_UI

/// The sentence on the not-installed page names `/opt/homebrew`, and a person
/// looking at it has to recognise that path: a line that ends on `/opt/` and a
/// next line that begins with `homebrew.` shows it as two pieces. The typesetter
/// may break after a slash, and in Spanish it did, at the page's own column.
///
/// The column is `HelmEmptyState`'s text width (380 pt, private to it) and the
/// face is the body step; the lines are laid out with TextKit, which breaks
/// lines by the same rules SwiftUI's `Text` does but is not it — so this is a
/// reading of where the typesetter breaks the sentence, not a photograph of the
/// page, and a change of the column would have to be repeated here.
@MainActor
final class ThePathInTheInstallSentenceStaysWholeTests: XCTestCase {

    private static let column: CGFloat = 380
    private static let path = "/opt/homebrew"

    /// The lines the sentence breaks into at the page's column, each as the
    /// text it shows — the word joiners a value may carry are not drawn.
    private func lines(of text: String) -> [String] {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.preferredFont(forTextStyle: .body)])
        let container = NSTextContainer(size: NSSize(width: Self.column, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var result: [String] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            result.append((text as NSString).substring(with: characters)
                .replacingOccurrences(of: "\u{2060}", with: ""))
        }
        return result
    }

    func testTheSentenceNeverShowsThePathInTwoPieces() {
        AppLanguage.each { language in
            let body = HbStr.notInstalledBody(language: language)
            let shown = lines(of: body)
            XCTAssertGreaterThan(shown.count, 1, "\(language.rawValue): the sentence fits one line, so nothing was tested")
            XCTAssertTrue(shown.contains { $0.contains(Self.path) },
                          "\(language.rawValue): no line carries \(Self.path) whole: \(shown)")
        }
    }
}
