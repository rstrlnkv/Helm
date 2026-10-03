import AppKit
import Foundation
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The palette's row draws the objects the person left on it and no others, measured, and the overlay reads that from
/// the store at the first release of an area.** A hidden object leaves the row — the capsule is exactly one cell narrower
/// for each — and `EditorChrome` places the palette by the width the overlay measured, so the width on the screen is the
/// width of the row it has. Read at the release, so the palette is measured with the row it will have; read again by the
/// next capture, so a pick made in the settings reaches the next editor.
///
/// No count is a number: the row is `EditorPalette.rowTools`, and each of its objects in turn is the one taken off.
@MainActor
final class ThePaletteShowsOnlyTheChosenToolsTests: XCTestCase {

    private let rig = HiddenPaletteRig()

    override func tearDown() {
        rig.close()
        super.tearDown()
    }

    private func width(hiding items: Set<PaletteItem>) -> CGFloat {
        let model = EditorBarModel()
        model.hide(items)
        return HiddenPaletteRig.naturalWidth(of: model)
    }

    // MARK: - The list the row is drawn from

    /// Every object of the row answers to an item, or it could never be taken off (and the page could not offer it); and
    /// two objects never answer to the same one.
    func testEveryObjectOfTheRowAnswersToOneItemAndNoItemIsAColourOrAWayOut() {
        XCTAssertFalse(EditorPalette.rowKinds.isEmpty, "the subject: the row has objects")
        let items = EditorPalette.rowKinds.map(EditorPalette.item(of:))
        XCTAssertFalse(items.contains { $0 == nil }, "a row object has no PaletteItem, so it can never be hidden or offered: \(EditorPalette.rowKinds)")
        XCTAssertEqual(Set(items.compactMap { $0 }).count, EditorPalette.rowKinds.count, "two row objects share one item")
        XCTAssertEqual(Set(items.compactMap { $0 }), Set(PaletteItem.allCases), "an item no object answers to is offered by nothing")
        let notAnItem = Set(AnnotationColor.allCases.map(\.rawValue)) .union(["colours", "colors", "undo", "redo", "more", "done", "close"])
        XCTAssertEqual(Set(PaletteItem.allCases.map(\.rawValue)).intersection(notAnItem), [], "a colour or a way out is an item: it can be hidden")
    }

    /// The menu glyph tools stand outside the row, so there is nothing to take them from: no item bears their name.
    func testAGlyphToolIsNoItem() {
        for object in EditorPalette.objects where object.place != .row {
            XCTAssertNil(PaletteItem(rawValue: object.tool.rawValue), "\(object.tool) stands in the ⋯ menu and is an item")
        }
    }

    // MARK: - The model

    func testOnlyTheHiddenObjectsLeaveTheRow() {
        let model = EditorBarModel()
        for tool in AnnotationTool.allCases { XCTAssertTrue(model.isOnRow(tool), "\(tool): off the row with nothing hidden") }
        for item in HiddenPaletteRig.rowItems {
            model.hide([item])
            for tool in AnnotationTool.allCases {
                let hidden = EditorPalette.item(of: tool) == item && EditorPalette.rowTools.contains(tool)
                XCTAssertEqual(model.isOnRow(tool), !hidden, "\(tool) with \(item) hidden")
            }
        }
        model.hide(Set(PaletteItem.allCases))
        for tool in AnnotationTool.allCases where !EditorPalette.rowTools.contains(tool) {
            XCTAssertTrue(model.isOnRow(tool), "\(tool) is no row object and every item hidden took it off")
        }
        model.hide([])
        XCTAssertTrue(AnnotationTool.allCases.allSatisfy(model.isOnRow), "an empty set did not bring the row back")
    }

    // MARK: - The width, by measure

    /// One cell narrower for each object taken off, whichever it is; the capsule is no other width.
    func testEachHiddenObjectTakesExactlyOneCellOfWidthOffTheCapsule() {
        let full = width(hiding: [])
        XCTAssertGreaterThan(full, 300, "the subject: the palette measured \(full)")
        for item in HiddenPaletteRig.rowItems {
            XCTAssertEqual(width(hiding: [item]), full - HiddenPaletteRig.cellWidth(of: item), accuracy: 0.5, "\(item) hidden")
        }
        var hidden: Set<PaletteItem> = []
        var taken: CGFloat = 0
        for item in HiddenPaletteRig.rowItems {
            hidden.insert(item)
            taken += HiddenPaletteRig.cellWidth(of: item)
            XCTAssertEqual(width(hiding: hidden), full - taken, accuracy: 0.5, "\(hidden.count) hidden")
        }
    }

    /// An item that is a case and not on the row (a later object this base does not draw yet) changes nothing.
    func testAnItemNoObjectAnswersToChangesNoWidth() {
        let drawn = Set(HiddenPaletteRig.rowItems)
        let undrawn = Set(PaletteItem.allCases).subtracting(drawn)
        XCTAssertEqual(width(hiding: undrawn), width(hiding: []), accuracy: 0.5, "an item with no object narrowed the row")
        XCTAssertEqual(width(hiding: Set(PaletteItem.allCases)), width(hiding: drawn), accuracy: 0.5)
    }

