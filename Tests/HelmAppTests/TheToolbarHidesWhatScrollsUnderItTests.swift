import XCTest
import HelmTestSupport

/// **On macOS 27 every settings page scrolls under a strip that lights up the
/// way the page header used to; on macOS 26 under the system's own scroll
/// edge.**
///
/// A page's scroll view runs under the window's toolbar, and the system's own
/// scroll edge effect attaches to it whatever the pane's content type —
/// `TheSystemsScrollEdgeEffectAttachesTests` is that measurement. Whether it
/// draws is the band decision's, `HelmBandChoice`: on macOS 27 the window's
/// `titlebarAppearsTransparent` is on, holds the effect at opacity 0, and the
/// strip is Helm's; on macOS 26 the flag is off and Helm draws no strip, which
/// leaves the pane to the system's effect (measured on 27, inferred for 26 —
/// `HelmBandChoice`'s own header). The pane keeps AppKit's safe area, so at
/// rest no content is under the bar; scrolled, content does pass beneath it,
/// and that is what lights the strip. The strip is `helmToolbarBackdrop`,
/// drawn by `HeaderEdgeLight` — whose pixels
/// `TheHeaderIsTheSystemsScrollEdgeTests` already reads — and lit by a
/// preference each page's bar reports from its own scroll view.
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
    /// finds only that comment). The claim this case exists to guard — the
    /// detail pane carries the backdrop modifier — still holds:
    /// `.helmToolbarBackdrop()` sits on `SettingsDetail` unconditionally. The
    /// band it draws is not unconditional: it draws Helm's band only where
    /// `HelmBandChoice.toolbarBand` is on, which is macOS 27, and on macOS 26
    /// draws none and leaves the pane to the system's own scroll-edge effect
    /// (the owner, 2026-09-27; `HelmBandChoice` holds the decision). A
    /// dev-only toggle once gated the call itself on a band style
    /// (`.modifier(ToolbarBackdropIfHelmBand())`) while the owner looked at
    /// the system's own scroll edge beside it; shown a screenshot of that
    /// alternative, the owner kept Helm's own band on 27.
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
