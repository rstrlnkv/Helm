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
/// `SettingsToolbar.segmentedReserveWidth(_:look:)`, the rig reads the
/// environment's `.text` default and reserves the options' *words*, and that
/// file still stays green while the capsule claims room from the centre tabs
/// that nothing in it draws. The first case here is the other side of that
/// bound.
///
/// The second case feeds the input the per-bar files never do: one
/// `SettingsToolbar`, one attached bar, and a page that re-declares its
/// options with other glyphs. The reserve is cached per glyph set
/// (`SettingsToolbar.segmentedReserveCache`, keyed on the options' own
/// `symbol` array and the look the bar was built under), and what the row
/// holds is that the key carries the symbols: with them out of the key, a
/// re-declared set reserves the width of the first set measured — 90.0 pt
/// against 94.0 and against 186.0 under Flat — instead of its own.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds: it has no `helm.tabsLead` and no capped search field.
///
/// **Both looks, each row.** The bar's look is read when the bar is built
/// (`AppSettings.barAppearance`), and it names the cell the switcher wears:
/// Helm's `HelmFlatSegmentedCell` under Flat, AppKit's own under Liquid Glass
/// (`HelmBarAppearance.switcherCell`). The rows pin the settings
/// (`PinnedBarSettings`), set the look before each bar is built, assert from
/// the drawn control's cell that the look reached the bar, and print the look
/// with each reading.
///
/// **What "drawn" is in a row:** the frame width of the switcher's control on
/// the bar as it was built, or as the page re-declared it. Each `[reserve]`
/// line prints beside it the control's own `intrinsicContentSize.width`, the
/// cell's own size, which no row asserts. Under Flat the two agree on every
/// reading (90.0, 94.0, 94.0, 94.0, 140.0 and 186.0 pt for the six sets
/// below). Under AppKit's cell a fresh control's frame reads 73.0, 73.0, 73.0,
/// 74.0, 108.0 and 144.0 pt for them where the cell's own size reads 73.0,
/// 77.5, 81.5, 85.0, 117.5 and 162.0 pt, and the reserve is read after the same
/// first layout of a fresh control (`SwitcherMeasurementRig.measure`), so the
/// first row there compares two controls, the rig's own and the bar's, each on
/// its first layout.
///
/// Only two or more options here — a one-option entry is its own case
/// (`AOneOptionSegmentedEntrysReserveCoversItTests`).
@MainActor
final class ASegmentedEntrysReserveIsWhatItDrawsTests: XCTestCase {

    /// Narrowest to widest by the control's own size under AppKit's cell: 73.0, 77.5, 81.5, 85.0 pt for
    /// the pairs, 117.5 and 162.0 pt for the longer sets. None of it is asserted.
    private static let sets: [[String]] = [
        ["minus", "ellipsis"], ["tablecells", "text.alignleft"],
        ["keyboard", "rectangle.split.3x1"], ["rectangle.3.group", "keyboard"],
        ["keyboard", "tablecells", "text.alignleft"],
        ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"],
    ]

    private static let looks: [HelmBarAppearance] = [.flat, .liquidGlass]

    @MainActor
    private struct Bar {
        let toolbar: SettingsToolbar
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
        let token: String
        let look: HelmBarAppearance

