import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The reserve is measured per glyph set, not a stand-in shared across
/// every `.segmented` entry.** `HelmToolbarActionsCapsule.reserveWidth(_:)`
/// reads whatever `EntryKind.segmented`'s own `reserveWidth` carries, and
/// `SettingsToolbar.segmentedReserveWidth(_:look:)` measures that number against
/// an attached `SwitcherMeasurementRig`, per glyph set and per look, rounded up to the
/// next whole point. A reserve tuned to one pair and reused for every page
/// would cover a page whose glyphs are narrow without covering a page whose
/// glyphs are wider — the capsule resize this entry exists to prevent — so
/// this file checks all four pairs, and a three- and a four-option set, rather
/// than only Hosts' own (`tablecells` / `text.alignleft`).
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
/// not assert. In a window never ordered the four pairs' frames read 90.0,
/// 94.0, 94.0 and 94.0 pt wearing Helm's cell, where the cell's own size reads
/// the same, a spread of 4.0 pt; wearing AppKit's they read 73.0, 73.0, 73.0
/// and 74.0 pt, a spread of 1.0, where the cell's own size reads 73.0, 77.5,
/// 81.5 and 85.0 pt. The pairs alone cannot show that the sets differ by more
/// than 4 in their frames, which is why the longer sets are in.
///
/// The sets span the glyph widths on purpose: a check fed one pair is a
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

    func testTheReserveCoversWhatTheSwitcherDrawsWhateverItsGlyphs() throws {
        PinnedBarSettings.pin(in: self)
        for look in [HelmBarAppearance.flat, .liquidGlass] {
            var drawnWidths: [CGFloat] = []
            for glyphs in Self.sets {
                let pair = "\(look) / " + glyphs.joined(separator: " / ")
                AppSettings.barAppearance = look
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
                        HelmToolbarAction(id: "viewMode", title: "View", isVisible: true,
                                          options: glyphs.enumerated().map {
                                              HelmToolbarTab(id: "option\($0.offset)", title: $0.element, symbol: $0.element)
                                          }, selection: .constant("option0")),
                        HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise",
                                          isVisible: buttonVisible) {},
                    ]), token: "test.reserveGlyphs", generation: channel.nextGeneration())
                    window.layoutIfNeeded()
                }

                declare(buttonVisible: true)
                let read = try ActionsCapsuleReading.read(try XCTUnwrap(window.toolbar, "\(pair): no toolbar"),
                                                          context: pair)
                let hosting = read.host
                let both = hosting.fittingSize.width
                let control = try XCTUnwrap(hosting.everyView(ofType: NSSegmentedControl.self).first,
                                            "\(pair): precondition — no switcher drawn")
                let cell = try XCTUnwrap(control.cell, "\(pair): precondition — the switcher has no cell")
                XCTAssertTrue(type(of: cell) == (look == .flat ? HelmFlatSegmentedCell.self : NSSegmentedCell.self), """
                    \(pair): precondition — the bar was built under \(look) and the switcher wears \(type(of: cell))
                    """)
                XCTAssertEqual(control.segmentCount, glyphs.count, "\(pair): precondition — the switcher has the wrong segments")
                XCTAssertTrue((0..<glyphs.count).allSatisfy { control.image(forSegment: $0) != nil },
                              "\(pair): precondition — a glyph is missing, so its width was never drawn")
                drawnWidths.append(control.frame.width)
                let entry = try XCTUnwrap(read.capsule.model.declared.first { $0.id == "viewMode" })
                let reserve = read.capsule.reserveWidth(entry)
                print("[reserve] \(pair): reserve \(reserve) pt, drawn \(control.frame.width) pt, "
                      + "intrinsic \(control.intrinsicContentSize.width) pt, capsule \(both) pt, cell \(type(of: cell))")
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
            // The subject: the sets really do draw at different widths, or this
            // is one set's numbers six times over.
            XCTAssertGreaterThan((drawnWidths.max() ?? 0) - (drawnWidths.min() ?? 0), 4, """
                precondition: the glyph sets drew \(drawnWidths) under \(look) — too close together to say \
                anything about glyph width
                """)
        }
    }
}
