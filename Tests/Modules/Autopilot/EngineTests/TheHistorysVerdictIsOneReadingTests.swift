import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A backing store in which one read can be made to happen **later** than the
/// line above it, and in which a write can be waited for.
///
/// `HoldingStore` next door holds a read and answers it with the value the store
/// had when it *arrived*, which is what a decision taken on a stale snapshot
/// looks like. This is the other half of the same subject and it needs the
/// opposite: the value as it stands when the read finally runs, because what is
/// being modelled is a thread descheduled *between* two reads — the first
/// already taken, the second not yet — which is the only thing a scheduler ever
/// does to a pair of statements with no lock across them.
///
/// One shot, and no other read is delayed: everything else runs at full speed,
/// which is what lets a writer overtake the parked reader when nothing stops it.
private final class LateReadStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var lateKey: String?
    private var spent = false
    private var watchedKey: String?
    private let arrived = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let written = DispatchSemaphore(value: 0)

    /// The next read of `key` parks until `release()` and then reads the value as
    /// it stands at that moment.
    func delayTheNextRead(of key: String) {
        lock.withLock { lateKey = key; spent = false }
    }

    /// True once a reader is parked. Fails rather than waits for ever.
    @discardableResult
    func waitUntilParked() -> Bool { arrived.wait(timeout: .now() + 5) == .success }

    func release() { released.signal() }

    /// Watch writes of `key` from here on, so a test can say "the write landed"
    /// rather than sleep and hope. Registered before the writer starts.
    func watchWrites(of key: String) { lock.withLock { watchedKey = key } }

    /// Whether a watched write happened inside `seconds`. **Not an assertion of
    /// its own**: false is a legitimate answer — it means the write could not
    /// overtake the parked reader, which is the arrangement this file wants.
    func waitUntilWritten(seconds: TimeInterval) -> Bool {
        written.wait(timeout: .now() + seconds) == .success
    }

    func object(forKey key: String) -> Any? {
        let park: Bool = lock.withLock {
            guard key == lateKey, !spent else { return false }
            spent = true
            return true
        }
        if park {
            arrived.signal()
            released.wait()
        }
        // Read after the wait, deliberately: this read is happening now, not
        // when the caller's previous statement ran.
        return lock.withLock { values[key] }
    }

    func set(_ value: Any?, forKey key: String) {
        let watched: Bool = lock.withLock {
            values[key] = value
            return key == watchedKey
        }
        if watched { written.signal() }
    }
}

/// **Whose history this is, is two reads, and nothing holds them together.**
///
/// `AutopilotEngine.historyRefused` is
///
/// ```swift
/// !rules.historyIsHelms(queue.sync { store.data(ActionHistory.storeKey) })
/// ```
///
/// — the payload under the engine's queue, and then the seal over it read inside
/// `SealedRules.historyIsHelms`, on the caller's own thread, with the queue long
/// since let go. Between those two reads sits every write the module makes to
/// the same pair, and `AutopilotEngine.write(_:)` makes them in this order:
///
/// ```swift
/// guard let data = ActionHistory.encode(history), rules.seal(history: data) else { return false }
/// store.set(data, for: ActionHistory.storeKey)
/// ```
///
/// The seal first, then the history it signs — chosen so that a process dying
/// between them leaves a mismatched pair, which refuses. That is right for a
/// crash and it is exactly what makes the split read dangerous: a reader that
/// took the payload before the write and the seal after it holds **Helm's new
/// seal over Helm's old history**, which does not verify.
///
/// What that costs is not a wrong number on a screen. `historyRefused` is the
/// claim «the stored history was not written by Helm» — the module's forgery
/// signal — and it is answered inside `AutopilotCommand.status`, which the page
/// sends on every load, on the cooperative pool. The writer it races is the
/// FSEvents leg and the hourly sweep, both on the engine's own queue, both
/// unattended. What the page then draws is the card that says somebody rewrote
/// the record, with every return switched off, and it stays until the page is
/// loaded again. The rules were given `decisionLock` for exactly this
/// (`AutopilotSealRaceTests`); the history was not.
///
/// **Nothing here is timing-dependent.** The interleaving is arranged, not
/// raced: the reader is parked between its two reads, the writer is watched
/// until its write lands, and the reader is released afterwards. And the
/// arrangement failing to occur is not a pass — the assertion is on the verdict
/// either way, and the premises below say the write happened at all.
final class TheHistorysVerdictIsOneReadingTests: XCTestCase {

    private var home: URL!
    private var downloads: URL!
    private var backing: LateReadStore!
    private var namespace: String!

    override func setUpWithError() throws {
        home = scratchDirectory("history-verdict")
        downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        backing = LateReadStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        // A parked reader would otherwise hold a thread for the life of the
        // process; releasing twice is harmless and releasing never is not.
        backing.release()
    }

