import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **The page's word about what is under its band, read off the window that
/// draws it.**
///
/// `TheBandStandsOnWhatIsUnderItTests` reads the split — which pages declare
/// `helmPageStandsOnStillContent`, and that nothing computes the fact from the
/// header's width — and it reads it out of the source.
/// `TheHeaderIsTheSystemsScrollEdgeTests` reads the predicate and the pixels of
/// the header a page draws **in the page**. Neither of them can see the placement that actually
/// ships: in the settings window the header is in the window's toolbar, the
/// band is `helmToolbarBackdrop`'s, and the declaration has to travel from the
/// page, up as a preference, into a modifier a window away.
///
/// That road was guarded by two string matches on `PageBarStyle.swift` — the
/// `onPreferenceChange` line and the argument list. A string match cannot tell
/// a wiring that works from a wiring that compiles: a preference read into a
/// `@State` the overlay never rebuilds on, a backdrop applied outside the view
/// that publishes, a window whose safe area is zero so the band has no height
/// to draw in — every one of those leaves both strings exactly where they are.
/// So this file builds the window and reads the pixels.
///
/// # The window is the settings window's shape and not a convenience
///
/// `NSHostingController` with `sceneBridgingOptions = [.toolbars]`, a
/// `.fullSizeContentView` mask and `titlebarAppearsTransparent` — the three
/// things `SettingsWindow` and `SettingsSplitViewController` set. The last one
/// is load-bearing twice over: it is what withholds the system's own scroll
/// edge effect (`TheSystemsScrollEdgeEffectAttachesTests`), which is why Helm
/// draws this band at all, and it is what gives the pane a 52 pt top safe area
/// for the band to be drawn in. A window without it hands `GeometryReader` a
/// zero inset and every reading below would be of a band 0 pt tall — which is
/// the same numbers a band that was never lit prints.
///
/// # What is read
///
/// Two rows: the strip's own surface, well below the toolbar's items, and the
/// **last pixel row of the safe area**, which is where `HeaderEdgeLight` puts
/// its rule. Both appearances, and the direction is asserted in each —
/// `Color.primary` is white in dark and black in light, so one token darkens
/// one pane and lightens the other, and a test that asserted "darker" would be
/// green in light and red at sunset on this Mac.
///
/// The unlit reading is taken from the same fixture with the one modifier
/// removed, and is the precondition for every lit one: without it these pass
/// over a band drawn unconditionally, which is the far side of the same defect.
@MainActor
final class TheWindowsBandReadsTheDeclarationTests: XCTestCase {

    /// The page swaps between one that declares and one that does not, on a
    /// published flag, because a settings page change is exactly that — and
    /// because a preference that is never *withdrawn* is the second half of
    /// this wiring and looks identical to a working one until somebody opens
    /// General after Homebrew.
    private final class Pages: ObservableObject {
        @Published var declaring: Bool
        init(declaring: Bool) { self.declaring = declaring }
    }

    private struct Detail: View {
        @ObservedObject var pages: Pages

        var body: some View {
            Group {
                if pages.declaring {
                    ground.helmPageStandsOnStillContent()
                } else {
                    ground
                }
            }
            // Applied here, outside the page and inside the window, exactly
            // where `SettingsSplitViewController` applies it.
            .helmToolbarBackdrop()
            // Every settings page carries one, and a page without it drops the
            // window's toolbar — and with it the safe area this band lives in.
            .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }

        /// A flat, opaque ground: the band's fill and its rule are plain fills
        /// over it, so `cacheDisplay` composites them exactly. The material
        /// under them is not composited offscreen and is not claimed here —
        /// `TheHeaderIsTheSystemsScrollEdgeTests` carries that caveat for the
        /// same modifier.
        private var ground: some View {
            Color(nsColor: .windowBackgroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A window built the way the settings window is, held so the readings can
    /// be taken from it more than once.
    @MainActor private final class Pane {
        let window: NSWindow
        let pages: Pages

        init(declaring: Bool, appearance: NSAppearance.Name) {
            pages = Pages(declaring: declaring)
            let controller = NSHostingController(rootView: Detail(pages: pages))
            controller.sceneBridgingOptions = [.toolbars]
            controller.sizingOptions = []
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: Pane.width, height: 300))
            window.appearance = NSAppearance(named: appearance)
        }

        /// The settings window's own default, so the band is measured at the
        /// width the app opens at rather than one chosen to make a number come
        /// out.
        static let width: CGFloat = 1060

        func settle(_ turns: Int = 30) {
            for _ in 0..<turns {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        func drop() { window.contentViewController = nil }
    }

    private var panes: [Pane] = []

    override func tearDown() {
        panes.forEach { $0.drop() }
        panes = []
        super.tearDown()
    }

    private func pane(declaring: Bool, appearance: NSAppearance.Name) -> Pane {
        let pane = Pane(declaring: declaring, appearance: appearance)
        panes.append(pane)
        pane.settle()
        return pane
    }

    /// Where a sample is taken: the strip's own surface, or the one pixel row
    /// the rule occupies.
    private enum Row { case strip, edge }

    /// The luma of one point of the window's own band.
    ///
    /// Fails rather than returns a number when the pane has no top safe area:
    /// a zero inset is a band with no height, and every reading taken of one
    /// prints what an unlit band prints.
    private func luma(_ pane: Pane, _ row: Row, _ what: String,
                      file: StaticString = #filePath, line: UInt = #line) throws -> CGFloat {
        let host = try XCTUnwrap(pane.window.contentView, "\(what): the window has no content view",
                                 file: file, line: line)
        let inset = host.safeAreaInsets.top
        guard inset > 1 else {
            XCTFail("""
                \(what): the pane's top safe area is \(inset) pt, so `helmToolbarBackdrop` is \
                drawing a band of no height and every reading of it is the ground. The toolbar \
                or `.fullSizeContentView` has gone from this fixture
                """, file: file, line: line)
            throw XCTSkip("no band to read")
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds),
                                "\(what): the pane would not cache its display",
                                file: file, line: line)
        host.cacheDisplay(in: host.bounds, to: rep)
        // **Points in, pixels out.** The rule is one device pixel at the very
        // bottom of the inset; sampled at the point coordinate it lands
        // halfway up the strip, which is a rule reported as absent.
        let scale = CGFloat(rep.pixelsHigh) / host.bounds.height
        let y = row == .edge ? Int(inset * scale) - 1 : Int(20 * scale)
        // Far from the traffic lights and far from the trailing edge, so what
        // is read is the band and not something drawn on it.
        let x = Int(Pane.width / 2 * CGFloat(rep.pixelsWide) / host.bounds.width)
        let colour = try XCTUnwrap(rep.colorAt(x: x, y: y), "\(what): no pixel at \(x), \(y)",
                                   file: file, line: line)
        let rgb = try XCTUnwrap(colour.usingColorSpace(.deviceRGB), file: file, line: line)
        return (0.299 * rgb.redComponent + 0.587 * rgb.greenComponent
                + 0.114 * rgb.blueComponent) * 255
    }

    /// **The whole road, end to end, in both appearances.**
    func testAPageThatDeclaresLightsTheWindowsBandAndOneThatDoesNotDoesNot() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let dark = appearance == .darkAqua
            let silent = pane(declaring: false, appearance: appearance)
            let declaring = pane(declaring: true, appearance: appearance)

            let plainStrip = try luma(silent, .strip, "silent strip, \(appearance.rawValue)")
            let plainEdge = try luma(silent, .edge, "silent edge, \(appearance.rawValue)")
            let litStrip = try luma(declaring, .strip, "declared strip, \(appearance.rawValue)")
            let litEdge = try luma(declaring, .edge, "declared edge, \(appearance.rawValue)")

            XCTAssertEqual(plainStrip, plainEdge, accuracy: 1, """
                precondition, \(appearance.rawValue): the window's band is already drawn over a \
                page that declares nothing (strip \(plainStrip), edge \(plainEdge)), so the \
                readings below are not about the declaration at all — they would pass over a \
                band lit unconditionally, which is the same defect from the other side
                """)
            XCTAssertTrue(dark ? litStrip > plainStrip + 3 : litStrip < plainStrip - 3, """
                \(appearance.rawValue): the page said nothing scrolls under its band and the \
                window's band is unlit anyway (declared \(litStrip), silent \(plainStrip)). \
                This is the placement that ships — in the settings window the header is in the \
                toolbar — so the eight pages that declare it have a band nothing will ever \
                light: there is no scroll view under them to report a scroll and the pointer is \
                not always there
                """)
            XCTAssertTrue(dark ? litEdge > litStrip + 3 : litEdge < litStrip - 3, """
                \(appearance.rawValue): the window's band lit from the declaration and no rule \
                came with it (strip \(litStrip), edge \(litEdge)) — the always-on line Finder \
                draws is that rule, and half of the one appearance is missing
                """)
        }
    }

    /// **The withdrawal, which is the half a page change exercises and a
    /// string match cannot see at all.**
    ///
    /// Homebrew declares and General does not. A preference that reaches the
    /// backdrop but is never taken back leaves the band lit over a `Form` —
    /// the hairline this app measured away, restored on five pages by a page
    /// change nobody would connect to it.
    func testTheBandGoesOutWhenThePageChangesToOneThatDeclaresNothing() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let dark = appearance == .darkAqua
            let pane = pane(declaring: true, appearance: appearance)
            let lit = try luma(pane, .edge, "declared, \(appearance.rawValue)")
            let ground = try luma(pane, .strip, "declared strip, \(appearance.rawValue)")
            // The subject before the absence: a band that never lit goes out
            // for free, and the message below would name the wrong reading.
            XCTAssertTrue(dark ? lit > ground + 3 : lit < ground - 3, """
                precondition, \(appearance.rawValue): the band is not lit over a page that \
                declares (edge \(lit), strip \(ground)), so there is nothing here that could \
                go out and the withdrawal below is asserted over a band that was never on
                """)

            pane.pages.declaring = false
            pane.settle()
            let out = try luma(pane, .edge, "after the change, \(appearance.rawValue)")

            pane.pages.declaring = true
            pane.settle()
            let back = try luma(pane, .edge, "back again, \(appearance.rawValue)")

            XCTAssertTrue(dark ? out < lit - 3 : out > lit + 3, """
                \(appearance.rawValue): the page changed to one that declares nothing and the \
                window's band stayed lit (\(lit) before, \(out) after). The declaration reaches \
                the backdrop and is never withdrawn, so every page opened after a Homebrew or a \
                Log carries an always-on rule over its `Form`
                """)
            XCTAssertEqual(back, lit, accuracy: 2, """
                \(appearance.rawValue): coming back to a page that declares gives \(back) where \
                it first gave \(lit) — the band lights once and not again, so the reading above \
                was the preference arriving rather than the preference being read
                """)
        }
    }
}
