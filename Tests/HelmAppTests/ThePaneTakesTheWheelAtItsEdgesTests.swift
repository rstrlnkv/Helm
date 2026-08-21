import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// The wheel reaches the page wherever the pointer is in the pane.
///
/// **The defect this is here for.** Four pages scroll by way of a SwiftUI
/// `Form` — the `Form` *is* the scroller — and `helmSettingsColumn()` was
/// applied to the `Form` itself, so the scroller was 744 pt wide and centred
/// inside an infinite outer frame. Everything either side of it belonged to
/// nothing, and the wheel over it reached no scroller: on the default 1060 pt
/// window the pane is 845, so 50 pt down each side of every one of those pages
/// was dead. A grouped `Form` already caps its own content at 704 pt and
/// centres it, measured identical to the point at 679, 845, 1149 and 1400 pt,
/// so the cap bought nothing and cost the sides.
///
/// # Why hit testing, and what makes it honest
///
/// **Scroll hit-testing is invisible in a still**, and a rendered frame of the
/// capped page and of the fixed one are the same picture. What decides it is
/// the AppKit tree: `NSWindow` delivers `scrollWheel` to the view `hitTest`
/// returns and then up the responder chain, so a point whose hit lands inside
/// the page's `NSScrollView` scrolls and one whose hit lands on the hosting
/// view does not.
///
/// That is a claim, so it was measured before it was relied on. A throwaway
/// probe put three arrangements — the bare `Form`, the capped one, and a third
/// that widened the scroller with `safeAreaPadding` — in a window ordered on
/// screen, and at each of four x positions compared `hitTest` against a real
/// `CGEvent` scroll wheel sent through `NSWindow.sendEvent`. **24 cells, all
/// 24 in agreement**: the page moved at exactly the points whose hit was
/// inside the scroller and at no other, and both outcomes appeared. The same
/// `hitTest` answers were then taken with the window never ordered in and came
/// back identical, which is what lets this run offscreen with nothing on the
/// owner's screen.
///
/// The probe also disposed of the obvious repair: `safeAreaPadding` gives the
/// `NSScrollView` the full width of the pane and the sides stay dead, because
/// SwiftUI hit-tests the content region and not the scroller's frame. That is
/// why the check below asks where the wheel lands and not how wide the
/// scroller is — a width assertion would have blessed it.
@MainActor
final class ThePaneTakesTheWheelAtItsEdgesTests: XCTestCase {

    /// The detail pane at the settings window's default size and at a wide one.
    ///
    /// 1060 wide with a 214 pt sidebar and the divider is 845; the window's own
    /// minimum, 860 with the sidebar at its 180 floor, is 679 — narrower than
    /// the 744 pt column, where the two arrangements cannot differ and the
    /// defect could not be seen. So both widths here are past the column, which
    /// is the only place the question exists.
    ///
    /// **Two of them, and the second is not a repetition.** A cap written as a
    /// constant — 744, or anything else — is invisible at every pane narrower
    /// than it, so one width can only catch a cap smaller than itself. The pair
    /// is what makes the check about capping rather than about 744.
    private static let panes: [CGFloat] = [845, 1149]

    /// The two pages that still have a dead band, and why they are named here
    /// rather than fixed.
    ///
    /// Both put `.padding(.horizontal, 12)` on the `List` that scrolls, which is
    /// the same defect as the `Form`'s and 12 pt wide instead of 50: measured at
    /// a 845 pt pane, x 4 and x 10 are dead and x 422 is live. Every repair that
    /// restores the wheel — dropping the padding, `contentMargins`,
    /// `listRowInsets` — also moves the row's content by some amount, and **the
    /// amount is not measurable here**: `cacheDisplay` does not composite a
    /// table-backed `List` at all (it returns the scroll view's background, read
    /// identical to the scroller's own frame in all four arrangements), the row
    /// backing view spans the clip view whatever the content does, and
    /// `screencapture` wants a Screen Recording grant that a measurement has no
    /// business asking for. Moving a visible gutter on an unmeasured guess is
    /// the trade this repository does not take.
    ///
    /// The list is **two-sided**, so it cannot go stale in silence: a page on it
    /// that starts reaching its edges fails too, saying to take it off.
    private static let knownDead: Set<String> = ["homebrew", "leftovers"]

