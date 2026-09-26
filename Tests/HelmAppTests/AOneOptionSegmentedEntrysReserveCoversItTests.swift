import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A `.segmented` entry with one option reserves what it draws, so a button
/// beside it that hides does not move the capsule by so much as a half
/// point.** Guards `SettingsToolbar.oneOptionCapsuleMargin`, and through it
/// the one-option branch of `SettingsToolbar.segmentedReserveWidth(_:)`.
///
/// Written as a repro (tester, 2026-09-25) against the tree before that
/// margin existed. The reserve is measured on the switcher alone, in
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
/// reserve is a whole point since `segmentedReserveWidth(_:)` rounds it up,
/// so a reserve that covers what is drawn leaves the capsule where it was to
/// the exact point. This file used to allow half a point on both checks, and
/// that half point was the whole defect: with the margin set to 2.5 pt it
/// stayed green on the three original glyphs while `battery.100.bolt` reserved
/// 43.0 against 43.5 drawn and the capsule moved 83.5 → 83.0 pt as its
/// neighbour hid (tester, 2026-09-26) — a half-point width on the capsule is
/// what `HostsTabsUnfoldWithoutABlinkTests` measured a blink on. The two
/// half-point glyphs below are what catch that.
///
/// `HelmToolbarAction`'s segmented initialiser accepts any number of options,
/// and this file feeds it one — an input the API leaves open. Whether a page
/// declares one is read at the declarations
/// `command grep -rn 'options: \[$' Sources/Modules` lists, not written here.
@MainActor
final class AOneOptionSegmentedEntrysReserveCoversItTests: XCTestCase {

    func testHidingAButtonBesideAOneOptionEntryDoesNotResizeTheCapsule() throws {
        for glyph in ["keyboard", "rectangle.3.group", "tablecells",
                      "battery.100.bolt", "chevron.left.forwardslash.chevron.right"] {
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
            let hosting = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }?
                .view as? NSHostingView<HelmToolbarActionsCapsule>, "\(glyph): no hosted capsule")
            let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(glyph): precondition — no switcher drawn")
            XCTAssertEqual(control.segmentCount, 1, "\(glyph): precondition — the switcher has the wrong segments")
            let entry = try XCTUnwrap(hosting.rootView.model.declared.first { $0.id == "viewMode" })
            let reserve = hosting.rootView.reserveWidth(entry)
            XCTAssertGreaterThanOrEqual(reserve, control.frame.width, """
                \(glyph): the one-option entry reserves \(reserve) pt and draws \(control.frame.width) pt
                """)
            let both = hosting.fittingSize.width

            declare(buttonVisible: false)
            XCTAssertEqual(hosting.fittingSize.width, both, """
                \(glyph): hiding the button beside a one-option entry resized the capsule \
                (\(both) -> \(hosting.fittingSize.width) pt)
                """)
            window.toolbar = nil
            _ = toolbar
        }
    }
}