        func declare(_ glyphs: [String]) {
            // Each option named after its own glyph, so a re-declaration that
            // changes a glyph changes its name as well. `HelmToolbarSwitcher.updateNSView`
            // refills when the option count moved (`countChanged`) and, the count
            // standing, when the drawn words differ, the selection moved, the names
            // changed (`namesChanged`), the glyphs changed (`symbolsChanged`) or the
            // attention dots changed. A re-declare here changes an option's name and
            // its glyph, so `namesChanged` or `symbolsChanged` refills it, and the
            // declare from two options to four refills by the count — what is under
            // test is the reserve, not the refill.
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
        /// switcher actually drew, read off the attached bar. The cell the
        /// control wears says whether the bar's look reached it.
        func reading(_ context: String) throws -> (reserve: CGFloat, drawn: CGFloat, count: Int) {
            let toolbar = try XCTUnwrap(window.toolbar, "\(context): the window wears no toolbar")
            let read = try ActionsCapsuleReading.read(toolbar, context: context)
            let control = try XCTUnwrap(read.host.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(context): precondition — no switcher drawn")
            let cell = try XCTUnwrap(control.cell, "\(context): precondition — the switcher has no cell")
            XCTAssertTrue(type(of: cell) == (look == .flat ? HelmFlatSegmentedCell.self : NSSegmentedCell.self), """
                \(context): precondition — the bar was built under \(look) and the switcher wears \(type(of: cell))
                """)
            let entry = try XCTUnwrap(read.capsule.model.declared.first { $0.id == "viewMode" },
                                      "\(context): no viewMode entry declared")
            let reserve = read.capsule.reserveWidth(entry)
            print("[reserve] \(context): reserve \(reserve) pt, drawn \(control.frame.width) pt, "
                  + "intrinsic \(control.intrinsicContentSize.width) pt, cell \(type(of: cell))")
            return (reserve, control.frame.width, control.segmentCount)
        }
    }

    /// A `SettingsToolbar` under `look`, built with the default lead `.sidebarSeparator`
    /// (the app's window builds `.spacer`): the look is read when the bar is built.
    private func mountBar(_ token: String, look: HelmBarAppearance) -> Bar {
        AppSettings.barAppearance = look
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        model.selection = .module(token)
        return Bar(toolbar: toolbar, channel: channel, window: window, token: token, look: look)
    }

    func testTheReserveIsNeitherShortOfNorPastWhatTheSwitcherDraws() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            var drawn: [CGFloat] = []
            for glyphs in Self.sets {
                let context = "\(look) / " + glyphs.joined(separator: " / ")
                let bar = mountBar("test.reserveIsWhatItDraws", look: look)
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
                precondition: the sets drew \(drawn) under \(look) — too close together to say anything about \
                glyph width
                """)
        }
    }

    func testARedeclaredSetOfGlyphsIsMeasuredAfresh() throws {
        PinnedBarSettings.pin(in: self)
        for look in Self.looks {
            let bar = mountBar("test.reserveRedeclared", look: look)
            var readings: [(reserve: CGFloat, drawn: CGFloat, count: Int)] = []
            // Narrow, wide, narrow again — each declare on the same attached bar.
            for glyphs in [["minus", "ellipsis"], ["rectangle.3.group", "keyboard"], ["minus", "ellipsis"],
                           ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"]] {
                let context = "\(look) redeclared " + glyphs.joined(separator: " / ")
                bar.declare(glyphs)
                let reading = try bar.reading(context)
                XCTAssertEqual(reading.count, glyphs.count, "\(context): precondition — the switcher drew other segments")
                readings.append(reading)
                XCTAssertEqual(reading.reserve, reading.drawn, accuracy: 0.5, """
                    \(context): after the page re-declared its options, the entry reserves \(reading.reserve) pt \
                    and draws \(reading.drawn) pt — the reserve is left over from an earlier declaration
                    """)
            }
            // The subject: the redeclares really did change what was drawn — a pair after a pair at all,
            // the four-option set after a pair by more than 4.
            XCTAssertGreaterThan(readings[1].drawn - readings[0].drawn, 0, """
                precondition: the two pairs drew \(readings[0].drawn) and \(readings[1].drawn) pt under \(look) \
                — a stale reserve would look like a fresh one
                """)
            XCTAssertGreaterThan(readings[3].drawn - readings[2].drawn, 4, """
                precondition: the pair and the four-option set drew \(readings[2].drawn) and \(readings[3].drawn) pt \
                under \(look) — a stale reserve would look like a fresh one
                """)
            bar.window.toolbar = nil
            _ = bar.toolbar
        }
    }
}
