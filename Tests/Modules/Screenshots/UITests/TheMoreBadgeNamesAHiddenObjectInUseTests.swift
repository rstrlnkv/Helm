import AppKit
import Foundation
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **⋯ shows a hidden object while it is in use, and shows nothing while the object stands on the row.** A hidden
/// pen that is raised has no cell to be lit; the badge on ⋯'s lower right is where the person sees it, and the accessibility
/// value says it by name. The same object on the row is lit in its own cell and ⋯ carries no badge for it.
///
/// Asked of every object of `EditorPalette.rowTools`, hidden alone and with every other, and of the tool being raised
/// among all `AnnotationTool.allCases`. The fallback symbol is asked through a tool that has no entry in the table of row
/// symbols (a glyph tool, which is no row object), because every row object of this tree has one.
@MainActor
final class TheMoreBadgeNamesAHiddenObjectInUseTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func model(tool: AnnotationTool?, hiding items: Set<PaletteItem>) -> EditorBarModel {
        let model = EditorBarModel()
        model.show(tool: tool, style: AnnotationStyle(), canUndo: false, canRedo: false)
        model.hide(items)
        return model
    }

    func testTheBadgeIsThereWhileTheObjectInUseIsHiddenAndNilWhileItIsOnTheRow() throws {
        XCTAssertFalse(EditorPalette.rowTools.isEmpty, "the subject: the row has objects")
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            let hidden = EditorPalette.moreBadge(for: model(tool: tool, hiding: [item]))
            XCTAssertEqual(hidden, EditorPalette.menuSymbol(ofRowTool: tool), "\(tool): hidden and in use, ⋯ shows not its symbol")
            XCTAssertNil(EditorPalette.moreBadge(for: model(tool: tool, hiding: [])), "\(tool): on the row, ⋯ carries a badge for it")
            // Every other object hidden: this one is still on the row, still no badge.
            let others = Set(EditorPalette.rowTools.filter { $0 != tool }.compactMap(EditorPalette.item(of:)))
            XCTAssertNil(EditorPalette.moreBadge(for: model(tool: tool, hiding: others)), "\(tool): another's hiding put it in the badge")
            // Another object in use while this one is hidden: this one is not what ⋯ shows.
            for other in EditorPalette.rowTools where other != tool {
                XCTAssertNil(EditorPalette.moreBadge(for: model(tool: other, hiding: [item])), "\(tool) hidden, \(other) in use: a badge")
            }
        }
    }

    func testTheAccessibilityValueFollowsTheBadgeInEveryLanguage() throws {
        AppLanguage.each { language in
            for tool in EditorPalette.rowTools {
                guard let item = EditorPalette.item(of: tool) else { return XCTFail("\(tool) has no item") }
                let hidden = model(tool: tool, hiding: [item])
                XCTAssertEqual(EditorPalette.moreValue(for: hidden), ScStr.tool(tool), "\(language) \(tool): the value is not its name")
                XCTAssertFalse((EditorPalette.moreValue(for: hidden) ?? "").isEmpty, "\(language) \(tool)")
                XCTAssertNil(EditorPalette.moreValue(for: model(tool: tool, hiding: [])), "\(language) \(tool): a value with the object on the row")
            }
        }
    }

    /// The badge and the value are one answer: a value stands exactly where a badge does, for every tool and every hiding.
    func testTheValueStandsExactlyWhereTheBadgeDoes() {
        let tools: [AnnotationTool?] = [nil] + AnnotationTool.allCases.map { Optional($0) }
        let everyItem = Set(PaletteItem.allCases)
        for hidden in [Set<PaletteItem>(), everyItem] {
            for tool in tools {
                let m = model(tool: tool, hiding: hidden)
                XCTAssertEqual(EditorPalette.moreBadge(for: m) == nil, EditorPalette.moreValue(for: m) == nil,
                               "tool \(String(describing: tool)), hidden \(hidden.count): the badge and the value disagree")
            }
        }
    }

    func testTheMenuItemAndTheBadgeShowOneSymbolAndItIsARealOne() throws {
        for tool in EditorPalette.rowTools {
            let item = try XCTUnwrap(EditorPalette.item(of: tool))
            let symbol = EditorPalette.menuSymbol(ofRowTool: tool)
            XCTAssertFalse(symbol.isEmpty, "\(tool): the symbol is empty")
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(tool): \(symbol) is no system symbol")
            let items = EditorMenu.items(for: model(tool: tool, hiding: [item]))
            guard case .tool(_, let inMenu, _, _)? = items.first else { return XCTFail("\(tool): the first item is no tool item") }
            XCTAssertEqual(inMenu, symbol, "\(tool): the menu item and the badge show different symbols")
            XCTAssertEqual(inMenu, EditorPalette.moreBadge(for: model(tool: tool, hiding: [item])))
        }
    }

    /// An object with no entry in the table gets the fallback: a glyph tool is no row object and has none.
    func testAnObjectWithNoEntryTakesTheFallbackSymbol() throws {
        let noEntry = AnnotationTool.allCases.filter { !EditorPalette.rowTools.contains($0) }
        XCTAssertFalse(noEntry.isEmpty, "the subject: a tool that is no row object")
        let fallback = EditorPalette.menuSymbol(ofRowTool: try XCTUnwrap(noEntry.first))
        XCTAssertFalse(fallback.isEmpty)
        XCTAssertNotNil(NSImage(systemSymbolName: fallback, accessibilityDescription: nil), "the fallback \(fallback) is no system symbol")
        for tool in noEntry { XCTAssertEqual(EditorPalette.menuSymbol(ofRowTool: tool), fallback, "\(tool)") }
        for tool in EditorPalette.rowTools {
            XCTAssertFalse(EditorPalette.menuSymbol(ofRowTool: tool).isEmpty, "\(tool)")
        }
    }

    /// A glyph tool's badge is as it was: its own symbol, whatever is hidden.
    func testAGlyphToolKeepsItsOwnBadgeWhateverIsHidden() {
        for tool in AnnotationTool.allCases where !EditorPalette.rowTools.contains(tool) {
            let own = EditorPalette.objects.first { $0.tool == tool && $0.place != .row }?.symbol
                ?? EditorPalette.afterSelect.first { $0.tool == tool }?.symbol
            for hidden in [Set<PaletteItem>(), Set(PaletteItem.allCases)] {
                XCTAssertEqual(EditorPalette.moreBadge(for: model(tool: tool, hiding: hidden)), own, "\(tool), hidden \(hidden.count)")
            }
        }
    }
}
