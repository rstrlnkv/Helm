import XCTest
import HelmTestSupport

/// **Every settings page scrolls under a strip that lights up the way the page
/// header used to.**
///
/// A page's scroll view runs under the window's toolbar, and the system's own
/// scroll edge effect is held there at opacity 0 by the window's
/// `titlebarAppearsTransparent` — it attaches, and the pane's content type has
/// nothing to do with it; `TheSystemsScrollEdgeEffectAttachesTests` is that
/// measurement. Let through it would draw next to nothing anyway, because the
/// pane keeps AppKit's safe area and a page's content never passes beneath the
/// bar. The strip is `helmToolbarBackdrop`, drawn by `HeaderEdgeLight` —
/// whose pixels `TheHeaderIsTheSystemsScrollEdgeTests` already reads — and lit
/// by a preference each page's bar reports from its own scroll view.
///
/// Read off the construction, because the strip's height is the window
/// toolbar's safe area and the lighting needs a real scroll, neither of which a
/// page drawn on its own in a hosting view has. Photographed on the dev build
/// instead, Keep Awake scrolled 90 pt: the strip 37 with its rule 50 on the
/// last row, against 30 flat at rest.
final class TheToolbarHidesWhatScrollsUnderItTests: XCTestCase {

    /// **Retargeted 2026-09-23: the detail pane's toolbar is `SettingsToolbar`'s
    /// now, not a SwiftUI bridge.** `SettingsWindow.swift` says why on the
    /// controller itself: "no `sceneBridgingOptions` is set on this
    /// controller, on purpose" — so a scan for that property no longer finds
    /// anything to bound the search by (measured:
    /// `command grep -n sceneBridgingOptions Sources/HelmApp/SettingsWindow.swift`
    /// finds only that comment). The claim this case exists to guard —
    /// the detail pane actually carries the backdrop strip — still holds:
    /// `.helmToolbarBackdrop()` sits on `SettingsDetail` unconditionally. A
    /// dev-only toggle gated this call on a band style for a stretch
    /// (`.modifier(ToolbarBackdropIfHelmBand())`) while the owner looked at
    /// the system's own scroll edge beside it; shown a screenshot of that
    /// alternative, the owner kept Helm's own band and the call is
    /// unconditional again.
    func testTheDetailPaneCarriesTheBackdrop() throws {
        let window = "Sources/HelmApp/SettingsWindow.swift"
        let code = SwiftSource.code(try RepoSource.text(of: window))
        let detail = try XCTUnwrap(code.range(of: "rootView: SettingsDetail(model: model)"),
                                   "\(window) no longer builds the detail pane from SettingsDetail")
        let sizing = try XCTUnwrap(code.range(of: "detail.sizingOptions",
                                              range: detail.upperBound..<code.endIndex),
                                   "could not bound the detail pane's own view-builder block")
        XCTAssertTrue(code[detail.upperBound..<sizing.lowerBound].contains(".helmToolbarBackdrop()"), """
            the settings pane has no strip under the toolbar — content scrolls straight through \
            the window's title on every page without a glass control
            """)
        XCTAssertTrue(code[detail.upperBound..<sizing.lowerBound].contains("helmWindowToolbarChannel"), """
            the detail pane no longer publishes into the channel `SettingsToolbar` reads — every \
            page's `.helmWindowToolbar` call would have nowhere to declare into
            """)
    }

    /// Both shapes of the bar report, or the strip under one of them never
    /// lights however far the page is scrolled.
    func testEveryBarShapeReportsItsScroll() throws {
        let file = "Sources/HelmUI/DesignSystem/PageBarStyle.swift"
        let code = SwiftSource.code(try RepoSource.text(of: file))
        for shape in ["case .windowTitle:", "case .moduleName:"] {
            let start = try XCTUnwrap(code.range(of: shape), "\(file) has no \(shape)")
            let end = code.range(of: "case .", range: start.upperBound..<code.endIndex)?.lowerBound
                ?? code.endIndex
            XCTAssertTrue(code[start.upperBound..<end].contains(".modifier(ReportsScrolledUnderBar())"), """
                the \(shape.dropFirst(5).dropLast()) bar does not report its page's scroll, so the \
                strip above that page stays unlit with content under it
                """)
        }
    }
}
