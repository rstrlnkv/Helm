import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The palette is drawn in every language and both appearances, every cell has a name, and its width
/// is the same in all eight languages.** The cells are icons, so no language can make the capsule wider
/// than another: a width that differs between two languages is a worded label on some cell, which would
/// move the checkmark under the pointer when the language changes. Drawn offscreen, so what is read is the
/// size, the ink and the declaration; the glass does not composite in a render.
@MainActor
final class ThePaletteDrawsInEveryLanguageTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The palette's own width, the way the overlay asks for it: a hosting view with nobody telling it how wide to be.
    private func naturalSize() -> CGSize {
        let host = NSHostingView(rootView: EditorPalette(model: EditorBarModel()))
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize
    }

    func testTheWidthIsTheSameInEveryLanguageAndTheHeightIsTheFixedOne() {
        var widths: [AppLanguage: CGFloat] = [:]
        AppLanguage.each { language in
            let size = naturalSize()
            widths[language] = size.width
            XCTAssertGreaterThan(size.width, 300, "\(language): the palette came out \(size.width) pt wide")
            XCTAssertLessThan(size.width, 700, "\(language): the palette needs \(size.width) pt, more than a small screen can spare")
            XCTAssertEqual(size.height, EditorPalette.height, accuracy: 0.01, "\(language): the height is not the fixed one")
        }
        XCTAssertEqual(widths.count, AppLanguage.allCases.count, "the loop did not run in every language: \(widths)")
        let first = widths.values.first ?? 0
        for (language, width) in widths {
            XCTAssertEqual(width, first, accuracy: 0.01, "\(language): the palette is \(width) pt wide, the others \(first) — a cell carries a word: \(widths)")
        }
    }

    func testThePaletteHasSubstanceInEveryLanguageAndAppearance() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            AppLanguage.each { language in
                let size = naturalSize()
                let mount = MountedRender(EditorPalette(model: EditorBarModel()), width: size.width, height: size.height, appearance: appearance)
                mount.settle(20)
                XCTAssertGreaterThan(mount.ink() ?? 0, 0, "\(language) \(appearance.rawValue): nothing was drawn")
            }
        }
    }

    /// Every cell's name: none empty, no two the same in one language, and none is a key that fell through
    /// (a missing translation reads as its English key in a language that has none).
    func testEveryCellHasANameAndNoTwoShareOne() {
        AppLanguage.each { language in
            let names: [(String, String)] = [("undo", ScStr.undo), ("redo", ScStr.redo),
                                             ("pen", ScStr.tool(.pen)), ("pencil", ScStr.tool(.pencil)), ("highlighter", ScStr.tool(.highlighter)),
                                             ("done", ScStr.done), ("close", ScStr.closeEditor), ("more", HelmA11y.moreActions)]
                + AnnotationColor.allCases.map { ("ink \($0)", ScStr.ink($0)) }
            for (what, name) in names {
                XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): the \(what) cell has no name")
            }
            let cells = names.map(\.1)
            XCTAssertEqual(Set(cells).count, cells.count, "\(language): two cells share a name: \(names)")
        }
    }

    /// The source says what a render cannot: a cell is built from a name that is a `ScStr` or `HelmA11y`
    /// string, and **no cell is drawn with a word** (`Text`, `Label`, a title) — the first would be an unnamed
    /// control, the second would make the width differ by language.
    func testEveryCellIsBuiltFromAShippingNameAndDrawsNoWord() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        let cells = source.components(separatedBy: "GlassCell(").dropFirst()
        XCTAssertGreaterThanOrEqual(cells.count, 6, "the scan found \(cells.count) cells: undo, redo, objects, ⋯, done and ✕ are six")
        for cell in cells {
            let head = String(cell.prefix { $0 != "\n" })
            XCTAssertTrue(head.contains("name: ScStr.") || head.contains("name: HelmA11y."),
                          "a cell is built with a name that is not a shipping string: \(head)")
        }
        // `accessibilityLabel(` is a name, not a word: a drawn word is `Text(`, `Label(` or a titled button.
        for word in [" Text(", "(Text(", "{ Text(", " Label(", "(Label(", "{ Label(", "Button(\"", ".navigationTitle"] {
            XCTAssertFalse(source.contains(word), "the palette draws a word with \(word)")
        }
    }
}
