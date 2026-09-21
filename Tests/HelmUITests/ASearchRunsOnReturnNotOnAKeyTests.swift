import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **Typing is not asking.**
///
/// `helmSearchable` hands a page two different things and they must stay
/// different: the binding, which moves on every keystroke because the results
/// on screen are filtered from it, and `onSubmit`, which is the press. The one
/// caller that passes an `onSubmit` sends two `brew search` runs over the
/// network per call — about nine seconds by this app's own measurement — so a
/// closure that ran per keystroke would put four of them out to spell «wget»,
/// and the fourth answer would land on top of the third.
///
/// The distinction survived the move from `HelmSearchField`, whose coordinator
/// had `controlTextDidChange` for one and a target/action for the other, to
/// SwiftUI's `.searchable`, which has a binding and `.onSubmit(of: .search)`.
/// That it survived is not something to take on trust: both halves are counted
/// here against the control AppKit actually built, in the window's toolbar.
///
/// **Return is a key event and nothing else.** Measured 2026-09-20 on the
/// bridged field: `target` and `action` are both nil, so `sendAction` fires
/// nothing; `insertNewline` on the field editor fires nothing either; a
/// `keyDown` carrying Return on that editor fires the submit exactly once.
/// `MountedRender.pressReturn` is that one route, spelled once.
@MainActor
final class ASearchRunsOnReturnNotOnAKeyTests: XCTestCase {

    /// The counters, on a class so the view can write to them without being
    /// rebuilt into a new copy of itself between keystrokes.
    private final class Tally: ObservableObject {
        @Published var text = ""
        /// Writes that actually changed the value. SwiftUI calls a binding's
        /// setter more than once per change, so counting calls would count the
        /// framework's bookkeeping rather than the keystrokes.
        var moves = 0
        var submits = 0
    }

    private struct Pane: View {
        @ObservedObject var tally: Tally
        var body: some View {
            Text("the list")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmSearchable(text: Binding(get: { tally.text },
                                              set: {
                                                  guard $0 != tally.text else { return }
                                                  tally.text = $0
                                                  tally.moves += 1
                                              }),
                                prompt: "Search packages",
                                onSubmit: { tally.submits += 1 })
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }

    func testFourKeystrokesMoveTheBindingAndAskNothing() throws {
        let tally = Tally()
        let mount = MountedRender(Pane(tally: tally), width: 1060, height: 400,
                                  appearance: .aqua)
        defer { mount.drop() }
        mount.settle(20)
        XCTAssertNotNil(mount.searchField, """
            nothing reached the window's toolbar, so neither count below is about a control — \
            `helmSearchable` stopped bridging
            """)

        for word in ["w", "wg", "wge", "wget"] {
            XCTAssertTrue(mount.type(word), "the field went away mid-word at «\(word)»")
        }
        XCTAssertEqual(tally.text, "wget", "the keystrokes did not reach the binding at all")
        XCTAssertEqual(tally.moves, 4, """
            four keystrokes moved the binding \(tally.moves) times — a list filtered from this \
            binding redraws on every letter, so anything but four is a page that lags behind \
            what is typed or redraws over nothing
            """)
        XCTAssertEqual(tally.submits, 0, """
            typing asked \(tally.submits) searches. Each one is two `brew search` runs over the \
            network, so a search per letter is four of them out at once for one word
            """)

        XCTAssertTrue(mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(tally.submits, 1, """
            Return fired `onSubmit` \(tally.submits) times where it is the one press that asks \
            — nothing at all means the network search can no longer be started
            """)
        XCTAssertEqual(tally.moves, 4, "Return moved the binding, which is the typing's job")
    }
}