    /// The same hosting view, measured before and after: the row follows the model with nobody remounting it.
    func testTheRowFollowsTheModelOnTheSameHost() throws {
        let model = EditorBarModel()
        let host = NSHostingView(rootView: EditorPalette(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        let full = host.fittingSize.width
        let item = try XCTUnwrap(HiddenPaletteRig.rowItems.first)
        model.hide([item])
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, full - HiddenPaletteRig.cellWidth(of: item), accuracy: 0.5, "the row did not shrink when an object was hidden")
        model.hide([])
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, full, accuracy: 0.5, "the row did not grow back")
    }

    // MARK: - The overlay reads the store at the release

    func testTheOverlayHidesWhatTheStoreSaysAtTheFirstRelease() throws {
        for item in HiddenPaletteRig.rowItems {
            try rig.build(store: HiddenPaletteRig.store(hiding: [item]))
            XCTAssertEqual(rig.overlay?.palette.hidden, [item], "\(item) was picked hidden and the palette hides \(String(describing: rig.overlay?.palette.hidden))")
        }
        try rig.build(store: HiddenPaletteRig.store(hiding: PaletteItem.allCases))
        XCTAssertEqual(rig.overlay?.palette.hidden, Set(PaletteItem.allCases))
        try rig.build(store: HiddenPaletteRig.store(hiding: []))
        XCTAssertEqual(rig.overlay?.palette.hidden, [], "nothing picked and something is hidden")
    }

    /// An editor with no store (the harness's) and a store of garbage show the whole row.
    func testNoStoreAndAStoreOfStrangersShowTheWholeRow() throws {
        try rig.build(store: nil)
        XCTAssertEqual(rig.overlay?.palette.hidden, [], "no store, and an object is hidden")
        try rig.build(store: HiddenPaletteRig.store(hiding: [], also: ["colours", "undo", "arrow", "laser"]))
        XCTAssertEqual(rig.overlay?.palette.hidden, [], "a name that is no item hid something")
        XCTAssertTrue(AnnotationTool.allCases.allSatisfy { rig.overlay?.palette.isOnRow($0) ?? false })
    }

    /// The overlay measures the palette with the row it will have, and `EditorChrome` places by that width.
    func testTheOverlayMeasuresAndPlacesThePaletteWithTheRowItHas() throws {
        let (id, plain) = try rig.build(store: HiddenPaletteRig.store(hiding: []))
        let full = plain.paletteSize.width
        XCTAssertEqual(try XCTUnwrap(rig.overlay?.chrome(on: id)).palette.width, full, accuracy: 0.5, "the subject: placed by its measure")
        for item in HiddenPaletteRig.rowItems {
            let (id, view) = try rig.build(store: HiddenPaletteRig.store(hiding: [item]))
            XCTAssertEqual(view.paletteSize.width, full - HiddenPaletteRig.cellWidth(of: item), accuracy: 0.5, "\(item): the overlay measured the old row")
            XCTAssertEqual(try XCTUnwrap(rig.overlay?.chrome(on: id)).palette.width, view.paletteSize.width, accuracy: 0.5,
                           "\(item): the palette was placed by another width than it measured")
        }
        let (id2, none) = try rig.build(store: HiddenPaletteRig.store(hiding: PaletteItem.allCases))
        XCTAssertEqual(none.paletteSize.width, full - HiddenPaletteRig.rowItems.map(HiddenPaletteRig.cellWidth(of:)).reduce(0, +), accuracy: 0.5)
        let placed = try XCTUnwrap(rig.overlay?.chrome(on: id2)).palette
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 800).contains(placed), "the narrowed palette is off the display: \(placed)")
    }

    /// The next capture reads the store again: a pick made between two captures is in the second.
    func testAPickMadeBetweenTwoCapturesIsInTheSecond() throws {
        let store = HiddenPaletteRig.store(hiding: [])
        try rig.build(store: store)
        XCTAssertEqual(rig.overlay?.palette.hidden, [])
        let item = try XCTUnwrap(HiddenPaletteRig.rowItems.first)
        PaletteItems.set(item, shown: false, in: store)
        try rig.build(store: store)
        XCTAssertEqual(rig.overlay?.palette.hidden, [item], "the second capture did not read the pick")
        PaletteItems.set(item, shown: true, in: store)
        try rig.build(store: store)
        XCTAssertEqual(rig.overlay?.palette.hidden, [], "the pick taken back was kept")
    }

    /// The palette and the settings page read **one** answer, `PaletteItems.visible(store)`, not two expressions.
    func testThePaletteAndThePageAskTheSameFunction() throws {
        let overlay = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/CaptureOverlay.swift")
        let page = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/ScreenshotsSettingsPage.swift")
        XCTAssertTrue(SwiftSource.code(overlay).contains("PaletteItems.visible("), "the overlay does not read PaletteItems.visible")
        XCTAssertTrue(SwiftSource.code(page).contains("PaletteItems.visible("), "the page does not read PaletteItems.visible")
        XCTAssertFalse(SwiftSource.code(overlay).contains("paletteChoices"), "the overlay reads the key itself, beside PaletteItems")
    }
}
