import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A `.segmented` entry with one option reserves what it draws, so a button
/// beside it that hides does not move the capsule by so much as a half
/// point.** Holds the one-option reserve of `ShellBarActions.segmentedReserveWidth(_:appearance:)` no
/// narrower than what the zone draws, and the capsule still when a button beside it hides. It does not hold
/// `ShellBarActions.oneOptionCapsuleMargin` to its figure: on the page bar, with the margin at 0, this file
/// stayed green — the red runs dated below were against the earlier toolbar.
///
/// Written as a repro (tester, 2026-09-25) against the earlier toolbar,
/// `SettingsToolbar`, before that margin existed. The reserve is measured on the switcher alone, in
/// `SwitcherMeasurementRig`'s toolbar item; the capsule draws it inside its
/// `GlassEffectContainer`. For two, three and four options the two agree to
/// the point (`ASegmentedEntrysReserveIsWhatItDrawsTests`); for one they did
/// not. Measured then on this Mac: `keyboard` reserved 37.0 pt and drawn 40.0,
/// `rectangle.3.group` 39.0 against 42.0, `tablecells` 36.0 against 38.5 —
/// and a button beside it that hides shrank the capsule by the difference
/// (80.0 → 77.0 pt for `keyboard`), the movement the reserve exists to
/// prevent. Seen red again (tester, 2026-09-26) with the margin removed from
/// the tree it guards: the same three glyphs, the same three numbers.
///
/// **Measured across more than the three glyphs the margin was fitted on**
/// (tester, 2026-09-26, this Mac: 22 glyphs from `minus` to
/// `person.3.sequence`, each beside zero, one and two buttons, first and
/// last, the rig's reading taken with the margin and the rounding both
/// removed). The rig never reads below 36.0 pt. Above that floor the capsule
/// draws every glyph exactly 3.0 pt wider than the rig reads — `keyboard` 37.0
/// → 40.0, `rectangle.and.pencil.and.ellipsis` 37.5 → 40.5, `rectangle.3.group`
/// 39.0 → 42.0, `chevron.left.forwardslash.chevron.right` 39.5 → 42.5,
/// `battery.100.bolt` 40.5 → 43.5, `person.3.sequence` 49.0 → 52.0; at the
/// floor it draws anything from 35.0 (`minus`, `circle`, an unknown name) to
/// 39.0 (`cable.connector.horizontal`). So the margin is a cover on this Mac
/// with nothing to spare on seven of the 22, and a narrow glyph reserves 39.0
/// over 35.0 drawn. No arrangement of neighbours moved the capsule by any
/// amount.
///
/// **No tolerance, and two glyphs that draw at a half point** — the
/// reserve is a whole point since `ShellBarActions.segmentedReserveWidth(_:appearance:)` rounds it up,
/// so a reserve that covers what is drawn leaves the capsule where it was to
/// the exact point. This file used to allow half a point on both checks, and
/// that half point was the whole defect: with the margin set to 2.5 pt it
/// stayed green on the three original glyphs while `battery.100.bolt` reserved
/// 43.0 against 43.5 drawn and the capsule moved 83.5 → 83.0 pt as its
/// neighbour hid (tester, 2026-09-26) — a half-point width on the capsule is
/// what `HostsTabsUnfoldWithoutABlinkTests` measured a blink on. The two
/// half-point glyphs below are what catch that.
///
/// **What is read now.** The page is declared on a real page bar in a window
/// (`LivePageToolbarFixture`), under each of the bar's two looks. The reserve
/// is the figure the actions zone's own model holds for the entry — measured
/// once, on a switcher mounted alone in a detached host — and what is drawn is
/// the `NSSegmentedControl` in the zone's own host, laid out inside the
/// capsule: two hosts, two layouts, so the comparison can fail. The numbers in
/// the paragraphs above were read in the earlier toolbar's attached item and
/// are history, not what this file asserts.
///
/// `HelmToolbarAction`'s segmented initialiser accepts any number of options,
/// and this file feeds it one — an input the API leaves open. Whether a page
/// declares one is read at the declarations
/// `command grep -rn 'options: \[$' Sources/Modules` lists, not written here.
@MainActor
final class AOneOptionSegmentedEntrysReserveCoversItTests: XCTestCase {

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

    func testHidingAButtonBesideAOneOptionEntryDoesNotResizeTheCapsule() throws {
        let token = "test.oneOption"
        for look in [HelmBarAppearance.flat, .liquidGlass] {
            for glyph in ["keyboard", "rectangle.3.group", "tablecells",
                          "battery.100.bolt", "chevron.left.forwardslash.chevron.right"] {
                let context = "\(look) / \(glyph)"
                AppSettings.barAppearance = look
                let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
                fixtures.append(fx)

                func declare(buttonVisible: Bool) {
                    fx.channel.declare(HelmPageToolbarContent(actions: [
                        HelmToolbarAction(id: "viewMode", title: "View", options: [
                            HelmToolbarTab(id: "only", title: glyph, symbol: glyph),
                        ], selection: .constant("only")),
                        HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                                          isVisible: buttonVisible) {},
                    ]), token: token, generation: fx.channel.nextGeneration())
                    fx.settle(10)
                }

                declare(buttonVisible: true)
                // Found from the window and held to be the fixture's own zone.
                let found = fx.mount.window?.contentView?.superview?
                    .everyView(ofType: ShellPageBarView.self).first?.view(for: .actions)
                let hosting = try XCTUnwrap(found, "\(context): the bar in the window holds no actions zone")
                XCTAssertTrue(hosting === fx.pageBar.actions.view, "\(context): precondition — not the fixture's zone")
                let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                            "\(context): precondition — no switcher drawn")
                XCTAssertEqual(control.segmentCount, 1, "\(context): precondition — the switcher has the wrong segments")
                TheGlassSwitcherWarmUp.assertDrawnAtTheBarsSize(control, context)
                let entry = try XCTUnwrap(fx.pageBar.actions.model.declared.first { $0.id == "viewMode" },
                                          "\(context): no viewMode entry declared")
                guard case .segmented(_, _, let reserve) = entry.kind else {
                    return XCTFail("\(context): precondition — the entry is not a segmented one")
                }
                XCTAssertGreaterThan(control.frame.width, 0, "\(context): precondition — the switcher drew no width")
                XCTAssertGreaterThanOrEqual(reserve, control.frame.width, """
                    \(context): the one-option entry reserves \(reserve) pt and draws \(control.frame.width) pt
                    """)
                let both = hosting.fittingSize.width

                declare(buttonVisible: false)
                XCTAssertTrue(fx.pageBar.actions.view === hosting, "\(context): the capsule's host was built again")
                XCTAssertEqual(fx.pageBar.actions.model.visibleIDs, ["viewMode"],
                               "\(context): precondition — the button did not hide")
                XCTAssertEqual(hosting.fittingSize.width, both, """
                    \(context): hiding the button beside a one-option entry resized the capsule \
                    (\(both) -> \(hosting.fittingSize.width) pt)
                    """)
            }
        }
    }
}