    // MARK: - What the wheel reaches

    func testEveryModulePageTakesTheWheelAtBothEdgesOfThePane() {
        var scrollingPages: Set<String> = []
        for pane in Self.panes {
            for page in ModulePageRender.pages(in: .aqua, width: pane) {
                guard let scroller = page.host.everyView(ofType: NSScrollView.self).first
                else { continue }
                scrollingPages.insert(page.id)
                let inside = scroller.everyView
                let reaches = [CGFloat(4), pane - 4].allSatisfy { x in
                    let hit = page.host.hitTest(NSPoint(x: x, y: page.host.bounds.midY))
                    return inside.contains { $0 === hit }
                }
                if Self.knownDead.contains(page.id) {
                    XCTAssertFalse(reaches, """
                        The \(page.id) page now takes the wheel at both edges of a \
                        \(Int(pane)) pt pane. Take it out of `knownDead` — a recorded \
                        exception that has stopped being true is a check nobody reads.
                        """)
                    continue
                }
                XCTAssertTrue(reaches, """
                    The \(page.id) page's scroller does not reach both edges of a \
                    \(Int(pane)) pt pane: the wheel there is delivered to the hosting \
                    view and the page does not move. The scroller runs \
                    \(scroller.convert(scroller.bounds, to: nil)) — it must fill the \
                    pane, with the \
                    column kept by the content inside it.
                    """)
            }
        }
        // Not decoration: every assertion above sits behind a `guard`, so a
        // release in which no page had an `NSScrollView` in it any more would
        // report zero failures while checking nothing at all.
        XCTAssertGreaterThanOrEqual(scrollingPages.count, 4,
                                    "only \(scrollingPages.sorted()) had a scroller to ask about")
    }

    // MARK: - The shape in the source

    /// The measured check above cannot reach every page: `GeneralSettingsPage`
    /// is the shell's own and not a module's, and rendering it would run its
    /// `.task`, which warms a sealed setting out of the login keychain. So the
    /// shape is also read off the source, where every page is reachable and the
    /// General page's `Form` is one of the four this was written for.
    ///
    /// `.formStyle(` rather than `Form {`: the file is what is being read, and
    /// a form style is applied to nothing else, so finding it and
    /// `.helmSettingsColumn()` in one chain of modifiers is exactly the defect.
    /// A chain is a run of lines that are blank or begin with a dot, which is
    /// how this repository writes them; a new chain always opens with the
    /// expression it hangs off, and that line is neither.
    ///
    /// Read through `SwiftSource.code`, not off the raw file. This rule is
    /// explained in a comment on `helmSettingsColumn` that quotes the very
    /// thing it forbids, and a scan that read comments would report the
    /// explanation as the offence — the reason every source scan here goes
    /// through that reader, and the reason blank lines have to continue a
    /// chain, since a blanked comment is what a comment inside one becomes.
    func testNoModifierChainCapsTheFormThatScrolls() throws {
        var offenders: [String] = []
        var chainsSeen = 0
        for file in try SwiftSource.code(under: "Sources") {
            for chain in Self.modifierChains(in: file.text) {
                chainsSeen += 1
                guard chain.contains(".formStyle("),
                      chain.contains(".helmSettingsColumn()") else { continue }
                offenders.append((file.path as NSString).lastPathComponent)
            }
        }
        XCTAssertGreaterThan(chainsSeen, 100, "the chain reader found almost nothing to read")
        XCTAssertEqual(offenders, [], """
            \(offenders.joined(separator: ", ")): `helmSettingsColumn()` caps and \
            centres what it is applied to, and a grouped `Form` is the page's \
            scroll view — so this caps the scroller and leaves the pane either \
            side of it dead to the wheel. The column is the `Form`'s own already.
            """)
    }

    // MARK: - Reading the source

    /// Every maximal run of modifier lines in a file, one string each.
    private static func modifierChains(in source: String) -> [String] {
        var chains: [String] = []
        var current: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(".") {
                current.append(trimmed)
            } else if trimmed.isEmpty && !current.isEmpty {
                continue
            } else {
                if !current.isEmpty { chains.append(current.joined(separator: "\n")) }
                current = []
            }
        }
        if !current.isEmpty { chains.append(current.joined(separator: "\n")) }
        return chains
    }
}
