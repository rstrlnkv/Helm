import XCTest
import HelmTestSupport

/// **Every settings page scrolls under a strip that lights up the way the page
/// header used to.**
///
/// A page's scroll view runs under the window's toolbar, and the system's
/// scroll edge effect drew nothing there for a SwiftUI `Form` in this pane:
/// photographed 2026-09-17, Keep Awake's hero figure ran through the window
/// title with nothing between them, and `scrollEdgeEffectStyle(.hard)` changed
/// no pixel. The strip is `helmToolbarBackdrop`, drawn by `HeaderEdgeLight` —
/// whose pixels `TheHeaderIsTheSystemsScrollEdgeTests` already reads — and lit
/// by a preference each page's bar reports from its own scroll view.
///
/// Read off the construction, because the strip's height is the window
/// toolbar's safe area and the lighting needs a real scroll, neither of which a
/// page drawn on its own in a hosting view has. Photographed on the dev build
/// instead, Keep Awake scrolled 90 pt: the strip 37 with its rule 50 on the
/// last row, against 30 flat at rest.
final class TheToolbarHidesWhatScrollsUnderItTests: XCTestCase {

    func testTheDetailPaneCarriesTheBackdrop() throws {
        let window = "Sources/HelmApp/SettingsWindow.swift"
        let code = SwiftSource.code(try RepoSource.text(of: window))
        let detail = try XCTUnwrap(code.range(of: "rootView: SettingsDetail(model: model)"),
                                   "\(window) no longer builds the detail pane from SettingsDetail")
        let bridged = try XCTUnwrap(code.range(of: "detail.sceneBridgingOptions",
                                               range: detail.upperBound..<code.endIndex),
                                    "the detail pane no longer bridges its toolbar")
        XCTAssertTrue(code[detail.upperBound..<bridged.lowerBound].contains(".helmToolbarBackdrop()"), """
            the settings pane has no strip under the toolbar — content scrolls straight through \
            the window's title on every page without a glass control
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
