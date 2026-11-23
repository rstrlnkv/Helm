import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **The selection path read from one app and wrote into whichever app was in
/// front when the write happened, and nothing held those two to being the
/// same.**
///
/// The word path was taught this lesson twice. `RememberedWord` carries the
/// bundle id the word was typed in and `UndoRecord` carries the one the
/// conversion happened in, both for the same stated reason: a blind edit is
/// only correct in the app it was measured in. The selection is the same kind
/// of edit against a stranger's text — `convertSelection`'s own comment calls
/// it «text Helm has never seen, in
/// an app it did not choose» — and it carried no app at all before `readIn`.
///
/// **The gap was not theoretical.** Both routes read the selection and then act
/// on the result:
///
/// - `convertSelection` was handed an app and a text, ran the app past
///   `AppScope`, and wrote to whichever app was in front at the write. The scope
///   verdict is as old as the read that preceded it.
/// - `fix()` read the selection on `DispatchQueue.global`, precisely because
///   that read can block, and then hopped back to `DispatchQueue.main`. The text
///   crossed a queue boundary; the app it came from did not cross with it.
///
/// Between the read and the write the frontmost app can change, and the tap
/// cannot see it happen: a `.click` or a `.chord` would end a word, and neither
/// is involved in a Space swipe, an app calling `activate()`, an alert coming
/// forward, or a call joining. What landed was a paragraph converted out of one
/// application typed into a different one — and, in the first case below, into
/// a terminal that `AppScope` blocks by default, because the rule was applied to
/// an app that was no longer there.
///
/// The repair is the one the word path already has: pin the app the selection
/// was read from and refuse to write anywhere else.
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

    /// `convertSelection` asked `AppScope` about Notes, took the selection it was
    /// given, and replaced text in a terminal — the app class the module
    /// blocks by default, on the stated ground that `ghbdtn` there is as likely
    /// to be a filename as a mistake.
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

    /// The gesture's own hop. `fix()` reads the selection off the main queue
    /// because that read blocks, then comes back to main to act — and the text
    /// it carried across was written into whoever held the keyboard on arrival.
    /// Mail is not blocked, so no scope rule saves this one: it was a paragraph
    /// from Notes typed over whatever was selected in Mail.
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
