import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The reserve is measured per glyph set, not a stand-in shared across
/// every `.segmented` entry.** `HelmToolbarActionsCapsule.reserveWidth(_:)`
/// reads whatever `EntryKind.segmented`'s own `reserveWidth` carries, and
/// `ShellBarActions.segmentedReserveWidth(_:appearance:)` measures that number
/// on a switcher mounted alone, per glyph set and per look, rounded up to the
/// next whole point. A reserve tuned to one pair and reused for every page
/// would cover a page whose glyphs are narrow without covering a page whose
/// glyphs are wider — the capsule resize this entry exists to prevent — so
/// this file checks four pairs and two longer sets, the pairs including Hosts' own `tablecells` /
/// `text.alignleft`, rather than only one.
///
/// The page is declared on a real page bar in a window
/// (`LivePageToolbarFixture`), under each of the bar's two looks. The reserve
/// is read from the actions zone's own model; what is drawn is the
/// `NSSegmentedControl` in the zone's host, laid out inside the capsule. Two
/// hosts, two layouts: the reserve is compared with something it does not
/// compute. The figures in the earlier version of this comment (73.0, 78.0,
/// 82.0, 85.0 pt) were read in the earlier toolbar's attached item and are not
/// asserted here.
///
/// The pairs span the glyph widths on purpose: a check fed one pair is a
/// check of that pair's numbers.
@MainActor
final class ASegmentedEntrysReserveCoversItsOwnGlyphsTests: XCTestCase {

    /// Four pairs and a three- and a four-option set.
    private static let sets: [[String]] = [
        ["minus", "ellipsis"], ["tablecells", "text.alignleft"],
        ["keyboard", "rectangle.split.3x1"], ["rectangle.3.group", "keyboard"],
        ["keyboard", "tablecells", "text.alignleft"],
        ["rectangle.3.group", "keyboard", "rectangle.split.3x1", "tablecells"],
    ]

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

    func testTheReserveCoversWhatTheSwitcherDrawsWhateverItsGlyphs() throws {
        let token = "test.reserveGlyphs"
        var drawnWidths: [HelmBarAppearance: [CGFloat]] = [:]
        for look in [HelmBarAppearance.flat, .liquidGlass] {
            for glyphs in Self.sets {
                let pair = "\(look) / " + glyphs.joined(separator: " / ")
                AppSettings.barAppearance = look
                let fx = LivePageToolbarFixture(Color.clear, selection: .module(token), width: 1060, height: 700)
                fixtures.append(fx)

                func declare(buttonVisible: Bool) {
                    fx.channel.declare(HelmPageToolbarContent(
                        tabs: [HelmToolbarTab(id: "alpha", title: "Alpha", symbol: "circle")],
                        selectedTab: .constant("alpha"), actions: [
                        HelmToolbarAction(id: "viewMode", title: "View", isVisible: true,
                                          options: glyphs.enumerated().map {
                                              HelmToolbarTab(id: "option\($0.offset)", title: $0.element, symbol: $0.element)
                                          }, selection: .constant("option0")),
                        HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                                          isVisible: buttonVisible) {},
                    ]), token: token, generation: fx.channel.nextGeneration())
                    fx.settle(10)
                }

                declare(buttonVisible: true)
                // The look reached the bar: the tabs zone's plate is the one this look draws.
                let plate = try XCTUnwrap(fx.pageBar.tabs.view as? ShellBarPlate,
                                          "\(pair): precondition — the tabs zone placed no plate")
                XCTAssertEqual(plate.barAppearance, look, "\(pair): precondition — the bar was not handed this look")
                // Found from the window and held to be the fixture's own zone.
                let found = fx.mount.window?.contentView?.superview?
                    .everyView(ofType: ShellPageBarView.self).first?.view(for: .actions)
                let hosting = try XCTUnwrap(found, "\(pair): the bar in the window holds no actions zone")
                XCTAssertTrue(hosting === fx.pageBar.actions.view, "\(pair): precondition — not the fixture's zone")
                let both = hosting.fittingSize.width
                let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                            "\(pair): precondition — no switcher drawn")
                XCTAssertEqual(control.segmentCount, glyphs.count, "\(pair): precondition — the switcher has the wrong segments")
                TheGlassSwitcherWarmUp.assertDrawnAtTheBarsSize(control, pair)
                XCTAssertTrue((0..<glyphs.count).allSatisfy { control.image(forSegment: $0) != nil },
                              "\(pair): precondition — a glyph is missing, so its width was never drawn")
                drawnWidths[look, default: []].append(control.frame.width)
                let entry = try XCTUnwrap(fx.pageBar.actions.model.declared.first { $0.id == "viewMode" },
                                          "\(pair): no viewMode entry declared")
                guard case .segmented(_, _, let reserve) = entry.kind else {
                    return XCTFail("\(pair): precondition — the entry is not a segmented one")
                }
                XCTAssertGreaterThanOrEqual(reserve + 0.5, control.frame.width, """
                    \(pair): the segmented entry reserves \(reserve) pt and draws \(control.frame.width) pt
                    """)

                declare(buttonVisible: false)
                XCTAssertTrue(fx.pageBar.actions.view === hosting, "\(pair): the capsule's host was built again")
                XCTAssertEqual(fx.pageBar.actions.model.visibleIDs, ["viewMode"],
                               "\(pair): precondition — the button did not hide")
                XCTAssertEqual(hosting.fittingSize.width, both, accuracy: 0.5, """
                    \(pair): hiding the button beside the segmented entry resized the capsule \
                    (\(both) -> \(hosting.fittingSize.width) pt)
                    """)
            }
        }
        // The subject: the sets really do draw at different widths under each look.
        for (look, widths) in drawnWidths {
            XCTAssertGreaterThan((widths.max() ?? 0) - (widths.min() ?? 0), 4, """
                precondition: the sets drew \(widths) under \(look) — too close together to say \
                anything about a reserve measured per set
                """)
        }
        // Both looks wear one cell, so the same glyphs draw the same widths; that the second look
        // reached the bar is the plate check inside the loop.
        XCTAssertEqual(drawnWidths[.flat]?.count, Self.sets.count, "the flat look drew \(String(describing: drawnWidths[.flat]))")
        XCTAssertEqual(drawnWidths[.flat], drawnWidths[.liquidGlass], """
            the two looks drew different widths for the same glyphs: \(String(describing: drawnWidths))
            """)
    }
}
