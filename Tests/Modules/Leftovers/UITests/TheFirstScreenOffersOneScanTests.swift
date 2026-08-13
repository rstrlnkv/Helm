import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The screen a person meets first drew **two** Scan buttons and three controls
/// with nothing to act on.
///
/// Measured before a scan, in Russian: focus rings at (480, 12) 106 pt wide — the
/// toolbar's Scan — and at (248, 324) 110 pt — the invitation's. The same word, the
/// same key, 312 pt apart. Below them, at y 504, «Select all», «Clear selection»
/// and «Move to Trash», on a page holding nothing to select or move: the toolbar
/// had an emptiness guard (`if !lvm.items.isEmpty`) and the bar under the list had
/// none.
///
/// So: the toolbar's Scan draws only where the invitation does not, both asked of
/// `LeftoversEmpty.invites`; and the bar takes the guard the toolbar already uses.
@MainActor
final class TheFirstScreenOffersOneScanTests: XCTestCase {

    private static func agent(_ name: String, status: ItemStatus = .orphaned) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: status)
    }

    /// **The first screen offers exactly one thing to press.**
    ///
    /// Every language, because a control this test cannot find is indistinguishable
    /// from a control that is not drawn, and the first assertion is that one *is*
    /// there: an assertion about an absence passes when the subject never happened.
    func testBeforeAnyScanThePageDrawsOneControlAndItIsTheInvitations() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            let (mount, model) = await LeftoversPageRender.page([], language: language,
                                                                width: 606, appearance: .aqua,
                                                                scanned: false)
            defer { mount.drop() }
            XCTAssertEqual(model.nothingToShow, .notScanned,
                           "precondition: \(language.rawValue) drew the invitation")
            let controls = LeftoversPageRender.controls(in: mount)

            XCTAssertEqual(controls.count, 1, """
                \(language.rawValue): the first screen draws \(controls.count) controls at \
                \(controls.map { "(\(Int($0.minX)),\(Int($0.minY)))" }.joined(separator: " ")) — \
                a second Scan in the toolbar, and a row of buttons with nothing to act on.
                """)
            guard let scan = controls.first else { continue }
            XCTAssertGreaterThan(scan.minY, 100, """
                \(language.rawValue): the one control left is the toolbar's, not the \
                invitation's — the sentence asking for a scan has nothing to accept again.
                """)
        }
    }

    /// **And it draws no empty chrome.** Taking the controls away is half the
    /// repair: what was left was a 48 pt strip with a hairline under it and nothing
    /// in it, and a second hairline at the foot of the page with nothing under
    /// that. A bar is drawn because it holds something.
    ///
    /// Measured in ink, in both appearances, because a hairline is one pixel row
    /// and a strip is empty either way — and the first assertion is that the page
    /// drew at all, or «nothing in the top band» is what a blank render says too.
    func testTheFirstScreenDrawsNoBarWithNothingInIt() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for appearance in RenderedInk.bothAppearances {
            let (mount, _) = await LeftoversPageRender.page([], language: .ru, width: 606,
                                                            appearance: appearance,
                                                            scanned: false)
            defer { mount.drop() }
            let whole = try XCTUnwrap(mount.ink(), "the page drew nothing at all")
            XCTAssertGreaterThan(whole, 0, "precondition: the invitation is on the screen")

            let top = try XCTUnwrap(mount.ink(0...50))
            let bottom = try XCTUnwrap(mount.ink(490...539))
            XCTAssertEqual(top, 0, "\(RenderedInk.label(of: appearance)): the toolbar's strip is "
                           + "still drawn over a page with nothing to filter and nothing to scan "
                           + "again")
            XCTAssertEqual(bottom, 0, "\(RenderedInk.label(of: appearance)): the divider above "
                           + "the action bar is drawn with no bar under it")
        }
    }

    /// **The one page with no rows that keeps its foot.** Removing the last
    /// leftover empties the list, and the report of that removal is drawn under it:
    /// a rule of «no rows, no bottom row» would take away the only thing the page
    /// ever says about a destructive press, at the moment it worked.
    func testARemovalThatEmptiedTheListStillReportsItself() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .ru

        let item = Self.agent("com.vendor.gone")
        let wire = LeftoversWire(
            items: [item],
            removal: LeftoversRemoval(removed: [item.path], refused: [], freedBytes: 4_096))
        let (mount, model) = await LeftoversPageRender.page(on: wire, language: .ru, width: 606,
                                                            appearance: .aqua)
        defer { mount.drop() }
        model.tickAll()
        wire.setItems([])
        await model.removeSelected()
        mount.settle(30)

        XCTAssertTrue(model.items.isEmpty, "precondition: the removal emptied the list")
        XCTAssertNotNil(model.banner, "precondition: the removal reported something")
        XCTAssertGreaterThan(try XCTUnwrap(mount.ink(480...539)), 0,
                             "the page dropped its whole foot with the rows, and with it the "
                             + "report of the removal that took them")
    }

    /// And once there is a list, the toolbar's Scan is back: it is the only way to
    /// scan again, and the invitation is gone.
    func testOnceSomethingHasBeenFoundTheToolbarCarriesTheScan() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        let (mount, model) = await LeftoversPageRender.page([Self.agent("com.vendor.gone")],
                                                            language: .ru, width: 606,
                                                            appearance: .aqua)
        defer { mount.drop() }
        XCTAssertNil(model.nothingToShow, "precondition: the page drew a list")
        let controls = LeftoversPageRender.controls(in: mount)

        XCTAssertEqual(controls.filter { $0.minY < 48 }.count, 1,
                       "the toolbar lost the Scan button along with the duplicate")
        XCTAssertEqual(controls.filter { $0.minY > 400 }.count, 3,
                       "the bar lost its buttons along with the empty page's")
    }

    /// A scan that found nothing is a **statement**, so the invitation draws no
    /// button — which makes the toolbar's the only one on the page. Losing it there
    /// would leave a screen that cannot be scanned again.
    func testAScanThatFoundNothingKeepsTheToolbarsScan() async throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        let (mount, model) = await LeftoversPageRender.page([], language: .ru, width: 606,
                                                            appearance: .aqua)
        defer { mount.drop() }
        XCTAssertEqual(model.nothingToShow, .nothingFound,
                       "precondition: the scan came back with nothing")
        XCTAssertFalse(LeftoversEmpty.invites(.nothingFound),
                       "precondition: this screen is a statement and draws no verb of its own")

        let controls = LeftoversPageRender.controls(in: mount)
        XCTAssertEqual(controls.count, 1, """
            a page that found nothing draws \(controls.count) controls at \
            \(controls.map { "(\(Int($0.minX)),\(Int($0.minY)))" }.joined(separator: " ")): \
            one Scan in the toolbar, and nothing else to press.
            """)
        XCTAssertLessThan(controls.first?.minY ?? .infinity, 48,
                          "the one control is not the toolbar's Scan, so this page cannot be "
                          + "scanned again at all")
    }
}
