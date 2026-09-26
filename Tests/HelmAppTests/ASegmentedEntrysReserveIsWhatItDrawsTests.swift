import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A `.segmented` entry reserves what its switcher draws — no less, and no
/// more — and a page that declares other glyphs on the same bar is measured
/// again.**
///
/// `ASegmentedEntrysReserveCoversItsOwnGlyphsTests` bounds the reserve from
/// below only (`reserve + 0.5 >= drawn`), so a reserve measured in the wrong
/// form passes it as long as the wrong form is the wider one: measured
/// (tester, 2026-09-25) with the rig's `.icons` removed from
/// `SettingsToolbar.segmentedReserveWidth(_:)`, the rig reads the
/// environment's `.text` default and reserves the options' *words*, and that
/// file still stays green while the capsule claims room from the centre tabs
/// that nothing in it draws. The first case here is the other side of that
/// bound.
///
/// The second case feeds the input the per-bar files never do: one
/// `SettingsToolbar`, one attached bar, and a page that re-declares its
/// options with other glyphs. The reserve is cached per glyph set
/// (`SettingsToolbar.segmentedReserveCache`, keyed on the options' own
/// `symbol` array), so what this proves is that a set the cache has not seen
/// before is measured against what its switcher actually draws rather than
/// answering with whatever an earlier, different set left behind.
///
/// Only two or more options here — a one-option entry is its own case
/// (`AOneOptionSegmentedEntrysReserveCoversItTests`).
@MainActor
final class ASegmentedEntrysReserveIsWhatItDrawsTests: XCTestCase {

    /// Narrowest to widest drawn on this Mac: 73.0, 77.5, 81.5, 85.0 pt for
    /// the pairs, 108.0–162.0 pt for the longer sets.
    private static let sets: [[String]] = [
        ["minus", "ellipsis"], ["tablecells", "text.alignleft"],
        ["keyboard", "rectangle.split.3x1"], ["rectangle.3.group", "keyboard"],
        ["keyboard", "tablecells", "text.alignleft"],
        ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"],
    ]

    @MainActor
    private struct Bar {
        let toolbar: SettingsToolbar
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
        let token: String

        func declare(_ glyphs: [String]) {
            // Each option named after its own glyph, so a re-declaration that
            // changes a glyph changes its name as well and the switcher refills
            // (`HelmToolbarSwitcher.updateNSView`'s `namesChanged`) — what is
            // under test here is the reserve, not the refill.
            let options = glyphs.enumerated().map {
                HelmToolbarTab(id: "option\($0.offset)", title: $0.element, symbol: $0.element)
            }
            channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "viewMode", title: "View", options: options,
                                  selection: .constant("option0")),
                HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {},
            ]), token: token, generation: channel.nextGeneration())
            window.layoutIfNeeded()
        }

        /// The reserve the capsule holds for the entry and the width its
        /// switcher actually drew, read off the attached bar.
        func reading(_ context: String) throws -> (reserve: CGFloat, drawn: CGFloat, count: Int) {
            let hosting = try XCTUnwrap(window.toolbar?.items
                .first { $0.itemIdentifier.rawValue == "helm.actions" }?
                .view as? NSHostingView<HelmToolbarActionsCapsule>, "\(context): no hosted capsule")
            let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(context): precondition — no switcher drawn")
            let entry = try XCTUnwrap(hosting.rootView.model.declared.first { $0.id == "viewMode" },
                                      "\(context): no viewMode entry declared")
            return (hosting.rootView.reserveWidth(entry), control.frame.width, control.segmentCount)
        }
    }

    private func mountBar(_ token: String) -> Bar {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        model.selection = .module(token)
        return Bar(toolbar: toolbar, channel: channel, window: window, token: token)
    }

    func testTheReserveIsNeitherShortOfNorPastWhatTheSwitcherDraws() throws {
        var drawn: [CGFloat] = []
        for glyphs in Self.sets {
            let context = glyphs.joined(separator: " / ")
            let bar = mountBar("test.reserveIsWhatItDraws")
            bar.declare(glyphs)
            let reading = try bar.reading(context)
            XCTAssertEqual(reading.count, glyphs.count, "\(context): precondition — the switcher drew other segments")
            drawn.append(reading.drawn)
            XCTAssertEqual(reading.reserve, reading.drawn, accuracy: 0.5, """
                \(context): the segmented entry reserves \(reading.reserve) pt and draws \(reading.drawn) pt — \
                short, and a neighbour that hides resizes the capsule; past it, the centre tabs lose room to \
                nothing drawn
                """)
            bar.window.toolbar = nil
            _ = bar.toolbar
        }
        XCTAssertGreaterThan((drawn.max() ?? 0) - (drawn.min() ?? 0), 4, """
            precondition: the sets drew \(drawn) — too close together to say anything about glyph width
            """)
    }

    func testARedeclaredSetOfGlyphsIsMeasuredAfresh() throws {
        let bar = mountBar("test.reserveRedeclared")
        var readings: [(reserve: CGFloat, drawn: CGFloat, count: Int)] = []
        // Narrow, wide, narrow again — each declare on the same attached bar.
        for glyphs in [["minus", "ellipsis"], ["rectangle.3.group", "keyboard"], ["minus", "ellipsis"],
                       ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"]] {
            let context = "redeclared " + glyphs.joined(separator: " / ")
            bar.declare(glyphs)
            let reading = try bar.reading(context)
            XCTAssertEqual(reading.count, glyphs.count, "\(context): precondition — the switcher drew other segments")
            readings.append(reading)
            XCTAssertEqual(reading.reserve, reading.drawn, accuracy: 0.5, """
                \(context): after the page re-declared its options, the entry reserves \(reading.reserve) pt \
                and draws \(reading.drawn) pt — the reserve is left over from an earlier declaration
                """)
        }
        // The subject: the redeclares really did change what was drawn.
        XCTAssertGreaterThan(readings[1].drawn - readings[0].drawn, 4, """
            precondition: the two pairs drew \(readings[0].drawn) and \(readings[1].drawn) pt — a stale \
            reserve would look like a fresh one
            """)
        bar.window.toolbar = nil
        _ = bar.toolbar
    }
}
