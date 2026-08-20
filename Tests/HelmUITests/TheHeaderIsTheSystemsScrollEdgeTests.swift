import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The page header at the system's height, with one appearance and two
/// reasons to wear it.**
///
/// The height is the system's. Measured on System Settings' Accessibility pane,
/// macOS 27, dark, captured through the real compositor with `screencapture -l`
/// at 2× and divided back: 11,5 pt above a 29,0 pt control and 11,5 below it —
/// a **52,0 pt** strip. The sum is taken and the parts are not: 12 is
/// `HelmSpace.s5` where 11,5 is a step of nothing, and the plate stays 28
/// because that is `HelmIconPlate`'s size, so 12 + 28 + 12 lands on the
/// system's total by way of numbers this app already has.
///
/// # The edge is deliberately not the system's, and that is the point
///
/// The system's separator is a **0,5 pt rule at luma 46,0 over a 30,0 pane**,
/// uniform to sd 0,00 across the pane's whole width, belonging to the scroll
/// view rather than the toolbar — it runs the detail pane's width exactly and
/// stops dead at the sidebar. And it is present **at the scroll origin**: 2400
/// px of scroll-up did not remove it, and scrolling moves only the strip, by
/// 2,6 luma.
///
/// **Helm does not do that, on purpose.** At rest its header draws nothing —
/// no fill and no rule. Both appear together, for either of two reasons: the
/// pointer is over the strip, or the content has scrolled up under it. One
/// look, two triggers. `HelmPageHeader.isLit` is where that decision is written
/// down; this file is where it is checked, and the checks are written so that
/// somebody restoring the system's always-on rule fails them rather than
/// quietly improving the app.
///
/// # What this file proves, and the half of it that cannot be proved here
///
/// The fill and the rule are plain fills, so `cacheDisplay` composites them
/// exactly and every reading below is real. **The material is not**: an
/// offscreen render never composites glass, so a pixel taken of the strip's
/// surface is the un-composited fill underneath and would read the same
/// whatever material — or no material — the header names. A pixel test of the
/// blur would pass on a header that had lost it, which is the shape
/// ARCHITECTURE.md § A check that cannot fail is not a check exists to name.
/// The material is therefore guarded **by construction**, and every message
/// here that touches the strip's surface says so, so a green run is never read
/// as coverage of the composite.
@MainActor
final class TheHeaderIsTheSystemsScrollEdgeTests: XCTestCase {

    /// The settings window's detail pane at the default 1060 pt window.
    private let width: CGFloat = 845

    // MARK: - The height

    /// 52,0, the system's — and asserted off the render rather than against the
    /// three constants the header adds up, which would be one number compared
    /// with itself.
    func testTheStripIsTheSystemsFiftyTwoPoints() {
        let view = NSHostingView(rootView: AnyView(
            HelmPageHeader(symbol: "gearshape", tint: .gray, title: "Settings", bleeds: true)
                .frame(width: width)))

        XCTAssertEqual(view.fittingSize.height, 52, accuracy: 0.5, """
            the page header is \(view.fittingSize.height) pt tall against the 52,0 System \
            Settings draws — measured on the Accessibility pane at 2×, 11,5 above a 29,0 pt \
            back-forward control and 11,5 below it
            """)
    }

    // MARK: - The predicate: one appearance, two triggers

    /// The question itself, before any pixels: nothing at rest, the same answer
    /// for the pointer and for the content.
    func testTheStripIsLitByThePointerOrByTheContentGoingUnderIt() {
        typealias Header = HelmPageHeader<EmptyView>

        XCTAssertFalse(Header.isLit(hovering: false, active: .key, scrolled: false),
                       "the strip is lit at rest — macOS lights nothing there and neither do we")
        XCTAssertTrue(Header.isLit(hovering: true, active: .key, scrolled: false),
                      "the pointer over the strip does not light it")
        XCTAssertTrue(Header.isLit(hovering: false, active: .key, scrolled: true),
                      "content gone under the strip does not light it")
        XCTAssertTrue(Header.isLit(hovering: true, active: .key, scrolled: true),
                      "both reasons at once put the strip out")
    }

