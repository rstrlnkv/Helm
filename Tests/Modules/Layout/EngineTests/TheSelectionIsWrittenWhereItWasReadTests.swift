import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The selection is written only into the app it was read from.
///
/// `RememberedWord` and `UndoRecord` carry a bundle id for the same reason: a
/// blind edit is only correct in the app it was measured in. The selection is
/// the same kind of edit against a stranger's text, so it is pinned with
/// `readIn`.
///
/// Both routes read the selection and then act on it: `convertSelection` runs
/// the app past `AppScope` and writes, and `fix()` reads on
/// `DispatchQueue.global`, because that read can block, then hops back to main.
/// Between the read and the write the frontmost app can change unseen by the
/// tap (a Space swipe, an app calling `activate()`, an alert, a call joining).
@MainActor
final class TheSelectionIsWrittenWhereItWasReadTests: XCTestCase {

    private var context = FakeSecure()
    private var selection = FakeSelection()

    private func engine() -> LayoutEngine {
        context = FakeSecure(); selection = FakeSelection()
        let engine = LayoutEngine(tap: FakeTap(), typing: FakeTyping(),
                                  sources: FakeSources(follows: false), translation: FakeTranslation(otherwise: { word, from, _ in
                                      from == "en" ? ["ghbdtn": "привет"][word] : nil }),
                                  spell: FakeSpell(valid: ["привет"]), secure: context, activation: FakeActivation(), selection: selection)
        engine.activate()
        return engine
    }

    /// One full turn of the main queue, so a block the gesture enqueued has
    /// certainly finished before an absence is asserted about it.
    private func drainMain() async {
        await withCheckedContinuation { resume in
            DispatchQueue.main.async { resume.resume() }
        }
    }

    // MARK: - The scope verdict is older than the write

    /// `AppScope` is asked about Notes; the write must not then land in a
    /// terminal, the app class the module blocks by default.
    func testAScopeVerdictIsNotSpentOnAnAppThatArrivedAfterIt() async throws {
        let engine = engine()
        selection.text = "ghbdtn"
        context.bundle = "com.apple.Terminal"

        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")

        XCTAssertGreaterThan(context.mainReads, 0,
                             "precondition: the app in front was never asked at the write")
        XCTAssertTrue(selection.replaced.isEmpty, """
            the module typed into a terminal. `AppScope` was asked about the app that was in \
            front before the read and never asked again, so its refusal was spent on an app \
            that had already gone.
            """)
        engine.deactivate()
    }

    /// The positive control for the test above: with nothing moving, the same
    /// selection *is* converted — so the refusal it asserts is the drift and not
    /// a harness that never reaches the write.
    func testASteadySelectionIsStillConverted() async throws {
        let engine = engine()
        selection.text = "ghbdtn"

        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")

        XCTAssertEqual(selection.replaced, ["привет"],
                       "the harness never converts a selection at all")
        engine.deactivate()
    }

    // MARK: - The text is older than the app it lands in

    /// The gesture's own hop: `fix()` reads the selection off the main queue
    /// because that read blocks, then comes back to main to act. Mail is not
    /// blocked, so no scope rule can stop a paragraph from Notes being typed
    /// over Mail's selection; only the pin can.
    func testTheTextTheGestureReadIsNotWrittenIntoADifferentApp() async {
        let engine = engine()
        selection.text = "ghbdtn"
        selection.whileReading = { [context] in context.bundle = "com.apple.Mail" }

        engine.fix()
        await waitUntil("the gesture came back to the main queue") { self.context.mainReads > 0 }
        await drainMain()

        XCTAssertEqual(selection.reads, 1, "precondition: the selection was never read")
        XCTAssertTrue(selection.replaced.isEmpty, """
            text read out of one application was typed into another. The read is on a \
            background queue and the write is a main-queue hop later; nothing carries the \
            app across, which is exactly what `RememberedWord` carries on the word path.
            """)
        engine.deactivate()
    }

    /// The positive control for the gesture path, including the wait: without
    /// it, an assertion that nothing was replaced would be green for a gesture
    /// that had not yet arrived.
    func testTheGestureStillConvertsASelectionThatStayedPut() async {
        let engine = engine()
        selection.text = "ghbdtn"

        engine.fix()
        await waitUntil("the gesture came back to the main queue") { self.context.mainReads > 0 }
        await drainMain()

        XCTAssertEqual(selection.replaced, ["привет"],
                       "the harness never reaches the write, so every absence it asserts "
                       + "elsewhere is vacuous")
        engine.deactivate()
    }
}
