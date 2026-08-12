import AppKit
import HelmUI
import Module_Layout_UI
import XCTest
@testable import HelmApp

/// **Without Accessibility the Keyboard page is one screen, not 1867 pt of
/// settings macOS ignores.**
///
/// Every control on that page depends on a tap the grant pays for, and the page
/// used to draw all of them under a banner — a switch that looks like it works,
/// nine times over. The empty state replaces the pane.
///
/// One section survives, and it is the one the mockup missed: the language
/// indicator reads the current input source through TIS and draws a status item.
/// No grant is involved, so taking it away with the rest would remove a working
/// feature because a different one is unavailable.
///
/// **Both appearances are named**, because a reading of this render has a screen
/// (`ModulePageRender`), and both grants are named for the same reason — the
/// third weather that file describes. Structure is what is asserted: which
/// controls are drawn, not how many layers, since a layer count is what the
/// ratchets carry and a number in two places drifts.
@MainActor
final class TheKeyboardPageWithoutTheGrantTests: XCTestCase {

    func testWithoutTheGrantOnlyTheIndicatorSectionIsDrawn() {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let granted = page(granting: ModulePageRender.granted)
            let withheld = page(granting: ModulePageRender.withheld, in: appearance)
            granted.assertItDrewSomething()
            // The withheld screen's own floor, measured: an empty state, its
            // plate and button, and the indicator row. Asserted so that «fewer
            // layers than granted» cannot be satisfied by a page that drew
            // nothing at all.
            withheld.assertItDrewSomething(atLeast: 40)

            XCTAssertLessThan(withheld.layers.count, granted.layers.count / 2, """
                the page without the grant draws \(withheld.layers.count) layers against \
                \(granted.layers.count) with it, in \(appearance.rawValue) — it is still \
                drawing the settings, and every one of them is a control macOS ignores.
                """)

            // Seven switches with the grant: fix as I type, the sound, three
            // triggers, the held capital, the indicator. One without it, and it
            // is the indicator's.
            XCTAssertEqual(switches(in: withheld), 1, """
                \(switches(in: withheld)) switches are drawn without the grant in \
                \(appearance.rawValue), where the indicator's is the only one that works \
                without it — either the empty state has taken that section away too, or the \
                dead settings are back.
                """)
            XCTAssertGreaterThan(switches(in: granted), 1,
                                 "the granted page draws no more switches than the withheld "
                                 + "one, so this comparison is measuring nothing")
        }
    }

    private func page(granting grants: HelmGrants,
                      in appearance: NSAppearance.Name = .aqua) -> ModulePageRender.Page {
        ModulePageRender.page(for: LayoutDescriptor(), in: appearance,
                              width: ModulePageRender.pageWidth, granting: grants)
    }

    private func switches(in page: ModulePageRender.Page) -> Int {
        page.controls.filter { $0.shortName == "AppKitSwitch" }.count
    }
}
