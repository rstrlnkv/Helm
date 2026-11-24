import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The fixture both sweep-notice classes below stand on: a real folder in a
/// temporary home, an engine on a fresh store, and the notice port.
class SweepNoticeRig: XCTestCase {

    fileprivate var home: URL!
    fileprivate var root: URL!
    fileprivate var engine: AutopilotEngine!
    fileprivate var notices: FakeAutomationNotice!

    /// Rendered from the tally rather than from `L()`: the words are the UI
    /// target's and the point here is that the numbers reach them intact.
    fileprivate static func words(_ tally: SweepNews.Tally) -> NoticeText {
        NoticeText(title: "Autopilot",
                   body: "trashed \(tally.trashed) refused \(tally.refused) "
                       + "failed \(tally.failed)")
    }

    override func setUpWithError() throws {
        // A real folder inside a temporary home: `WatchScope` refuses anything
        // outside one.
        home = scratchDirectory("home")
        root = home.appendingPathComponent("helm-sweep-notice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    fileprivate func build(_ port: FakeAutomationNotice) {
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
    fileprivate func trashable(_ base: String) throws -> String {
        let leaf = unownableLeaf(base)
        reclaimFromTrash(leaf)
        try write(leaf, in: root, bytes: 8)
        return leaf
    }

    fileprivate func watch(_ action: RuleAction, on ext: String = "pdf") {
        let rule = Rule(id: "r", name: "r", enabled: true, match: .all,
                        conditions: [.fileExtension([ext])], action: action)
        engine.folders = [WatchedFolder(id: "f", path: root.path, enabled: true,
                                        rules: [rule], depth: 1)]
    }
}

/// The hourly sentinel, and the one thing it does that cannot be taken back.
///
/// Autopilot trashes files with nobody at the desk, so a sweep that binned
/// something says so beyond the log. This drives the real leg — the timer's
/// sweep — over a real folder: the rule that decides is tested next door, and
/// what is left to get wrong here is a prompt that outlives the module.
final class TheSweepTellsSomebodyWhatItBinnedTests: SweepNoticeRig {


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