    /// **Measured, not assumed:** with System Settings not the key window the
    /// strip does not react to the pointer at all. A flag set from a pointer
    /// that may never leave is not enough on its own to say the strip is lit.
    ///
    /// And `scrolled` is *not* gated the same way, which is the half a
    /// symmetrical test would have got wrong: hover being ignored in a
    /// background window is a fact about the pointer, while content sitting
    /// under the strip is a fact about the page — a background window whose
    /// text ran unmarked into its header would be showing the very defect the
    /// strip is there to prevent.
    func testThePointerNeedsTheKeyWindowAndTheContentDoesNot() {
        typealias Header = HelmPageHeader<EmptyView>

        XCTAssertFalse(Header.isLit(hovering: true, active: .active, scrolled: false), """
            the strip lights in a window that is merely frontmost. macOS lights it only in the \
            key window — with System Settings not key, three readings of the hovered strip were \
            identical to the unhovered one
            """)
        XCTAssertFalse(Header.isLit(hovering: true, active: .inactive, scrolled: false))
        XCTAssertTrue(Header.isLit(hovering: false, active: .inactive, scrolled: true), """
            a background window whose content has gone under its header draws no strip — so the \
            page's text runs into its own title in every window that is not key, which is what \
            the strip exists to stop. The key gate belongs to the pointer, not to the content
            """)
    }

    // MARK: - The pixels: nothing at rest, both together when lit

    /// At rest the strip is the pane and the edge is the pane: no fill, no rule.
    ///
    /// Asserted first because everything below is a *difference from* this, and
    /// a render that drew nothing at all would satisfy those differences too.
    func testAtRestTheHeaderDrawsNeitherFillNorRule() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let strip = try luma(lit: false, overContent: true, appearance: appearance, atY: .strip)
            let edge = try luma(lit: false, overContent: true, appearance: appearance, atY: .edge)
            let ground = try luma(lit: false, overContent: false,
                                  appearance: appearance, atY: .strip)

