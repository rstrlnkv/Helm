import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **«Helm never reads a password: a field the system marks as secure is
/// skipped whole.»** That is the page's own sentence (`LyStr.deniedGuarantee`), and
/// the gesture read the field first and refused afterwards.
///
/// `fix()` opened with
///
/// ```
/// let readIn = secure.frontmostBundleID()
/// let selected = selection?.selectedTextWithoutClipboard()
/// ```
///
/// and asked nothing about the field. The refusal came two hops later, inside
/// `convertSelection`, by which time the text had been pulled out of the accessibility
/// tree, carried across a queue hop and held as a `String`. `AXSelection`
/// applies no role check of its own — it copies `kAXSelectedTextAttribute` off
/// the focused element — while `AXSecureContext.isSecure()` reads
/// `kAXRoleAttribute` off *the same element* and answers `AXSecureTextField`.
/// The two questions were one round trip apart and asked in the wrong order.
///
/// What a person does: types their password into a login form the browser never
/// escalated for — so `IsSecureEventInputEnabled()` is false, which is the whole
/// reason the expensive role check exists — selects it, and taps the key they
/// bound, because tapping it is a reflex by then. What they got: the password
/// read out of the field and dropped a moment later. What they get now: the
/// question asked before the reading: both calls go to the same
/// accessibility element.
///
/// The same move was meant to settle a second thing. `convertSelection` runs on
/// main, and `isSecure()` «reaches the accessibility server, and a hung app
/// there blocks for the messenger's timeout» — `emitState` carries that
/// sentence and keeps the call outside its lock for it. The gesture paid that
/// round trip on the main thread, which is the thread `fix()`'s background hop
/// exists to keep clear and the thread the tap callback runs on. Asking in the
/// background block put one ask off main; `convertSelection` still asks again
/// on main.
final class ASecureFieldIsAskedBeforeItIsReadTests: XCTestCase {

    private func engine(_ context: FakeSecure, _ selection: FakeSelection) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: FakeTap(), typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: FakeTranslation(sameLength: true), spell: FakeSpell(cyrillic: true),
            secure: context, activation: FakeActivation(), selection: selection,
            ledger: LedgerStore(),
            settings: layoutStore())
        engine.activate()
        return engine
    }

    /// The control, and it runs first: with an ordinary field the gesture does
    /// read the selection and does replace it. Without this, «the tree was not
    /// read» would be green in a world where the gesture never reads anything.
    func testAnOrdinaryFieldIsReadAndReplaced() async {
        let context = FakeSecure(bundle: "com.apple.Safari")
        let selection = FakeSelection()
        selection.text = "ghbdtn"
        let engine = engine(context, selection)

        // Synchronised on the write itself rather than on the check, so this
        // waits for the end of the path instead of for a point in the middle
        // of it.
        let acted = expectation(description: "the gesture replaced the selection")
        selection.onReplace = { acted.fulfill() }
        engine.fix()
        await fulfillment(of: [acted], timeout: 5)

        XCTAssertGreaterThan(selection.reads, 0,
                             "precondition: the gesture reads the selection at all")
        XCTAssertEqual(selection.replaced, ["пппппп"],
                       "precondition: and writes the conversion back")
        engine.deactivate()
    }

    /// The field is a password field by its accessibility role, and system-wide
    /// secure input is off — the case `isSecureInput()` cannot see, and the
    /// only reason the expensive check exists.
    func testASecureFieldIsNotReadBeforeItIsRefused() async {
        let context = FakeSecure(bundle: "com.apple.Safari")
        context.passwordField = true
        let selection = FakeSelection()
        selection.text = "hunter2"
        let engine = engine(context, selection)

        // The expensive check is the one point both the old order and the
        // repaired one pass through, which makes it the synchronisation point:
        // when it has been asked, the gesture has decided.
        let asked = expectation(description: "the gesture asked whether it may act")
        context.onExpensiveCheck = { asked.fulfill() }
        engine.fix()
        await fulfillment(of: [asked], timeout: 5)

        XCTAssertEqual(selection.reads, 0, """
            the password was pulled out of the accessibility tree before anybody \
            asked whether the field was a password. The role check and the \
            selection read go to the same focused element one round trip apart, \
            and the page promises a secure field is \
            «skipped whole», not read and then discarded.
            """)
        XCTAssertEqual(selection.replaced, [],
                       "and nothing was written back, which is the half that already worked")
        engine.deactivate()
    }
}
