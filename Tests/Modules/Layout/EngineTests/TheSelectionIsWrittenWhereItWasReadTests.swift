import Foundation
import HelmContract
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **The selection path reads from one app and writes into whichever app is in
/// front when the write happens, and nothing holds those two to being the
/// same.**
///
/// The word path was taught this lesson twice. `RememberedWord` carries the
/// bundle id the word was typed in and `UndoRecord` carries the one the
/// conversion happened in, both for the same stated reason: a blind edit is
/// only correct in the app it was measured in. The selection is the same kind
/// of edit against a stranger's text — `SelectionAction`'s own comment calls it
/// «text Helm never saw, in an app it did not choose» — and it carries no app at
/// all.
///
/// **The gap is not theoretical, it is what the code spends time in.** Both
/// doors read the selection and then act on the result:
///
/// - `transform` reads `frontmostBundleID()`, runs it past `AppScope`, and
///   *then* calls `selectedText()` — which falls through to ⌘C and polls the
///   pasteboard for up to 200 ms in every app whose accessibility tree will not
///   answer, which is most Electron apps and most web views. The scope verdict
///   is a fifth of a second old before anything is typed.
/// - `fix()` reads the selection on `DispatchQueue.global`, precisely because
///   that read can block, and then hops back to `DispatchQueue.main`. The text
///   crosses a queue boundary; the app it came from does not cross with it.
///
/// Between the read and the write the frontmost app can change, and the tap
/// cannot see it happen: a `.click` or a `.chord` would end a word, and neither
/// is involved in a Space swipe, an app calling `activate()`, an alert coming
/// forward, or a call joining. What lands is a paragraph converted out of one
/// application typed into a different one — and, in the first case below, into
/// a terminal that `AppScope` blocks by default, because the rule was applied to
/// an app that is no longer there.
///
/// The repair is the one the word path already has: pin the app the selection
/// was read from and refuse to write anywhere else.
@MainActor
final class TheSelectionIsWrittenWhereItWasReadTests: XCTestCase {

    /// The two halves of the secure check stay separate, as they are on the
    /// real port: `isSecureInput` is the cheap system-wide syscall, `isSecure`
    /// also recognises a password field by its accessibility role. Folding them
    /// into one flag makes «the field that took focus is a password field» a
    /// state no test in the file could write down.
    private final class DriftContext: SecureContextPort, @unchecked Sendable {
        private let lock = NSLock()
        private var storedBundle = "com.apple.Notes"
        private var storedMainReads = 0
        /// Written from the read's own thread and read from the one that types,
        /// which is the whole point of the suite — so it is locked rather than
        /// merely `@unchecked`.
        var bundle: String {
            get { lock.lock(); defer { lock.unlock() }; return storedBundle }
            set { lock.lock(); storedBundle = newValue; lock.unlock() }
        }
        /// How many times the engine has asked who is in front **from the main
        /// queue**.
        ///
        /// The thread is the whole point of the marker. `transform` asks this
        /// question and calls `replaceSelection` inside one main-queue block, and
        /// a `@MainActor` test polling with `Task.yield()` is itself a main-queue
        /// item — so it cannot observe the count move until that block has run to
        /// its end. Once this is above zero, the write has either happened or
        /// never will, and there is no window left for it to happen in.
        ///
        /// A repair that refuses on the background queue before the hop would
        /// never move this, and `waitUntil` says «never reached» rather than
        /// passing quietly. That is the right failure: it means the wait needs a
        /// new marker, not that the absence below was proved.
        var mainReads: Int { lock.lock(); defer { lock.unlock() }; return storedMainReads }
        var systemWideSecure = false
        var passwordField = false
        func isSecureInput() -> Bool { systemWideSecure }
        func isSecure() -> Bool { systemWideSecure || passwordField }
        func frontmostBundleID() -> String {
            let onMain = Thread.isMainThread
            lock.lock()
            if onMain { storedMainReads += 1 }
            let front = storedBundle
            lock.unlock()
            return front
        }
    }

    private final class DriftSelection: SelectionPort, @unchecked Sendable {
        private let lock = NSLock()
        private var storedText: String?
        private var storedReplaced: [String] = []
        private var storedReads = 0
        /// Run *inside* the read, which is where the real port spends its time:
        /// an accessibility round trip, or twenty 10 ms polls of the pasteboard
        /// waiting for ⌘C. Whatever the person does to their Mac in that window
        /// happens here.
        var whileReading: (@Sendable () -> Void)?

        var text: String? {
            get { lock.lock(); defer { lock.unlock() }; return storedText }
            set { lock.lock(); storedText = newValue; lock.unlock() }
        }
        var replaced: [String] { lock.lock(); defer { lock.unlock() }; return storedReplaced }
        var reads: Int { lock.lock(); defer { lock.unlock() }; return storedReads }

        private func read() -> String? {
            lock.lock(); storedReads += 1; let text = storedText; lock.unlock()
            whileReading?()
            return text
        }
        func selectedText() -> String? { read() }
        func selectedTextWithoutClipboard() -> String? { read() }
        func replaceSelection(with text: String) -> Bool {
            lock.lock(); storedReplaced.append(text); lock.unlock()
            return true
        }
    }

    private final class DriftTap: KeyTapPort, @unchecked Sendable {
        func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                   onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
                   died: @escaping @Sendable () -> Void) -> Bool { true }
        func stop() {}
    }

    private final class DriftTyping: TypingPort, @unchecked Sendable {
        func perform(_ plan: SwitchPlan) -> Bool { true }
    }

    private struct DriftSources: LayoutSourcePort {
        func installed() -> [String] { ["en", "ru"] }
        func current() -> String? { "en" }
        func select(_ sourceID: String) {}
    }

    private struct DriftTranslation: TranslationPort {
        func translate(_ word: String, from: String, to: String) -> String? {
            from == "en" ? ["ghbdtn": "привет"][word] : nil
        }
    }

    private struct DriftSpell: SpellPort {
        func isWord(_ word: String, sourceID: String) -> Bool? { word == "привет" }
    }

    private var context = DriftContext()
    private var selection = DriftSelection()

    private func engine() -> LayoutEngine {
        context = DriftContext(); selection = DriftSelection()
        let engine = LayoutEngine(tap: DriftTap(), typing: DriftTyping(),
                                  sources: DriftSources(), translation: DriftTranslation(),
                                  spell: DriftSpell(), secure: context, selection: selection)
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

    /// `transform` asks `AppScope` about Notes, spends up to 200 ms reading the
    /// selection, and replaces text in a terminal — the app class the module
    /// blocks by default, on the stated ground that `ghbdtn` there is as likely
    /// to be a filename as a mistake.
    func testAScopeVerdictIsNotSpentOnAnAppThatArrivedAfterIt() async throws {
        let engine = engine()
        selection.text = "ghbdtn"
        selection.whileReading = { [context] in context.bundle = "com.apple.Terminal" }

        engine.convertSelection()

        XCTAssertEqual(selection.reads, 1,
                       "precondition: the selection was never read, so nothing below is "
                       + "about what happened while it was being read")
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

        engine.convertSelection()

        XCTAssertEqual(selection.replaced, ["привет"],
                       "the harness never converts a selection at all")
        engine.deactivate()
    }

    // MARK: - The text is older than the app it lands in

    /// The gesture's own hop. `fix()` reads the selection off the main queue
    /// because that read blocks, then comes back to main to act — and the text
    /// it carries across is written into whoever holds the keyboard on arrival.
    /// Mail is not blocked, so no scope rule saves this one: it is a paragraph
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