            XCTAssertEqual(strip, ground, accuracy: 1, """
                the strip at rest is not the pane it sits on (\(strip) against \(ground)) in \
                \(appearance.rawValue) — Helm draws no fill until the pointer arrives or the \
                content goes under. \(Self.compositeCaveat)
                """)
            XCTAssertEqual(edge, strip, accuracy: 1, """
                there is a rule under the header at rest (strip \(strip), edge \(edge)) in \
                \(appearance.rawValue). **System Settings does draw one there** — measured, at \
                the scroll origin, and 2400 px of scroll-up did not remove it — and Helm \
                deliberately does not. Restoring it is a decision to take with the owner, not a \
                repair; see `HelmPageHeader.isLit`
                """)
        }
    }

    /// Lit — by either trigger, since the predicate has already folded them —
    /// the fill and the rule arrive **together**.
    ///
    /// **Positive deltas, deliberately.** Written as "the two renders differ"
    /// this would pass on a header that had lost the fill and gained a rule, or
    /// on one built from a material the render cannot see.
    func testLitTheFillAndTheRuleArriveTogether() throws {
        let rest = try luma(lit: false, overContent: true, appearance: .darkAqua, atY: .strip)
        let strip = try luma(lit: true, overContent: true, appearance: .darkAqua, atY: .strip)
        let edge = try luma(lit: true, overContent: true, appearance: .darkAqua, atY: .edge)

        XCTAssertGreaterThan(strip, rest + 3, """
            the strip does not lighten when lit (rest \(rest), lit \(strip)). macOS moves it \
            30,0 → 37,8 in dark. \(Self.compositeCaveat)
            """)
        XCTAssertGreaterThan(edge, strip + 3, """
            the strip lightened but no rule came with it (strip \(strip), edge \(edge)) — the \
            two are one appearance with one trigger, and half of it is missing
            """)
    }

    /// The same appearance in light, where `Color.primary` is black: the
    /// direction is what is asserted, because the light values were never
    /// measured off macOS.
    func testLitTheStripDarkensALightPane() throws {
        let rest = try luma(lit: false, overContent: true, appearance: .aqua, atY: .strip)
        let strip = try luma(lit: true, overContent: true, appearance: .aqua, atY: .strip)
        let edge = try luma(lit: true, overContent: true, appearance: .aqua, atY: .edge)

        XCTAssertLessThan(strip, rest - 3, """
            the strip does not change when lit in light (rest \(rest), lit \(strip)). \
            `Color.primary` is black in light, so the same token that lightens a dark pane has \
            to darken a light one — the direction is the point. \(Self.compositeCaveat)
            """)
        XCTAssertLessThan(edge, strip - 3, """
            the rule is invisible in light (strip \(strip), edge \(edge)) — a mark that shows in \
            one appearance and not the other is a mark drawn in a literal colour
            """)
    }

    /// **One rule, not two.**
    ///
    /// The two triggers are folded before anything is drawn, so a header that is
    /// hovered *and* scrolled has to look exactly like one that is only
    /// hovered. Two fills at α 0,071 compose to 0,137 and the edge lands half
    /// again as bright — **a real reading, not arithmetic**: an early draft of
    /// this file applied the chrome twice by accident and that stacked pair
    /// solved to α 0,156 against the 0,084 one rule reads here.
    ///
    /// Nothing offscreen can move a pointer or a scroll view, so what is
    /// compared is the *drawn* state either side of `overContent` — the flag
    /// that would carry a second rule if the rule were keyed on the scroll edge
    /// separately from the pointer, which is the shape this forbids.
    func testTheLitStripLooksTheSameWhicheverReasonLitIt() throws {
        let strip = try luma(lit: true, overContent: false, appearance: .darkAqua, atY: .strip)
        let alone = try luma(lit: true, overContent: false, appearance: .darkAqua, atY: .edge)
        let overContent = try luma(lit: true, overContent: true, appearance: .darkAqua, atY: .edge)

        XCTAssertGreaterThan(alone, strip + 3, """
            precondition: there is no rule under the lit header to count (strip \(strip), \
            edge \(alone)), so the comparison below is between two absences and passes for free
            """)
        XCTAssertEqual(overContent, alone, accuracy: 1, """
            the rule under a lit header over scrolling content (\(overContent)) is not the rule \
            under a lit header with nothing behind it (\(alone)) — the scroll edge is drawing a \
            second line of its own on top of the one the pointer draws, where the two are meant \
            to be one appearance asked for once
            """)
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

    // MARK: - The material, which pixels cannot answer for

    /// **The half no render can check, checked the only way it can be.**
    ///
    /// The strip is a material: solving the composite gave 32,2 % of the
    /// backdrop passed, and a card's edge came through at the predicted 32 %
    /// (2,25 against 2,36 measured) while text was destroyed — strip max
    /// gradient 1,93 against the content's 51,00, a ratio of 0,038 where a
    /// plain 32 % fill predicts 0,32. Low frequencies through, high frequencies
    /// gone: a blur.
    ///
    /// None of that is visible to `cacheDisplay`, which renders the fill under
    /// the glass and hands it back unchanged. So this reads the construction:
    /// the header names a `Material`, and the strip's own surface is filled
    /// with it. Swap it for a `Color` and this fails; swap it for a *different*
    /// material and nothing here notices, which is stated rather than hidden.
    func testTheScrollEdgeIsBuiltOnAMaterialTheHeaderNames() throws {
        let source = try RepoSource.text(of: Self.headerFile)

        XCTAssertTrue(source.contains("static let material: Material"), """
            `HeaderEdgeLight` no longer names a `Material` for its scroll edge. This is the \
            only guard the material has — an offscreen render composites no glass — so the \
            name going away takes the last check with it
            """)
        XCTAssertTrue(source.contains("Rectangle().fill(Self.material)"), """
            the scroll edge's surface is no longer filled with the material `HeaderEdgeLight` \
            names. A constant nothing draws with is not a material; \(Self.compositeCaveat)
            """)
    }

    // MARK: - The wiring the renders above deliberately step around

    /// The renders put `HeaderEdgeLight` on from outside, because a header's own
    /// copy reads a pointer no offscreen render can move and a scroll view no
    /// offscreen render has. So the three joints between the header, its chrome
    /// and the page are read here instead.
    ///
    /// Without this, `scrolled` could stop reaching the modifier entirely and
    /// every pixel test in this file would go on passing, because none of them
    /// renders the path that carries it.
    func testTheHeaderHandsItsFactsToTheStripAndThePageReportsTheScroll() throws {
        let source = try RepoSource.text(of: Self.headerFile)

        XCTAssertTrue(source.contains("scrolled: scrolled),\n                                  "
                                      + "overContent: overContent))"), """
            `HelmPageHeader` no longer hands both of its facts to `HeaderEdgeLight` — they are \
            stored, the modifier is applied, and nothing connects them
            """)
        XCTAssertTrue(source.contains("overContent: true, scrolled: scrolled"), """
            `helmPageHeader` no longer builds its header over the content. It is the only thing \
            that may: laying the header over the page is what makes the strip's material mean \
            anything, and a page that draws `HelmPageHeader` directly must not get one
            """)
        XCTAssertTrue(source.contains(".onScrollGeometryChange(for: Bool.self)"), """
            nothing asks the scroll view where it is any more, so `scrolled` is whatever it was \
            initialised to — false — and the strip will never light for the content again. The \
            offset is the scroll view's to report; a header that inferred it would be the flag \
            standing in for a live fact that CLAUDE.md names as its own family of defect
            """)
    }

    /// And the scans above can fail: they read one file by path, and a file that
    /// has moved reads as empty and passes everything.
    func testTheConstructionScanIsReadingTheFileItThinksItIs() throws {
        let source = try RepoSource.text(of: Self.headerFile)

        XCTAssertTrue(source.contains("struct HeaderEdgeLight"), """
            \(Self.headerFile) does not hold `HeaderEdgeLight` — the material scan above is \
            reading some other file, or none, and passes on whatever the header now draws
            """)
    }

    private static let headerFile = "Sources/HelmUI/DesignSystem/HelmPageHeader.swift"

    /// Said in every message that touches the strip's surface, so a green run
    /// here can never be read as proof of a blur nobody measured.
    private static let compositeCaveat =
        "note: the composite half of this strip is unguarded — `cacheDisplay` never composites "
        + "a material, so the material itself is checked by construction only "
        + "(`testTheScrollEdgeIsBuiltOnAMaterialTheHeaderNames`)."

    // MARK: - Reading the pixels

    /// Where a sample is taken: the strip's own surface, or the one row the
    /// rule occupies.
    private enum Row { case strip, edge }

    /// A point far from the title and far from the trailing edge, so what is
    /// read is the strip and not something drawn on it.
    private var bare: CGFloat { width - 120 }

    /// The strip over the window's ground, lit or not, over content or not.
    ///
    /// The ground is painted here because a hosting view has none: a
    /// `cacheDisplay` of the header alone comes back with alpha 0 on every
    /// pixel — a fact about the capture and not about the app.
    ///
    /// **The header is built plain and the state is put on from outside**: a
    /// header's own
    /// `HeaderEdgeLight` reads a pointer this render cannot move and a scroll
    /// view it does not have. Built with its own chrome switched on it would
    /// carry a second copy of the modifier under this one, and the first
    /// reading taken that way solved to α 0,156 — the stacking this file exists
    /// to catch, manufactured by its own fixture. Plain, the header's own
    /// modifier is inert (not lit, nothing behind it) and exactly one is under
    /// measurement. What that leaves unmeasured is read out of the source by
    /// `testTheHeaderHandsItsFactsToTheStripAndThePageReportsTheScroll`.
    private func luma(lit: Bool, overContent: Bool, appearance: NSAppearance.Name,
                      atY row: Row) throws -> CGFloat {
        let height: CGFloat = 52
        let view = NSHostingView(rootView: AnyView(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                HelmPageHeader(symbol: "gearshape", tint: .gray, title: "Settings", bleeds: true)
                    .modifier(HeaderEdgeLight(lit: lit, overContent: overContent))
            }
            .frame(width: width, height: height)))
        view.appearance = NSAppearance(named: appearance)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // **Points in, pixels out.** The rep is backed at the screen's scale, so
        // the rule is the last pixel row and nothing else — sampled at the point
        // coordinate it lands halfway up the strip, which is a rule reported as
        // absent.
        let scaleX = CGFloat(rep.pixelsWide) / width
        let scaleY = CGFloat(rep.pixelsHigh) / height
        let y = row == .edge ? rep.pixelsHigh - 1 : Int(20 * scaleY)
        let colour = try XCTUnwrap(rep.colorAt(x: Int(bare * scaleX), y: y))
        let inRGB = try XCTUnwrap(colour.usingColorSpace(.deviceRGB))
        return (0.299 * inRGB.redComponent + 0.587 * inRGB.greenComponent
                + 0.114 * inRGB.blueComponent) * 255
    }
}
