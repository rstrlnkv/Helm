import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **The strip had no slack, and a caption added to it was paid for by the
/// button.**
///
/// «Not checked: N» belongs beside «Found: N» — the rows it counts are the ones
/// the default filter hides, so this is the only place the number can be read.
/// Written as a third fixed-width item in the row it cost the Scan button its
/// words at the narrowest pane the window allows: measured at 606 pt, Russian
/// «Сканировать заново» drawn 20.5 pt against the 154.0 it needs, Spanish 20.5
/// against 139.0, Portuguese 76.0 against 131.5, German 92.5 against 118.5,
/// French 68.0 against 90.5 — an `HStack` does not wrap, and what it compresses
/// is whatever has no fixed size. That is `TheActionBarKeepsItsWordsTests`'
/// defect one row up.
///
/// So the captions give way instead, and in an order: the one that survives is
/// the one saying the number above it is incomplete.
@MainActor
final class TheToolbarKeepsItsVerbTests: XCTestCase {

    /// The narrowest pane the window allows, the default, and a wide one —
    /// `contentMinSize` is 860 × 540 and the sidebar takes the rest
    /// (ARCHITECTURE.md § Settings window).
    private static let widths: [CGFloat] = [606, 720, 845]

    /// The strip, in points from the top of the page: 48 pt of controls and the
    /// hairline under them.
    private static let strip = 0...47

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private static func agent(_ name: String, _ status: ItemStatus) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096, status: status)
    }

    /// One leftover to keep the list drawn, and `unchecked` rows the scan could
    /// not judge — which are never in the list, being neither `.orphaned` nor
    /// anything else the filter keeps.
    private static func items(unchecked: Int) -> [StaleItem] {
        [agent("com.vendor.gone", .orphaned)]
        + (0..<unchecked).map { agent("com.vendor.u\($0)", .undetermined) }
    }

    private func toolbar(_ language: AppLanguage, width: CGFloat, unchecked: Int)
    async -> (scan: CGRect?, ink: Int) {
        AppLanguage.override = language
        let (mount, model) = await LeftoversPageRender.page(Self.items(unchecked: unchecked),
                                                            language: language, width: width,
                                                            height: 620, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(20)
        XCTAssertEqual(model.uncheckedCount, unchecked, "precondition: the scan carried them")
        let controls = LeftoversPageRender.controls(in: mount).filter { $0.minY < 90 }
        return (controls.max { $0.minX < $1.minX }, mount.ink(Self.strip) ?? 0)
    }

    /// **The measurement this file exists for**, in every one of the eight and at
    /// three pane widths.
    func testTheScanButtonIsNeverDrawnNarrowerThanItsOwnWords() async throws {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let natural = LeftoversPageRender.naturalWidth(of: LfStr.rescan, prominent: false,
                                                           appearance: .aqua)
            XCTAssertGreaterThan(natural, 0, "precondition: the button was measured on its own")
            for width in Self.widths {
                let strip = await toolbar(language, width: width, unchecked: 3)
                let drawn = try XCTUnwrap(strip.scan,
                                          "\(language.rawValue) at \(width): no button was drawn")
                XCTAssertGreaterThanOrEqual(drawn.width, natural, """
                    \(language.rawValue) at \(width) pt: «\(LfStr.rescan)» is drawn \
                    \(drawn.width) pt wide where its own words need \(natural) — \
                    \(natural - drawn.width) pt squeezed out of the one verb on this screen by a \
                    caption beside it.
                    """)
            }
        }
    }

    /// And the caption is drawn where there is room for it — without this the
    /// check above passes with the caption deleted, which is the arrangement it
    /// is supposed to be making room for.
    func testTheCaptionIsDrawnWhereTheStripCanHoldIt() async {
        for language in [AppLanguage.en, .ru] {
            let without = await toolbar(language, width: 845, unchecked: 0).ink
            let with = await toolbar(language, width: 845, unchecked: 3).ink
            XCTAssertGreaterThan(with, without, """
                \(language.rawValue) at 845 pt: the strip draws no more than it did without a \
                single unjudged row, so «\(LfStr.uncheckedLine(3))» is not on the screen at all.
                """)
        }
    }

    /// And steps aside where there is not. Russian at the narrowest pane is the
    /// case: the three controls and one caption already come to more than the
    /// strip has, so what is drawn is the controls.
    func testTheCaptionStepsAsideWhereTheStripCannot() async {
        let without = await toolbar(.ru, width: 606, unchecked: 0).ink
        let with = await toolbar(.ru, width: 606, unchecked: 3).ink

        XCTAssertGreaterThan(without, 0, "precondition: the strip drew something either way")
        XCTAssertLessThan(with, without, """
            ru at 606 pt: the strip draws as much as it did with a caption, so a caption is \
            still in it — and the button is what paid for the room.
            """)
    }
}
