import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A backing store that can hold one read inside the engine and let the world
/// move underneath it.
///
/// The held read is given the value the store had *when it arrived*, and only
/// then made to wait: that is what a decision taken on a stale snapshot is. No
/// other read is delayed, so a second one is free to overtake it — if the engine
/// lets it.
private final class HoldingStore: KeyValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [String: Any] = [:]
    private var heldKey: String?
    private var window: TimeInterval = 0
    private var holding = false
    private var spent = false
    private var overlapped = false
    private var others = 0
    private let arrived = DispatchSemaphore(value: 0)

    /// Hold the next read of `key` for `window` seconds. One shot: the reads
    /// that follow run at full speed, which is what makes the older decision
    /// the slower one.
    func holdTheNextRead(of key: String, for window: TimeInterval) {
        lock.withLock {
            heldKey = key
            self.window = window
        }
    }

    /// True once a read is being held. Fails rather than waits forever.
    func waitUntilHolding() -> Bool { arrived.wait(timeout: .now() + 5) == .success }

    /// Whether another read of the same key began while one was still held.
    var somethingReadWhileOneWasHeld: Bool { lock.withLock { overlapped } }

    /// Reads of that key other than the held one — the premise of the test
    /// above it, since "nothing overlapped" is also true of nothing happening.
    var otherReads: Int { lock.withLock { others } }

    func object(forKey key: String) -> Any? {
        let value = lock.withLock { raw[key] }
        let hold: TimeInterval? = lock.withLock {
            guard key == heldKey else { return nil }
            guard !spent else {
                others += 1
                if holding { overlapped = true }
                return nil
            }
            spent = true
            holding = true
            return window
        }
        if let hold {
            arrived.signal()
            Thread.sleep(forTimeInterval: hold)
            lock.withLock { holding = false }
        }
        return value
    }

    func set(_ value: Any?, forKey key: String) { lock.withLock { raw[key] = value } }
}

/// Two threads asking the engine whose rules these are.
///
/// The rule set is read from the sweep timer, from FSEvents, from the transport
/// and from the watch refresh — four callers, none of them serialised with the
/// others. Each read decides whether the stored rules are Helm's own and records
/// that decision in `rulesRefused`, which is the only signal a person has that
/// something else wrote their rules. So the reads have to be ordered against
/// each other: a decision taken about the file as it was is not allowed to be
/// the last word about the file as it is.
final class AutopilotSealRaceTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: HoldingStore!
    private var namespace: String!

    /// Long enough that a read which is *not* held cannot be mistaken for one
    /// that is: the whole decision is a dictionary lookup and an HMAC over a few
    /// hundred bytes. Nothing is asserted about how long anything took — the
    /// window only decides which decision is the slow one.
    private let window: TimeInterval = 0.25

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = HoldingStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
    }

    private func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private var payloadKey: String { "module.\(namespace!).folders" }

    /// A barrier on the engine's queue: `clearHistory` is `queue.sync` and the
    /// queue is serial, so the watch refresh the setter dispatched has finished.
    /// Without it the read this test holds might be that one.
    private func settle(_ engine: AutopilotEngine) { engine.clearHistory() }

    private func emptyingRules() -> [WatchedFolder] {
        [WatchedFolder(id: "planted", path: root.path, enabled: true, rules: [
            Rule(id: "r", name: "take it", enabled: true, match: .all,
                 conditions: [.fileExtension(["pdf"])], action: .trash),
        ], depth: 1)]
    }

    /// Sets up an engine with one sealed, harmless rule set saved through Helm,
    /// and a read of it held mid-decision.
    private func engineWithAHeldRead() throws -> AutopilotEngine {
        let helm = engine()
        helm.folders = [WatchedFolder(id: "kept", path: root.path, enabled: true,
                                      rules: [], depth: 1)]
        settle(helm)
        backing.holdTheNextRead(of: payloadKey, for: window)
        return helm
    }

    // MARK: - The verdict

    /// The defect. A read that began before the plist was edited finishes after
    /// the read that saw the edit, and its verdict — "these are Helm's own
    /// rules", true of the file it read and of nothing since — lands last.
    ///
    /// `rulesRefused` is what tells a person their rules were tampered with, so
    /// the last write winning by accident is not a test problem.
    func testAReadThatBeganBeforeTheEditDoesNotGetTheLastWord() throws {
        let helm = try engineWithAHeldRead()
        let earlier = expectation(description: "the earlier read finished")
        DispatchQueue.global().async {
            _ = helm.folders
            earlier.fulfill()
        }
        XCTAssertTrue(backing.waitUntilHolding(), "the premise: a read is in flight")

        backing.set(try JSONEncoder().encode(emptyingRules()), forKey: payloadKey)
        _ = helm.folders

        wait(for: [earlier], timeout: 5)
        XCTAssertTrue(helm.rulesRefused,
                      "a verdict about the rules as they were overwrote the verdict about the edit")
    }

    // MARK: - Why it holds

    /// And the property that makes the above true rather than lucky: the engine
    /// decides about the stored rules one decision at a time. A second read
    /// cannot begin while another is still deciding, so the recorded verdict is
    /// always the one taken over the file as it stands.
    ///
    /// Asserted on the store's own reads rather than on how long anything took.
    func testTwoDecisionsAboutTheStoredRulesDoNotOverlap() throws {
        let helm = try engineWithAHeldRead()
        let earlier = expectation(description: "the earlier read finished")
        DispatchQueue.global().async {
            _ = helm.folders
            earlier.fulfill()
        }
        XCTAssertTrue(backing.waitUntilHolding(), "the premise: a read is in flight")

        _ = helm.folders

        wait(for: [earlier], timeout: 5)
        XCTAssertEqual(backing.otherReads, 1, "the premise: there was a second read")
        XCTAssertFalse(backing.somethingReadWhileOneWasHeld,
                       "a second read of the rules began while one was still deciding")
    }
}
