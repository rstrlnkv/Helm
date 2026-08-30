import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **«Helm never reads a password: a field the system marks as secure is
/// skipped whole.»** That is the page's own sentence (`LyStr.suspended`), and
/// the gesture reads the field first and refuses afterwards.
///
/// `fix()` opens with
///
/// ```
/// let readIn = secure.frontmostBundleID()
/// let selected = selection?.selectedTextWithoutClipboard()
/// ```
///
/// and asks nothing about the field. The refusal is two hops later, inside
/// `transform`, by which time the text has been pulled out of the accessibility
/// tree, carried across a queue hop and held as a `String`. `AXSelection`
/// applies no role check of its own — it copies `kAXSelectedTextAttribute` off
/// the focused element — while `AXSecureContext.isSecure()` reads
/// `kAXRoleAttribute` off *the same element* and answers `AXSecureTextField`.
/// The two questions are one round trip apart and asked in the wrong order.
///
/// What a person does: types their password into a login form the browser never
/// escalated for — so `IsSecureEventInputEnabled()` is false, which is the whole
/// reason the expensive role check exists — selects it, and taps the key they
/// bound, because tapping it is a reflex by then. What they get: the password
/// read out of the field and dropped a moment later. What they should get: the
/// question asked before the reading, which is free — both calls go to the same
/// accessibility element, and one of them is already being paid.
///
/// The same move settles a second thing. `transform` runs on main, and
/// `isSecure()` «reaches the accessibility server, and a hung app there blocks
/// for the messenger's timeout» — `emitState` carries that sentence and keeps
/// the call outside its lock for it. The gesture pays that round trip on the
/// main thread, which is the thread `fix()`'s background hop exists to keep
/// clear and the thread the tap callback runs on. Asking in the background
/// block removes both.
final class ASecureFieldIsAskedBeforeItIsReadTests: XCTestCase {

    /// Both halves apart, as the port keeps them: `isSecureInput` is the
    /// system-wide syscall and cannot see an app's own password field, which is
    /// the case this suite is about. `onExpensiveCheck` fires when the
    /// accessibility round trip is made, which is the one point in the gesture
    /// both the present order and the repaired one pass through — **once**,
    /// because `emitState` asks the same question and an expectation fulfilled
    /// twice is a failure of its own.
    private final class Context: SecureContextPort, @unchecked Sendable {
        private let lock = NSLock()
        var bundle = "com.apple.Safari"
        var systemWideSecure = false
        var passwordField = false
        var onExpensiveCheck: (@Sendable () -> Void)?
        func isSecureInput() -> Bool { lock.lock(); defer { lock.unlock() }; return systemWideSecure }
        func isSecure() -> Bool {
            lock.lock()
            let answer = systemWideSecure || passwordField
            let announce = onExpensiveCheck
            onExpensiveCheck = nil
            lock.unlock()
            announce?()
            return answer
        }
        func frontmostBundleID() -> String { lock.lock(); defer { lock.unlock() }; return bundle }
    }

    /// Counts the readings, and keeps the tree and the clipboard apart the way
    /// the port does: `selectedTextWithoutClipboard` is the tree alone, and
    /// `selectedText` falls through to ⌘C when the tree says nothing.
    private final class Selection: SelectionPort, @unchecked Sendable {
        private let lock = NSLock()
        var treeText: String?
        var clipboardText: String?
        private var treeReads = 0
        private var written: [String] = []
        var onReplace: (@Sendable () -> Void)?
        func selectedText() -> String? {
            lock.lock(); treeReads += 1; let tree = treeText, board = clipboardText
            lock.unlock()
            return tree ?? board
        }
        func selectedTextWithoutClipboard() -> String? {
            lock.lock(); treeReads += 1; let tree = treeText; lock.unlock()
            return tree
        }
        func replaceSelection(with text: String) -> Bool {
            lock.lock(); written.append(text); let announce = onReplace; onReplace = nil
            lock.unlock()
            announce?()
            return true
        }
        var readings: Int { lock.lock(); defer { lock.unlock() }; return treeReads }
        var replaced: [String] { lock.lock(); defer { lock.unlock() }; return written }
    }

    private struct Translation: TranslationPort {
        func translate(_ word: String, from: String, to: String) -> String? {
            word.isEmpty ? nil : String(repeating: "п", count: word.count)
        }
    }

    private struct Spell: SpellPort {
        func isWord(_ word: String, sourceID: String) -> Bool? {
            word.unicodeScalars.allSatisfy { $0.value > 0x400 }
        }
    }

    private func engine(_ context: Context, _ selection: Selection) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: Translation(), spell: Spell(),
            secure: context, selection: selection,
            ledger: LedgerStore(),
            settings: NamespacedStore(namespace: LayoutEngine.moduleID,
                                      backing: InMemoryKeyValueStore()))
        engine.activate()
        return engine
    }

    /// The control, and it runs first: with an ordinary field the gesture does
    /// read the selection and does replace it. Without this, «the tree was not
    /// read» would be green in a world where the gesture never reads anything.
    func testAnOrdinaryFieldIsReadAndReplaced() async {
        let context = Context()
        let selection = Selection()
        selection.treeText = "ghbdtn"
        let engine = engine(context, selection)

        // Synchronised on the write itself rather than on the check, so this
        // waits for the end of the path instead of for a point in the middle
        // of it.
        let acted = expectation(description: "the gesture replaced the selection")
        selection.onReplace = { acted.fulfill() }
        engine.fix()
        await fulfillment(of: [acted], timeout: 5)

        XCTAssertGreaterThan(selection.readings, 0,
                             "precondition: the gesture reads the selection at all")
        XCTAssertEqual(selection.replaced, ["пппппп"],
                       "precondition: and writes the conversion back")
        engine.deactivate()
    }

    /// The field is a password field by its accessibility role, and system-wide
    /// secure input is off — the case `isSecureInput()` cannot see, and the
    /// only reason the expensive check exists.
    func testASecureFieldIsNotReadBeforeItIsRefused() async {
        let context = Context()
        context.passwordField = true
        let selection = Selection()
        selection.treeText = "hunter2"
        let engine = engine(context, selection)

        // The expensive check is the one point both the present order and the
        // repaired one pass through, which makes it the synchronisation point:
        // when it has been asked, the gesture has decided.
        let asked = expectation(description: "the gesture asked whether it may act")
        context.onExpensiveCheck = { asked.fulfill() }
        engine.fix()
        await fulfillment(of: [asked], timeout: 5)

        XCTAssertEqual(selection.readings, 0, """
            the password was pulled out of the accessibility tree before anybody \
            asked whether the field was a password. The role check and the \
            selection read go to the same focused element one round trip apart, \
            so asking first is free — and the page promises a secure field is \
            «skipped whole», not read and then discarded.
            """)
        XCTAssertEqual(selection.replaced, [],
                       "and nothing was written back, which is the half that already worked")
        engine.deactivate()
    }
}
