import AppKit
import HelmTestSupport
import XCTest
@testable import HelmUI

/// **A `.segmented` action in the actions capsule is always glyphs, never
/// the tabs' own label style.** This action has no word of its own to fall
/// back to (`HelmToolbarAction`'s own segmented initialiser fixes the
/// action's `symbol` to `""`), so the tabs' `.text` or `.iconsAndText`
/// drew Hosts' Table / Plain-text pair as a second, worded set of tabs
/// beside the first — the owner's own report (2026-09-25). Each segment
/// keeps its word for VoiceOver and as a tooltip regardless
/// (`HelmToolbarSwitcher.fill`'s own `setToolTip`); this file is only about
/// what is drawn on the segment itself, whatever style it is handed.
@MainActor
final class ASegmentedActionIsAlwaysGlyphsTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// `reserveWidth: 0` — nothing here reads it. `SettingsToolbar.actionEntries(for:)`
    /// is what measures the real number, on a live bar
    /// (`ASegmentedEntrysReserveCoversItsOwnGlyphsTests`); this fixture is
    /// only about what a `.segmented` entry draws, never about its reserve.
    private func segmented() -> HelmToolbarActionsModel.Entry {
        HelmToolbarActionsModel.Entry(
            id: "viewMode", title: "View", symbol: "", isEnabled: true,
            kind: .segmented([
                .init(id: "table", title: "Table", symbol: "tablecells"),
                .init(id: "text", title: "Plain text", symbol: "text.alignleft"),
            ], selectedID: "table", reserveWidth: 0))
    }

    /// Mounted under an *ambient* label style — the one an environment above
    /// the capsule would otherwise hand every switcher below it —
    /// `HelmToolbarActionsCapsule`'s own `.segmented` branch has to override
    /// this, not merely default to something that happens to agree with it.
    private func mount(ambient style: ToolbarSwitcherStyle) -> MountedRender {
        let model = HelmToolbarActionsModel()
        model.setDeclared([segmented()])
        model.setVisibleIDs(["viewMode"])
        let view = HelmToolbarActionsCapsule(model).environment(\.helmSwitcherStyle, style)
        let render = MountedRender(view, width: 400, height: 60, appearance: .aqua)
        renders.append(render)
        return render
    }

    func testEverySegmentDrawsAGlyphAndNoWordWhateverTheAmbientStyleIs() throws {
        for style in ToolbarSwitcherStyle.allCases {
            let render = mount(ambient: style)
            let control = try XCTUnwrap(render.host.everyView(ofType: NSSegmentedControl.self).first,
                                        "\(style): no segmented control mounted")
            XCTAssertGreaterThan(control.segmentCount, 0, "\(style): precondition — no segments filled")
            for index in 0..<control.segmentCount {
                XCTAssertEqual(control.label(forSegment: index), "", """
                    \(style): segment \(index) carries a word — a `.segmented` action must draw \
                    glyphs only, whatever the ambient label style is
                    """)
                XCTAssertNotNil(control.image(forSegment: index),
                                "\(style): segment \(index) has no glyph")
            }
        }
    }
}
