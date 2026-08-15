import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_UI

/// A return's banner offers one button per rule that could not be re-marked,
/// and the button carries the rule's *name* — the person's own text, with no
/// bound. In one HStack with the report those buttons compressed instead of
/// wrapping: measured on the audit render, «Выключить правило „Ск…“» arrived
/// at 153 pt of its natural 286 in a 540 pt pane, which is the rule's name cut
/// to two letters on the one control that needs it whole.
///
/// Two claims, the way `DuplicatesBarWidthTests` splits them: the arithmetic
/// (a capped button fits the narrowest pane, an uncapped one does not), and
/// the page (the shipped banner actually wraps its buttons and caps the one
/// with a name in it — a cap measured here but not drawn is a guard on
/// nothing).
final class TheReturnBannerFoldsItsButtonsTests: XCTestCase {

    /// A name a person can really paste into the rule editor.
    private let rule = String(repeating: "Квартальные отчёты и накладные ", count: 4)

    /// The panes of the audit: the narrowest a page can be given, and the one
    /// the default window opens on.
    private enum Pane {
        static let narrowest: CGFloat = 540
        static let atTheDefaultWindow: CGFloat = 846
        static func content(_ pane: CGFloat) -> CGFloat { pane - HelmLayout.formInset * 2 }
    }

    private func button(_ title: String) -> CGFloat {
        ControlMetrics.smallButton(title)
    }

    /// The bezel around an empty title: what the cap on the *label* leaves out.
    private var bezel: CGFloat { button("") }

    /// The hazard is real: at its natural size the button does not fit the
    /// narrow pane in any language, so a banner without the cap is a banner
    /// that cannot keep its promise.
    func testAnUncappedButtonOverflowsTheNarrowPane() {
        for language in AppLanguage.allCases {
            let needs = button(ApStr.turnRuleOff(rule, language: language))
            XCTAssertGreaterThan(needs, Pane.content(Pane.narrowest), language.rawValue)
        }
    }

    /// The capped button fits both panes with room to spare — `HelmWrappingRow`
    /// gives a child wider than the row a line of its own rather than folding
    /// it, so the cap is the only thing standing between a long name and the
    /// pane's edge.
    func testTheCappedButtonFitsBothPanes() {
        let capped = AutopilotLayout.turnOffButtonCap + bezel
        XCTAssertLessThan(capped, Pane.content(Pane.narrowest) - 20)
        XCTAssertLessThan(capped, Pane.content(Pane.atTheDefaultWindow) - 20)
    }

    /// And the shipped banner is built of the parts measured here: the buttons
    /// live in a `HelmWrappingRow` pinned to the leading edge — its
    /// `sizeThatFits` answers with the widest *line*, so unpinned it centres —
    /// and the turn-off button reads the cap this file just measured.
    func testTheShippedBannerWrapsAndCapsItsButtons() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Autopilot/UI/AutopilotSettingsPage.swift")
        let opens = try XCTUnwrap(page.range(of: "if let banner = rvm.banner"))
        let closes = try XCTUnwrap(page.range(of: ".helmTracksFullDiskAccess",
                                              range: opens.upperBound..<page.endIndex))
        let banner = String(page[opens.lowerBound..<closes.lowerBound])

        XCTAssertTrue(banner.contains("HelmWrappingRow"), """
            The banner keeps its buttons in a single line, so a long rule name \
            compresses the button that carries it instead of wrapping.
            """)
        XCTAssertTrue(banner.contains("AutopilotLayout.turnOffButtonCap"), """
            The turn-off button does not read the cap this test measures, so \
            the arithmetic above guards nothing the page draws.
            """)
        XCTAssertTrue(banner.contains(".frame(maxWidth: .infinity, alignment: .leading)"), """
            `HelmWrappingRow.sizeThatFits` reports its widest line, so without \
            a leading pin the wrapped block centres in the pane — the lesson \
            `LogView` already records.
            """)
    }
}