    private var sealKey: String { "module.\(namespace!).historyMAC" }
    private var payloadKey: String { "module.\(namespace!).history" }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    /// One folder, one rule that tags whatever it finds — an action that leaves
    /// the file where it is, so each pass's only effect on the world is the
    /// history record this test is about.
    private func watching() -> WatchedFolder {
        WatchedFolder(id: "downloads", path: downloads.path, enabled: true, rules: [
            Rule(id: "tag-them", name: "tag them", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .addTag("Seen")),
        ], depth: 1)
    }

    @discardableResult
    private func file(_ name: String) throws -> URL {
        let url = downloads.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    /// The defect. A history Helm wrote, read while Helm's own unattended leg is
    /// writing the next record into it, reports itself as somebody else's.
    func testAHistoryHelmIsWritingIsNotReportedAsSomebodyElses() throws {
        let helm = engine()
        helm.folders = [watching()]
        try file("first.pdf")
        _ = helm.sweepAll()

        // The premise, before anything is interleaved: this history is Helm's.
        XCTAssertFalse(helm.historyRefused, "the premise: a history Helm just wrote verifies")
        XCTAssertEqual(helm.history.count, 1, "the premise: there is a record to verify")

        // A reader parked between its two reads: the payload is already in its
        // hand, the seal is not.
        backing.delayTheNextRead(of: sealKey)
        let answered = expectation(description: "the verdict came back")
        let verdict = Box()
        DispatchQueue.global().async {
            verdict.refused = helm.historyRefused
            answered.fulfill()
        }
        XCTAssertTrue(backing.waitUntilParked(), "the premise: a reader is between its two reads")

        // …and the leg that writes history with nobody watching: a file
        // appeared, which the watcher hands to the engine's own queue. The same
        // path the hourly sweep takes, and the one the page is racing.
        let arrived = try file("second.pdf")
        backing.watchWrites(of: payloadKey)
        helm.handle([arrived.path])
        // False here is not a failure — it is the write being unable to overtake
        // the reader, which is the arrangement this test would like to be true.
        let overtookTheReader = backing.waitUntilWritten(seconds: 2)
        backing.release()
        wait(for: [answered], timeout: 5)
        XCTAssertTrue(overtookTheReader || backing.waitUntilWritten(seconds: 5), """
            the premise: the interleaved pass never wrote a history at all, so there was no \
            second seal for the parked reader to pick up and nothing here was tested
            """)

        // The premises for the accusation being an artefact and nothing else:
        // the write really happened, and the pair really does verify afterwards.
        XCTAssertEqual(helm.history.count, 2, "the premise: the interleaved pass recorded its work")
        XCTAssertFalse(helm.historyRefused,
                       "the premise: the pair the module ended up with does verify")

        XCTAssertEqual(verdict.refused, false, """
            a reader that took the history before Helm's own write and its seal after it was told \
            the record had been forged — the payload and the mac it is judged against are two \
            store reads with nothing holding them together
            """)
    }

    /// And the pair itself, so the finding above cannot be an accident of one
    /// ordering: two halves of Helm's own history that were never written
    /// together do not verify, whichever of them is the stale one.
    ///
    /// If they did, `historyRefused` would be blind to the interleaving and the
    /// test above would be about nothing.
    func testTheSealAndTheHistoryItSignsAreJudgedAsOnePair() throws {
        let helm = engine()
        helm.folders = [watching()]
        try file("first.pdf")
        _ = helm.sweepAll()

        let firstSeal = try XCTUnwrap(backing.object(forKey: sealKey) as? String,
                                      "the premise: a seal was written")
        let firstPayload = try XCTUnwrap(backing.object(forKey: payloadKey) as? Data)

        try file("second.pdf")
        _ = helm.sweepAll()
        let secondSeal = try XCTUnwrap(backing.object(forKey: sealKey) as? String)
        let secondPayload = try XCTUnwrap(backing.object(forKey: payloadKey) as? Data)

        XCTAssertNotEqual(firstPayload, secondPayload,
                          "the premise: the second pass changed the history")
        XCTAssertNotEqual(firstSeal, secondSeal, "the premise: and changed the seal with it")

        let key = RuleKey(material: TestRuleKey.material, firstUse: false)
        XCTAssertTrue(RuleSeal.historyIsHelms(payload: firstPayload, mac: firstSeal, key: key))
        XCTAssertTrue(RuleSeal.historyIsHelms(payload: secondPayload, mac: secondSeal, key: key))
        XCTAssertFalse(RuleSeal.historyIsHelms(payload: firstPayload, mac: secondSeal, key: key),
                       "an old history under a new seal verifies, so a split read is invisible")
        XCTAssertFalse(RuleSeal.historyIsHelms(payload: secondPayload, mac: firstSeal, key: key),
                       "a new history under an old seal verifies, so a split read is invisible")
    }

    private final class Box: @unchecked Sendable { var refused: Bool? }
}
