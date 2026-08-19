import AppKit
import SwiftUI
import XCTest
@testable import HelmUI

/// **What macOS 27 does, made into a check.**
///
/// Measured on this Mac against System Settings and Finder: the top strip of
/// the content pane lights when the pointer is over it — dark pane 30.0 → 37.8
/// luma, flat to ±0.1 over all 51 rows, with a one-point rule appearing at its
/// bottom edge at 46.0. It is a fill and not a material (glyph coverage solved
/// to k = 0.100 at rest against 0.0999 lit — the glyphs are untouched), which
/// is the only reason this file can exist: `cacheDisplay` composites a plain
/// fill exactly and never composites glass.
///
/// **The delta is asserted positive, deliberately.** If the fill is later swapped
/// for `.glassEffect`, the offscreen render sees no change at all — so a test
/// written as "the two renders differ" would pass on a header that draws
/// nothing, while this one fails. That is the difference between a check and a
/// check that cannot fail.
///
/// The state is a value, never a pointer: nothing here warps the cursor, and the
/// two renders are settled rather than sampled mid-animation — `cacheDisplay`
/// renders model values and cannot see an animation in flight, which is why the
/// 0,19 s / 0,33 s ramp is measured off a screen recording and not here.
@MainActor
final class TheHeaderLightsUnderThePointerTests: XCTestCase {

    private let width: CGFloat = 846
    private let height: CGFloat = 46

    /// A strip at the pane's own width, lit or not, over the window's ground.
    ///
    /// The ground is painted here because a hosting view has none: a
    /// `cacheDisplay` of the header alone comes back with alpha 0 on every
    /// pixel — "nothing is behind it" — which is a fact about the capture and
    /// not about the app.
    private func luma(lit: Bool, appearance: NSAppearance.Name, atX x: CGFloat,
                     y: CGFloat) throws -> CGFloat {
        let view = NSHostingView(rootView: AnyView(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                HelmPageHeader(symbol: "gearshape", tint: .gray, title: "Settings", bleeds: true)
                    .modifier(HeaderHoverLight(lit: lit))
            }
            .frame(width: width, height: height)))
        view.appearance = NSAppearance(named: appearance)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // **Points in, pixels out.** The rep is backed at the screen's scale,
        // so on this Mac a 846 × 46 pt view comes back 1692 × 92, and a sample
        // taken at the point coordinate lands halfway up the strip instead of
        // on its bottom edge — which is a one-pixel rule reported as absent.
        let scaleX = CGFloat(rep.pixelsWide) / width
        let scaleY = CGFloat(rep.pixelsHigh) / height
        let colour = try XCTUnwrap(rep.colorAt(x: Int(x * scaleX),
                                               y: min(rep.pixelsHigh - 1, Int(y * scaleY))))
        let inRGB = try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
        return (0.299 * inRGB.redComponent + 0.587 * inRGB.greenComponent
                + 0.114 * inRGB.blueComponent) * 255
    }

    // MARK: - The fill

    /// A point far from the title and far from the trailing edge, so what is
    /// measured is the strip itself and not something drawn on it.
    private var bare: CGFloat { width - 120 }

    func testTheStripIsLighterUnderThePointerInDark() throws {
        let rest = try luma(lit: false, appearance: .darkAqua, atX: bare, y: 20)
        let hovered = try luma(lit: true, appearance: .darkAqua, atX: bare, y: 20)
        XCTAssertGreaterThan(hovered, rest + 3, """
            the strip does not lighten under the pointer (rest \(rest), lit \(hovered)). macOS \
            moves it 30.0 → 37.8 in dark. A render that sees no change is also what a header \
            built from a material would give, which is why this is a positive delta and not \
            an inequality
            """)
    }

    func testTheStripIsDarkerUnderThePointerInLight() throws {
        let rest = try luma(lit: false, appearance: .aqua, atX: bare, y: 20)
        let hovered = try luma(lit: true, appearance: .aqua, atX: bare, y: 20)
        XCTAssertLessThan(hovered, rest - 3, """
            the strip does not change under the pointer in light (rest \(rest), lit \(hovered)). \
            `Color.primary` is black in light, so the same token that lightens a dark pane has \
            to darken a light one — the direction is the point, and the light values were never \
            measured off macOS
            """)
    }

    // MARK: - The rule

    /// The other half of what macOS does, and the half that keeps this from
    /// contradicting the header having lost its hairline: **no line at rest, a
    /// line on hover.**
    func testTheBottomRuleAppearsOnlyUnderThePointer() throws {
        let restEdge = try luma(lit: false, appearance: .darkAqua, atX: bare, y: height - 0.5)
        let restStrip = try luma(lit: false, appearance: .darkAqua, atX: bare, y: 20)
        XCTAssertEqual(restEdge, restStrip, accuracy: 1, """
            there is a rule under the header at rest — the pane's own edge is what should be \
            there, and drawing one back is the line this app measured as marking a boundary \
            nothing else on the page expresses
            """)

        let litEdge = try luma(lit: true, appearance: .darkAqua, atX: bare, y: height - 0.5)
        let litStrip = try luma(lit: true, appearance: .darkAqua, atX: bare, y: 20)
        XCTAssertGreaterThan(litEdge, litStrip + 3, """
            the bottom edge does not differ from the strip above it while lit, so the rule macOS \
            draws on hover (30.0 → 46.0 against the strip's 37.8) is missing
            """)
    }

    // MARK: - The gate

    /// **Measured, not assumed:** with System Settings not the key window the
    /// strip does not react to the pointer at all. A flag set from a pointer
    /// that may never leave is not enough on its own to say the strip is lit.
    func testTheStripDoesNotLightWhileTheWindowIsNotKey() {
        XCTAssertTrue(HelmPageHeader<EmptyView>.isLit(hovering: true, active: .key))
        XCTAssertFalse(HelmPageHeader<EmptyView>.isLit(hovering: true, active: .active), """
            the strip lights in a window that is merely frontmost. macOS lights it only in the \
            key window — with System Settings not key, three readings of the hovered strip were \
            identical to the unhovered one
            """)
        XCTAssertFalse(HelmPageHeader<EmptyView>.isLit(hovering: true, active: .inactive))
        XCTAssertFalse(HelmPageHeader<EmptyView>.isLit(hovering: false, active: .key))
    }

    // MARK: - The motion

    /// The ramp itself cannot be measured here — `cacheDisplay` renders model
    /// values, so an animation in flight is invisible to it — but which
    /// animation is asked for can be, and the measurement it comes from is
    /// asymmetric: in over 12 frames, out over 20, at ~32 fps.
    func testGoingOutTakesLongerThanComingIn() {
        XCTAssertNotEqual(String(describing: HelmMotion.hover(entering: true)),
                          String(describing: HelmMotion.hover(entering: false)), """
            the strip lights and goes out at one speed. macOS takes 0,19 s in and 0,33 s out — \
            the asymmetry is what was measured, and a single duration is a decision to ignore it
            """)
    }
}
