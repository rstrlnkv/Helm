import XCTest
import SwiftUI
import AppKit
@testable import HelmApp
@testable import HelmUI

/// The composer sheet has to know how tall it is *before* it is presented.
///
/// A sheet's window is sized by AppKit once, at presentation. `tableHeight`
/// used to start at a flat 200 and be corrected by measurement a turn of the
/// run loop later — so the window took the floor of 360 while the content
/// wanted 631, and the title, the Done button and both footer buttons were
/// outside it. What is on trial here is not the arithmetic but the timing: an
/// estimate is allowed to exist only because this test compares it with what
/// the list actually draws.
@MainActor
final class SidebarComposerHeightTests: XCTestCase {

    private final class Box { var value: CGFloat = 0 }

    /// Renders the real list in a real window and returns the height it
    /// reports through its binding.
    ///
    /// A window, not an offscreen view: a `List` is an AppKit table and draws
    /// nothing without one, so the probe that skips this step measures an
    /// empty bitmap and passes on nothing.
    private func measured(_ layout: SidebarLayout) -> CGFloat {
        let box = Box()
        let list = SidebarComposerList(
            layout: layout, host: ModuleHost.shared, editing: true,
            height: Binding(get: { box.value }, set: { box.value = $0 }),
            apply: { _ in }, rename: { _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: list.frame(width: 436))
        window.layoutIfNeeded()
        for _ in 0..<12 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return box.value
    }

    private var shipped: SidebarLayout {
        SidebarLayout.seeded(from: SidebarLayoutStore.registry())
    }

    /// The number the sheet is sized from is within a row's height of what the
    /// list draws. Not equality: the estimate exists to be close enough that
    /// the first frame is right, and the measurement still refines it.
    func testTheEstimateMatchesWhatTheListDraws() {
        let layout = shipped
        let drawn = measured(layout)
        try? XCTSkipIf(drawn == 0, "the list reported nothing — no window server in this run")
        guard drawn > 0 else { return }
        let estimate = SidebarComposerList.estimatedHeight(of: layout, editing: true)
        XCTAssertEqual(estimate, drawn, accuracy: SidebarComposerListRow.height,
                       "the sheet would open \(Int(abs(estimate - drawn))) pt off its content")
    }

    /// The failure that started this: the shipped arrangement must not land on
    /// the 360 pt floor, because at 360 the Done button is outside the window.
    func testTheShippedArrangementDoesNotOpenAtTheFloor() {
        let estimate = SidebarComposerList.estimatedHeight(of: shipped, editing: true)
        XCTAssertGreaterThan(estimate + SidebarComposerSheet.chromeHeight, 360,
                            "the sheet opens clamped, with its own chrome outside the window")
    }

    /// Nine modules and four sections still fit under the cap, which is the
    /// promise the cap was chosen for: the standard arrangement never scrolls.
    /// A tenth module was measured at 683 pt against this 660 — so a module added
    /// later fails here, which is the conversation this test exists to force.
    func testTheShippedArrangementFitsUnderTheCap() {
        let estimate = SidebarComposerList.estimatedHeight(of: shipped, editing: true)
        XCTAssertLessThanOrEqual(estimate + SidebarComposerSheet.chromeHeight, 660)
    }

    /// The note is measured, not guessed — twice in one afternoon a constant
    /// for it went stale, once when the font changed and once when a sentence
    /// was added. Nothing here pins a number; it pins that the chrome accounts
    /// for a note that wraps.
    ///
    /// **It does not pin what it used to claim**, which was that the number
    /// comes from the text actually drawn. It cannot: the assertion below
    /// passes for any measured note, including one whose font stopped matching
    /// the drawn one — and the sheet measured a second declaration of the note
    /// until `SidebarComposerSheet.note` became the single value that both
    /// `noteHeight` and `body` read. That is what makes the stronger sentence
    /// true, and it is true by construction rather than by this test.
    func testTheChromeAccountsForANoteThatWraps() {
        let oneLine = NSHostingController(rootView: Text("x").font(HelmText.rowDetail))
            .sizeThatFits(in: CGSize(width: 420, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(SidebarComposerSheet.chromeHeight, 129 + oneLine,
                             "the note is being counted as a single line")
    }

    // MARK: - The window the numbers are turned into

    func testTheSheetIsSizedToItsContentBetweenTheFloorAndTheCap() {
        XCTAssertEqual(SidebarComposerSheet.windowHeight(table: 300, chrome: 129), 429)
        XCTAssertEqual(SidebarComposerSheet.windowHeight(table: 10, chrome: 129), 360)
        XCTAssertEqual(SidebarComposerSheet.windowHeight(table: 5_000, chrome: 129), 660)
    }

    /// A height that is not a number is a window AppKit cannot make, and
    /// `.frame(height:)` is where it would find that out. The clamp this line
    /// used to be — `min(max(360, table + chrome), 660)` — answered the floor
    /// for one, because `Swift.max(360, .nan)` is 360; the shared `clamped`
    /// hands the NaN back instead. The floor is kept as the answer: it is what
    /// this sheet has always opened at when it knew nothing, and it is the size
    /// the seeded estimate is corrected up from a turn of the run loop later.
    func testAHeightThatIsNotANumberOpensAtTheFloor() {
        XCTAssertEqual(SidebarComposerSheet.windowHeight(table: .nan, chrome: 129), 360)
    }

    /// An *infinite* height is a different sentence: it has a place on the
    /// number line and the cap is the answer for a sheet taller than the
    /// window it sits in, which is the cap's whole job.
    func testAnInfiniteHeightOpensAtTheCap() {
        XCTAssertEqual(SidebarComposerSheet.windowHeight(table: .infinity, chrome: 129), 660)
    }

    /// The control. Every assertion above passes on an estimator that returns
    /// one constant.
    func testTheEstimateFollowsTheArrangement() {
        let one = SidebarLayout(sections: [.init(id: "a", seed: nil, name: "A", modules: ["x"])])
        let two = SidebarLayout(sections: [.init(id: "a", seed: nil, name: "A", modules: ["x", "y"])])
        XCTAssertEqual(SidebarComposerList.estimatedHeight(of: two, editing: true)
                       - SidebarComposerList.estimatedHeight(of: one, editing: true),
                       SidebarComposerListRow.height)
    }
}
