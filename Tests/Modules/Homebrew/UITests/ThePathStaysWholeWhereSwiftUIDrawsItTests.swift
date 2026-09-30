import XCTest
import SwiftUI
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_UI

/// `ThePathInTheInstallSentenceStaysWholeTests` reads where TextKit breaks the
/// not-installed sentence, and says itself that TextKit is not the renderer the
/// page uses. This reads the renderer: the sentence is drawn by SwiftUI's
/// `Text` at the empty state's column and step, with every character clear but
/// the path, so the only ink on the drawing is `/opt/homebrew` — and a path
/// laid out whole is one line of ink, a path broken after a slash is two.
///
/// The column is `HelmEmptyState`'s text width (380 pt, private to it); the
/// face is `HelmText.rowTitle`, the one that view names.
@MainActor
final class ThePathStaysWholeWhereSwiftUIDrawsItTests: XCTestCase {

    private static let column: CGFloat = 380

    /// The path as the value spells it: plain, or with a word joiner after
    /// each slash.
    private static let spellings = ["/\u{2060}opt/\u{2060}homebrew", "/opt/homebrew"]

    private func lines(_ body: String, inking path: Bool) -> [RenderedLines.Line]? {
        var text = AttributedString(body)
        text.foregroundColor = path ? .clear : .black
        if path {
            guard let range = Self.spellings.lazy.compactMap({ text.range(of: $0) }).first else { return nil }
            text[range].foregroundColor = .black
        }
        let view = Text(text)
            .font(HelmText.rowTitle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Self.column)
        let mount = MountedRender(view, width: 600, height: 240, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(5)
        return RenderedLines.read(mount.host)
    }

    func testThePathIsOneLineOfInkInEveryLanguage() {
        AppLanguage.each { language in
            let body = HbStr.notInstalledBody(language: language)
            guard let sentence = lines(body, inking: false), let path = lines(body, inking: true) else {
                return XCTFail("\(language.rawValue): the drawing could not be read, or the value spells the path some other way")
            }
            XCTAssertGreaterThan(sentence.count, 1, "\(language.rawValue): the sentence drew on one line, so nothing was tested")
            XCTAssertEqual(path.count, 1,
                           "\(language.rawValue): /opt/homebrew is drawn on \(path.count) lines: \(path)")
        }
    }
}
