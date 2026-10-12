import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A `.segmented` entry with one option reserves what it draws, so a button
/// beside it that hides does not move the capsule by so much as a half
/// point.** Covers `SettingsToolbar.oneOptionCapsuleMargin`, and through it
/// the one-option branch of `SettingsToolbar.segmentedReserveWidth(_:look:)`;
/// see "No tolerance" below for which look and which glyph turn it red.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds: it has no `helm.tabsLead` and no capped search field.
///
/// **Under both looks.** The bar's look is read when the bar is built
/// (`AppSettings.barAppearance`) and names the cell the switcher wears: Helm's
/// `HelmFlatSegmentedCell` under Flat, AppKit's own under Liquid Glass
/// (`HelmBarAppearance.switcherCell`). The row pins the settings
/// (`PinnedBarSettings`), sets the look before each bar is built, asserts from
/// the drawn control's cell that the look reached the bar, and prints the look
/// with each reading.
///
/// **What "drawn" is in the row:** the frame width of the switcher's control
/// on the bar as built. Each `[reserve]` line prints beside it the control's
/// own `intrinsicContentSize.width`, the cell's own size, which the row does
/// not assert. In a window never ordered the five glyphs reserve 51.0 pt and
/// draw 48.0 wearing Helm's cell (the cell's own size 48.0), and reserve 39.0
/// pt and draw 35.0 to 37.0 wearing AppKit's, where the cell's own size reads
/// 38.5 to 43.5. The paragraphs below carry readings dated by the tester, all
/// of AppKit's cell and taken before the look reached the measuring views;
/// none of them is asserted here.
///
/// Written as a repro (tester, 2026-09-25) against the tree before that
/// margin existed. The reserve is measured on the switcher alone, in
/// `SwitcherMeasurementRig`'s toolbar item; the capsule draws it inside its
/// `GlassEffectContainer`. For two, three and four options the family
/// `ASegmentedEntrysReserveIsWhatItDrawsTests` holds the reserve equal to the
/// control's frame within half a point; for one they did not agree. Measured
/// then on this Mac: `keyboard` reserved 37.0 pt and drawn 40.0,
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
/// **No tolerance.** The reserve is a whole point since
/// `segmentedReserveWidth(_:look:)` rounds it up, so a reserve that covers
/// what is drawn leaves the capsule where it was to the exact point; this file
/// used to allow half a point on both checks, and a half-point width on the
/// capsule is what `HostsTabsUnfoldWithoutABlinkTests` measured a blink on.
/// What the margin is held by in the row: with `oneOptionCapsuleMargin` at 0
/// the row is red under Liquid Glass through `battery.100.bolt` alone (reserve
/// 36.0 pt against 37.0 drawn, and the capsule 77.0 → 76.0 pt as its neighbour
/// hides) and green under Flat (48.0 against 48.0). Margin 0 is the only value
/// run against this row; the other glyphs and the Flat half pass without any
/// margin, so the row does not hold the margin's size beyond that.
///
/// `HelmToolbarAction`'s segmented initialiser accepts any number of options,
/// and this file feeds it one — an input the API leaves open. Whether a page
/// declares one is read at the declarations
/// `command grep -rn 'options: \[$' Sources/Modules` lists, not written here.
@MainActor
final class AOneOptionSegmentedEntrysReserveCoversItTests: XCTestCase {

    func testHidingAButtonBesideAOneOptionEntryDoesNotResizeTheCapsule() throws {
        PinnedBarSettings.pin(in: self)
        for look in [HelmBarAppearance.flat, .liquidGlass] {
            for glyph in ["keyboard", "rectangle.3.group", "tablecells",
                          "battery.100.bolt", "chevron.left.forwardslash.chevron.right"] {
                let context = "\(look) / \(glyph)"
                AppSettings.barAppearance = look
                let model = SettingsModel(host: ModuleHost.shared)
                let channel = HelmWindowToolbarChannel()
                let toolbar = SettingsToolbar(model: model, channel: channel)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                                      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                      backing: .buffered, defer: false)
                toolbar.window = window
                model.selection = .module("test.oneOption")

                func declare(buttonVisible: Bool) {
                    channel.declare(HelmPageToolbarContent(actions: [
                        HelmToolbarAction(id: "viewMode", title: "View", options: [
                            HelmToolbarTab(id: "only", title: glyph, symbol: glyph),
                        ], selection: .constant("only")),
                        HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                                          isVisible: buttonVisible) {},
                    ]), token: "test.oneOption", generation: channel.nextGeneration())
                    window.layoutIfNeeded()
                }

                declare(buttonVisible: true)
                let read = try ActionsCapsuleReading.read(try XCTUnwrap(window.toolbar, "\(context): no toolbar"),
                                                          context: context)
                let hosting = read.host
                let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                            "\(context): precondition — no switcher drawn")
                let cell = try XCTUnwrap(control.cell, "\(context): precondition — the switcher has no cell")
                XCTAssertTrue(type(of: cell) == (look == .flat ? HelmFlatSegmentedCell.self : NSSegmentedCell.self), """
                    \(context): precondition — the bar was built under \(look) and the switcher wears \(type(of: cell))
                    """)
                XCTAssertEqual(control.segmentCount, 1, "\(context): precondition — the switcher has the wrong segments")
                let entry = try XCTUnwrap(read.capsule.model.declared.first { $0.id == "viewMode" })
                let reserve = read.capsule.reserveWidth(entry)
                print("[reserve] \(context): reserve \(reserve) pt, drawn \(control.frame.width) pt, "
                      + "intrinsic \(control.intrinsicContentSize.width) pt, cell \(type(of: cell))")
                XCTAssertGreaterThanOrEqual(reserve, control.frame.width, """
                    \(context): the one-option entry reserves \(reserve) pt and draws \(control.frame.width) pt
                    """)
                let both = hosting.fittingSize.width

                declare(buttonVisible: false)
                XCTAssertEqual(hosting.fittingSize.width, both, """
                    \(context): hiding the button beside a one-option entry resized the capsule \
                    (\(both) -> \(hosting.fittingSize.width) pt)
                    """)
                window.toolbar = nil
                _ = toolbar
            }
        }
    }
}
