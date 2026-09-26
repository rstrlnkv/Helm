import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The reserve is measured per glyph set, not a stand-in shared across
/// every `.segmented` entry.** `HelmToolbarActionsCapsule.reserveWidth(_:)`
/// reads whatever `EntryKind.segmented`'s own `reserveWidth` carries, and
/// `SettingsToolbar.segmentedReserveWidth(_:)` measures that number against
/// an attached `SwitcherMeasurementRig`, per glyph pair, rounded up to the
/// next whole point — measured here: 73.0 pt for `minus` / `ellipsis`, 78.0
/// for Hosts' own `tablecells` / `text.alignleft` (77.5 pt actually drawn,
/// rounded up), 82.0 for `keyboard` / `rectangle.split.3x1`, 85.0 for
/// `rectangle.3.group` / `keyboard`. A reserve tuned to one pair and reused
/// for every page would cover a page whose glyphs are narrow without
/// covering a page whose glyphs are wider — the capsule resize this entry
/// exists to prevent — so this file checks all four pairs rather than only
/// Hosts' own.
///
/// The pairs span the glyph widths on purpose: a check fed one pair is a
/// check of that pair's numbers.
@MainActor
final class ASegmentedEntrysReserveCoversItsOwnGlyphsTests: XCTestCase {

    private static let pairs = [("minus", "ellipsis"), ("tablecells", "text.alignleft"),
                                ("keyboard", "rectangle.split.3x1"), ("rectangle.3.group", "keyboard")]

    func testTheReserveCoversWhatTheSwitcherDrawsWhateverItsGlyphs() throws {
        var drawnWidths: [CGFloat] = []
        for (first, second) in Self.pairs {
            let pair = "\(first) / \(second)"
            let model = SettingsModel(host: ModuleHost.shared)
            let channel = HelmWindowToolbarChannel()
            let toolbar = SettingsToolbar(model: model, channel: channel)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            toolbar.window = window
            model.selection = .module("test.reserveGlyphs")

            func declare(buttonVisible: Bool) {
                channel.declare(HelmPageToolbarContent(actions: [
                    HelmToolbarAction(id: "viewMode", title: "View", isVisible: true, options: [
                        HelmToolbarTab(id: "first", title: "First", symbol: first),
                        HelmToolbarTab(id: "second", title: "Second", symbol: second),
                    ], selection: .constant("first")),
                    HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                                      isVisible: buttonVisible) {},
                ]), token: "test.reserveGlyphs", generation: channel.nextGeneration())
                window.layoutIfNeeded()
            }

            declare(buttonVisible: true)
            let hosting = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" }?
                .view as? NSHostingView<HelmToolbarActionsCapsule>, "\(pair): no hosted capsule")
            let both = hosting.fittingSize.width
            let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(pair): precondition — no switcher drawn")
            XCTAssertEqual(control.segmentCount, 2, "\(pair): precondition — the switcher has the wrong segments")
            XCTAssertTrue((0..<2).allSatisfy { control.image(forSegment: $0) != nil },
                          "\(pair): precondition — a glyph is missing, so its width was never drawn")
            drawnWidths.append(control.frame.width)
            let entry = try XCTUnwrap(hosting.rootView.model.declared.first { $0.id == "viewMode" })
            let reserve = hosting.rootView.reserveWidth(entry)
            XCTAssertGreaterThanOrEqual(reserve + 0.5, control.frame.width, """
                \(pair): the segmented entry reserves \(reserve) pt and draws \(control.frame.width) pt
                """)

            declare(buttonVisible: false)
            XCTAssertEqual(hosting.fittingSize.width, both, accuracy: 0.5, """
                \(pair): hiding the button beside the segmented entry resized the capsule \
                (\(both) -> \(hosting.fittingSize.width) pt)
                """)
            _ = toolbar
        }
        // The subject: the pairs really do draw at different widths, or this
        // is one pair's numbers four times over.
        XCTAssertGreaterThan((drawnWidths.max() ?? 0) - (drawnWidths.min() ?? 0), 4, """
            precondition: the glyph pairs drew \(drawnWidths) — too close together to say anything about \
            glyph width
            """)
    }
}
