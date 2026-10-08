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
/// (tester, 2026-09-25) with the `.icons` style removed from the earlier
/// toolbar's measurement, `SettingsToolbar.segmentedReserveWidth(_:)`, it
/// reserved the options' *words*, and that file still stayed green while the
/// capsule claimed room from the centre tabs that nothing in it draws. The
/// first case here is the other side of that bound.
///
/// The second case feeds the input the per-bar files never do: one bar in
/// one window, and a page that re-declares its options with other glyphs. The
/// reserve is cached per glyph set and look (`ShellBarActions`' private
/// `reserveCache`, keyed on the options' own `symbol` array and the bar's
/// look), so what this proves is that a set the cache has not seen before is
/// measured against what its switcher actually draws rather than answering
/// with whatever an earlier, different set left behind.
///
/// **What is read.** The page is declared on a real page bar in a window
/// (`LivePageToolbarFixture`), under each of the bar's two looks. The reserve
/// is the figure the actions zone's own model holds for the entry, measured on
/// a switcher mounted alone in a detached host; what is drawn is the
/// `NSSegmentedControl` in the zone's own host, laid out inside the capsule.
/// The two come from two layouts, so the comparison can fail. The figures in
/// the earlier version of this comment (73.0 to 162.0 pt) were read in the
/// earlier toolbar's attached item and are not asserted here.
///
/// Only two or more options here — a one-option entry is its own case
/// (`AOneOptionSegmentedEntrysReserveCoversItTests`).
@MainActor
final class ASegmentedEntrysReserveIsWhatItDrawsTests: XCTestCase {

    /// Two to four options, narrow to wide.
    private static let sets: [[String]] = [
        ["minus", "ellipsis"], ["tablecells", "text.alignleft"],
        ["keyboard", "rectangle.split.3x1"], ["rectangle.3.group", "keyboard"],
        ["keyboard", "tablecells", "text.alignleft"],
        ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"],
    ]

    private static let looks: [HelmBarAppearance] = [.flat, .liquidGlass]

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var fixtures: [LivePageToolbarFixture] = []

    /// The bar reads these when it is built, so they are pinned before a fixture is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.alwaysCollapseSearch = false
        TheGlassSwitcherWarmUp.run()
    }

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
    }

    private struct NotSegmented: Error {}

    @MainActor
    private struct Bar {
        let fx: LivePageToolbarFixture
        let token: String

        func declare(_ glyphs: [String]) {
            // Each option named after its own glyph, so a re-declaration that
            // changes a glyph changes its name as well and the switcher refills
            // (`HelmToolbarSwitcher.updateNSView`'s `namesChanged`) — what is
            // under test here is the reserve, not the refill.
            let options = glyphs.enumerated().map {
                HelmToolbarTab(id: "option\($0.offset)", title: $0.element, symbol: $0.element)
            }
            fx.channel.declare(HelmPageToolbarContent(actions: [
                HelmToolbarAction(id: "viewMode", title: "View", options: options,
                                  selection: .constant("option0")),
                HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {},
            ]), token: token, generation: fx.channel.nextGeneration())
            fx.settle(10)
        }

        /// The reserve the zone's model holds for the entry and the width its
        /// switcher actually drew, read off the bar the window holds.
        func reading(_ context: String) throws -> (reserve: CGFloat, drawn: CGFloat, count: Int) {
            let found = fx.mount.window?.contentView?.superview?
                .everyView(ofType: ShellPageBarView.self).first?.view(for: .actions)
            let hosting = try XCTUnwrap(found, "\(context): the bar in the window holds no actions zone")
            XCTAssertTrue(hosting === fx.pageBar.actions.view, "\(context): precondition — not the fixture's zone")
            let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(context): precondition — no switcher drawn")
            let entry = try XCTUnwrap(fx.pageBar.actions.model.declared.first { $0.id == "viewMode" },
                                      "\(context): no viewMode entry declared")
            guard case .segmented(_, _, let reserve) = entry.kind else {
                XCTFail("\(context): precondition — the entry is not a segmented one")
                throw NotSegmented()
            }
            TheGlassSwitcherWarmUp.assertDrawnAtTheBarsSize(control, context)
            return (reserve, control.frame.width, control.segmentCount)
        }
    }

    private func mountBar(_ token: String, look: HelmBarAppearance) -> Bar {
        AppSettings.barAppearance = look
        let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
        fixtures.append(fx)
        return Bar(fx: fx, token: token)
    }

    func testTheReserveIsNeitherShortOfNorPastWhatTheSwitcherDraws() throws {
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
            }
            XCTAssertGreaterThan((drawn.max() ?? 0) - (drawn.min() ?? 0), 4, """
                precondition: the sets drew \(drawn) under \(look) — too close together to say anything about \
                glyph width
                """)
        }
    }

    func testARedeclaredSetOfGlyphsIsMeasuredAfresh() throws {
        for look in Self.looks {
            let bar = mountBar("test.reserveRedeclared", look: look)
            var readings: [(reserve: CGFloat, drawn: CGFloat, count: Int)] = []
            // Narrow, wide, narrow again — each declare on the same bar in the same window.
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
            // The subject: the redeclares really did change what was drawn. The two pairs differ by 4 pt
            // under the flat look, so a pair after a pair has to differ at all, and the four-option set after
            // a pair by more than 4.
            XCTAssertGreaterThan(readings[1].drawn - readings[0].drawn, 0, """
                precondition: the two pairs drew \(readings[0].drawn) and \(readings[1].drawn) pt under \(look) \
                — a stale reserve would look like a fresh one
                """)
            XCTAssertGreaterThan(readings[3].drawn - readings[2].drawn, 4, """
                precondition: the pair and the four-option set drew \(readings[2].drawn) and \(readings[3].drawn) pt \
                under \(look) — a stale reserve would look like a fresh one
                """)
        }
    }
}
