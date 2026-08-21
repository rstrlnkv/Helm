import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The permission, at the moment something wants it — one rule, for every
/// channel that has something to say with nobody at the desk.
///
/// It was written inside Keep Awake, where the battery veto is the only event
/// this app has that happens to an empty chair. Two more arrived at once — a
/// background scan's finding and Autopilot's hourly sweep — and a conversation
/// with macOS spelled three times is three chances to ask twice, or to trust a
/// permission that was revoked in System Settings an hour ago.
final class OneConversationWithMacOSAboutABannerTests: XCTestCase {

    private let words = NoticeText(title: "a module", body: "something happened")

    // MARK: - The rule alone

    /// Three cases and no `default`: a fourth authorization state has to be
    /// decided here rather than falling into whichever of these the compiler
    /// reaches first.
    func testNobodyHasBeenAskedYet() {
        XCTAssertEqual(NoticeChannel.step(given: .notDetermined), .ask)
    }

    func testAGrantedPermissionIsPostedThrough() {
        XCTAssertEqual(NoticeChannel.step(given: .authorized), .post)
    }

    func testARefusalIsNotAskedAgain() {
        XCTAssertEqual(NoticeChannel.step(given: .denied), .stayQuiet)
    }

    // MARK: - The conversation

    /// Somebody who has already granted it is not prompted a second time — macOS
    /// would not show the prompt anyway, and a channel that asks every time is a
    /// channel that reads the permission it was about to be told.
    func testAnAuthorizedChannelPostsWithoutPromptingAnybody() async {
        let port = FakeAutomationNotice(state: .authorized)
        let outcome = await NoticeChannel.tell(port, words)

        XCTAssertEqual(outcome, .posted)
        XCTAssertEqual(port.posted, [words])
        XCTAssertEqual(port.requests, 0, "a permission already granted was asked for again")
    }

    /// The one prompt macOS allows, spent at the first moment there is something
    /// to say rather than at launch.
    func testAnUnaskedChannelAsksOnceAndThenSpeaks() async {
        let port = FakeAutomationNotice(state: .notDetermined, answersRequest: .authorized)
        let outcome = await NoticeChannel.tell(port, words)

        XCTAssertEqual(outcome, .posted)
        XCTAssertEqual(port.requests, 1)
        XCTAssertEqual(port.posted, [words])
    }

    func testAPersonWhoSaidNoIsNotTold() async {
        let port = FakeAutomationNotice(state: .notDetermined, answersRequest: .denied)
        let outcome = await NoticeChannel.tell(port, words)

        XCTAssertEqual(outcome, .notAllowed)
        XCTAssertEqual(port.posted, [])
    }

    /// A standing refusal is read, not prompted: macOS answers it without
    /// showing anybody anything, so asking is neither useful nor harmless — it
    /// is the code believing it can undo a decision.
    func testAStandingRefusalIsNeverPromptedAgain() async {
        let port = FakeAutomationNotice(state: .denied)
        let outcome = await NoticeChannel.tell(port, words)

        XCTAssertEqual(outcome, .notAllowed)
        XCTAssertEqual(port.requests, 0)
        XCTAssertEqual(port.posted, [])
    }

    /// **The permission is read at every firing, never remembered.** It can be
    /// revoked in System Settings at any moment and nothing tells the app — the
    /// reverse channel this family of defects is named for.
    func testAPermissionRevokedBehindTheAppsBackIsNoticed() async {
        let port = FakeAutomationNotice(state: .authorized)
        let first = await NoticeChannel.tell(port, words)
        XCTAssertEqual(first, .posted, "precondition")

        port.state = .denied
        let second = await NoticeChannel.tell(port, words)
        XCTAssertEqual(second, .notAllowed)
        XCTAssertEqual(port.posted.count, 1, "a banner was posted after the grant was withdrawn")
    }

    /// **A banner that macOS took and threw away is not one somebody was
    /// shown.** The port swallows the error and logs it, so the two look
    /// identical from here; `attempts` is what says the channel really tried,
    /// which is what keeps this from passing on a channel that has gone silent
    /// altogether.
    func testAPostThatFailsIsNotAPostThatArrived() async {
        let port = FakeAutomationNotice(state: .authorized, postFails: true)
        _ = await NoticeChannel.tell(port, words)

        XCTAssertEqual(port.attempts, 1, "the channel never handed macOS anything")
        XCTAssertEqual(port.posted, [])
    }

    /// **A prompt can stand on screen for minutes, and the module may be
    /// switched off in that time.** The fake stalls where macOS stalls, so this
    /// is a test of the wait rather than of a subject that was over before it
    /// began.
    func testAChannelCancelledWhileThePromptStandsPostsNothing() async {
        let gate = PromptGate()
        let port = FakeAutomationNotice(
            state: .notDetermined, answersRequest: .authorized,
            whileAsking: { await gate.arrive() })
        let said = words
        let task = Task { await NoticeChannel.tell(port, said) }
        await gate.reached()
        XCTAssertEqual(port.requests, 1, "precondition: the prompt was actually raised")

        task.cancel()
        await gate.open()

        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(port.posted, [], "a banner arrived from a channel already cancelled")
    }
}
