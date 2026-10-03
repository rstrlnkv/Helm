import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The colours, Undo, Redo, ⋯, Done and ✕ are never taken off the palette, whatever the store says.** Owner: "Colours can
/// NOT be hidden; they are always on the palette." They are not `PaletteItem`s, so no table can name them; and the
/// palette that hides every object of its row is exactly the width of the row's cells shorter and still has the rest.
/// The fixture is the hostile one: `paletteChoices` holds `"colours": false`, `"undo": false`, … beside every object
/// hidden, and what is asked is what the palette drew, measured: the palette's width without the row, the colour
/// wheel's cell, the ⋯ cell, and ink in the render in every language and both appearances.
@MainActor
final class TheColoursCannotBeHiddenTests: XCTestCase {

    private let rig = HiddenPaletteRig()

    override func tearDown() {
        rig.close()
        AppLanguage.override = nil
        super.tearDown()
    }

    private static let wayOut = ["colours", "colors", "colour", "color", "swatches", "wheel", "undo", "redo", "more", "ellipsis", "done", "close", "x"]

    func testNoColourAndNoWayOutIsAnItemAndNoneIsReadFromTheTable() {
        for name in Self.wayOut { XCTAssertNil(PaletteItem(rawValue: name), "\(name) is an item: the palette can hide it") }
        for color in AnnotationColor.allCases { XCTAssertNil(PaletteItem(rawValue: color.rawValue), "the colour \(color) is an item") }
        let read = HiddenPaletteRig.store(hiding: PaletteItem.allCases, also: Self.wayOut + AnnotationColor.allCases.map(\.rawValue))
        XCTAssertEqual(PaletteItems.visible(read), [], "the subject: every item is hidden")
        XCTAssertEqual(read.boolTable(ScreenshotsSettings.Key.paletteChoices).count, PaletteItem.allCases.count + Self.wayOut.count
                       + AnnotationColor.allCases.count - Set(Self.wayOut).intersection(AnnotationColor.allCases.map(\.rawValue)).count,
                       "the subject: the hostile names are in the store")
        PaletteItems.set(.pen, shown: false, in: read)
        XCTAssertEqual(Set(read.boolTable(ScreenshotsSettings.Key.paletteChoices).keys), Set(PaletteItem.allCases.map(\.rawValue)),
                       "the next write kept names that are not items, or lost the picks of items")
    }

    /// The palette in every state of the row: the colour wheel's cell and ⋯'s cell are laid out, and the width is the full
    /// palette's less only the cells of the row's objects.
    func testTheColourGridAndTheWayOutStandWithEveryObjectHidden() throws {
        let full = EditorBarModel()
        let fullWidth = HiddenPaletteRig.naturalWidth(of: full)
        let rowWidth = CGFloat(EditorPalette.rowTools.count) * PaletteObject.width
        let model = EditorBarModel()
        model.hide(Set(PaletteItem.allCases))
        let host = NSHostingView(rootView: EditorPalette(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        XCTAssertEqual(size.width, fullWidth - rowWidth, accuracy: 0.5,
                       "the empty row took more than its own cells off: something else left the palette")
        XCTAssertEqual(size.height, EditorPalette.height, accuracy: 0.01)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<20 where model.wheelFrame == .zero || model.moreFrame == .zero { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertGreaterThan(model.wheelFrame.width, 20, "the colour wheel's cell was not laid out: \(model.wheelFrame)")
        XCTAssertGreaterThan(model.moreFrame.width, 20, "⋯'s cell was not laid out: \(model.moreFrame)")
        XCTAssertGreaterThan(model.moreFrame.minX, model.wheelFrame.maxX, "⋯ stands left of the colours")
        XCTAssertLessThan(model.moreFrame.maxX, size.width, "⋯ is outside the capsule")
        XCTAssertEqual(model.cellMidX.count, 0, "an object's cell was laid out in an empty row: \(model.cellMidX)")
    }

    /// Drawn in every language and appearance with the row empty: there is ink, and the width is the same in all languages.
    func testTheEmptyRowPaletteDrawsInEveryLanguageAndAppearanceAtOneWidth() {
        var widths: [CGFloat] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            AppLanguage.each { language in
                let model = EditorBarModel()
                model.hide(Set(PaletteItem.allCases))
                let size = HiddenPaletteRig.naturalWidth(of: model)
                widths.append(size)
                let mount = MountedRender(EditorPalette(model: model), width: size, height: EditorPalette.height, appearance: appearance)
                mount.settle(20)
                XCTAssertGreaterThan(mount.ink() ?? 0, 0, "\(language) \(appearance.rawValue): nothing was drawn with the row empty")
            }
        }
        XCTAssertEqual(widths.count, AppLanguage.allCases.count * 2, "the loop did not run in every language")
        XCTAssertEqual(Set(widths.map { ($0 * 2).rounded() }).count, 1, "the empty row's width differs by language: \(Set(widths))")
    }

    /// The overlay with every object hidden and the hostile table: a colour is picked, the colours open, undo and redo act,
    /// ⋯ has its menu, Done and ✕ leave — everything the row's absence must not have taken.
    func testTheOverlayStillTakesAColourAndHasItsWayOutWithTheRowEmpty() throws {
        let store = HiddenPaletteRig.store(hiding: PaletteItem.allCases, also: Self.wayOut)
        let (id, view) = try rig.build(store: store)
        XCTAssertEqual(rig.overlay?.palette.hidden, Set(PaletteItem.allCases), "the subject: every object hidden")
        XCTAssertTrue(view.paletteIsShown, "the palette is not on screen with the row empty")
        let chrome = try XCTUnwrap(rig.overlay?.chrome(on: id), "no palette")
        XCTAssertGreaterThan(chrome.palette.width, 150, "the empty-row palette collapsed: \(chrome.palette)")
        rig.overlay?.perform(.color(.blue))
        XCTAssertEqual(rig.overlay?.palette.picked.color, .blue, "a colour cannot be picked with the row empty")
        rig.overlay?.perform(.colours(anchorX: 40))
        XCTAssertTrue(rig.overlay?.palette.coloursOpen ?? false, "the colours do not open with the row empty")
    }

    /// Done and ✕, with the row empty and nothing drawn, finish the capture: the way out is there. Through the palette's own
    /// `perform`, the door a cell's click goes through.
    func testDoneAndTheCloseCrossStillLeaveWithTheRowEmpty() throws {
        try rig.build(store: HiddenPaletteRig.store(hiding: PaletteItem.allCases))
        rig.overlay?.palette.perform(.exit(.confirm))
        XCTAssertEqual(rig.results.count, 1, "Done did not finish the capture with the row empty: \(rig.results)")
        try rig.build(store: HiddenPaletteRig.store(hiding: PaletteItem.allCases))
        rig.overlay?.palette.perform(.close)
        XCTAssertEqual(rig.results.count, 1, "✕ did not finish the capture with the row empty: \(rig.results)")
    }
}
