import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The hourly sentinel, and the one thing it does that cannot be taken back.
///
/// Autopilot trashes files with nobody at the desk and the whole account of it
/// was a line in a log file, while the banner port was spent on the two modules
/// that touch no files at all. These drive the real legs — the timer's sweep and
/// the FSEvents batch — over a real folder, because the rule that decides is
/// tested next door and what is left to get wrong is *which trigger* speaks.
final class TheSweepTellsSomebodyWhatItBinnedTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!
    private var notices: FakeAutomationNotice!

    /// Rendered from the tally rather than from `L()`: the words are the UI
    /// target's and the point here is that the numbers reach them intact.
    private static func words(_ tally: SweepNews.Tally) -> NoticeText {
        NoticeText(title: "Autopilot",
                   body: "trashed \(tally.trashed) refused \(tally.refused) "
                       + "failed \(tally.failed)")
    }

    override func setUpWithError() throws {
        // A real folder inside a temporary home: `WatchScope` refuses anything
        // outside one, and a test exempted from that gate is a test of another
        // program.
        home = trashScratchDirectory("home")
        root = home.appendingPathComponent("helm-sweep-notice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func build(_ port: FakeAutomationNotice) {
        notices = port
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence(),
            sweepNotice: SweepNotifier(port: port, words: Self.words))
    }

    /// A file whose leaf nobody else could own, so the teardown that takes it
    /// back out of the Trash cannot take somebody else's.
    @discardableResult
    private func trashable(_ base: String) throws -> String {
        let leaf = unownableLeaf(base)
        reclaimFromTrash(leaf)
        try write(leaf, in: root, bytes: 8)
        return leaf
    }

    private func watch(_ action: RuleAction, on ext: String = "pdf") {
        let rule = Rule(id: "r", name: "r", enabled: true, match: .all,
                        conditions: [.fileExtension([ext])], action: action)
        engine.folders = [WatchedFolder(id: "f", path: root.path, enabled: true,
                                        rules: [rule], depth: 1)]
    }

    /// The banner is posted from a task of its own — nothing in the engine waits
    /// for macOS — so a read taken straight afterwards would pass an absence for
    /// free.
    private func waitForPosts(_ wanted: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while notices.posted.count < wanted, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // MARK: - The timer's sweep

    func testAnHourlySweepThatTrashedSomethingSaysSoOnce() async throws {
        build(FakeAutomationNotice(state: .authorized))
        try trashable("gone.pdf")
        watch(.trash)

        engine.sweepAll()
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.count, 1)
        XCTAssertEqual(notices.posted.first?.body, "trashed 1 refused 0 failed 0")
    }

    /// **A move it can undo and has recorded in History stays silent** — and the
    /// control beside it, so the silence is a decision rather than a notifier
    /// that has stopped working: the same engine, the same port, one pass that
    /// tidies and one that bins.
    func testAPassThatOnlyTidiedIsSilentAndTheOneAfterItStillSpeaks() async throws {
        build(FakeAutomationNotice(state: .authorized))
        try trashable("keep.pdf")
        let destination = home.appendingPathComponent("sorted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        watch(.move(to: destination.path))

        engine.sweepAll()
        await grace()
        XCTAssertEqual(notices.posted, [], "an hourly sweep that tidied became an hourly banner")
        XCTAssertEqual(notices.reads, 0, "macOS was asked about banners for a pass with no news")

        try trashable("gone.pdf")
        watch(.trash)
        engine.sweepAll()
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.count, 1,
                       "the control: with something binned the same path still speaks")
    }

    /// A sweep of a folder where no rule matched is the ordinary hour.
    func testASweepThatFoundNothingToDoIsSilent() async throws {
        build(FakeAutomationNotice(state: .authorized))
        try trashable("thing.txt")
        watch(.trash, on: "pdf")

        engine.sweepAll()
        await grace()
        XCTAssertEqual(notices.posted, [])
    }

    // MARK: - Run now

    /// **A person watching the page is not sent a banner about the page.** Run
    /// now is the one trigger with somebody in front of it, and the answer it
    /// owes them is on screen.
    func testRunNowBinsWithoutTellingAnybodyTwice() async throws {
        build(FakeAutomationNotice(state: .authorized))
        try trashable("gone.pdf")
        watch(.trash)

        let watched = try XCTUnwrap(engine.folders.first)
        _ = engine.runNow(watched)
        await grace()

        XCTAssertEqual(notices.posted, [],
                       "the person pressed the button and was sent a banner about the result")

        // The control: the same engine, the same folder, the timer's trigger.
        try trashable("also-gone.pdf")
        engine.sweepAll()
        await waitForPosts(1)
        XCTAssertEqual(notices.posted.count, 1)
    }

    // MARK: - The watcher's batch

    /// The other unattended leg. A file that arrives and is binned a moment
    /// later is the same loss to the person as one the hourly sweep takes, and
    /// one rule answers both.
    func testAFileBinnedByTheWatcherIsAnnouncedToo() async throws {
        build(FakeAutomationNotice(state: .authorized))
        let leaf = try trashable("arrived.pdf")
        watch(.trash)

        engine.handle([root.appendingPathComponent(leaf).path])
        await waitForPosts(1)

        XCTAssertEqual(notices.posted.first?.body, "trashed 1 refused 0 failed 0")
    }

    // MARK: - The permission

    /// **The prompt can stand on screen for minutes and the module may be
    /// switched off in that time.** The fake stalls where macOS stalls, so this
    /// is a test of the wait rather than of a subject that was over before it
    /// began.
    func testAModuleSwitchedOffWhileThePromptStandsPostsNothing() async throws {
        let gate = PromptGate()
        build(FakeAutomationNotice(state: .notDetermined, answersRequest: .authorized,
                                   whileAsking: { await gate.arrive() }))
        try trashable("gone.pdf")
        watch(.trash)

        engine.sweepAll()
        await gate.reached()
        XCTAssertEqual(notices.requests, 1, "precondition: the prompt was actually raised")

        engine.deactivate()
        await gate.open()
        await grace()

        XCTAssertEqual(notices.posted, [],
                       "a banner arrived from a module that had been switched off")
    }
}
