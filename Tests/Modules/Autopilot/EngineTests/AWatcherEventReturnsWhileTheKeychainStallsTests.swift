import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// The FSEvents leg must not make the watcher's own thread wait for the
/// keychain.
///
/// `FolderWatcher` delivers change callbacks on the same serial queue it hands
/// `watch` and `stop` to, and `AutopilotEngine.handle` is called synchronously
/// from that callback. Reading the rule set resolves the seal's key, and the
/// real port can sit inside a modal keychain prompt for as long as a person
/// ignores it — `AutopilotLaunchTests` has the measured launches. So a `handle`
/// that reads `folders` before dispatching parks the watcher for the whole
/// prompt: no folder can be watched or unwatched until it is answered, and the
/// engine's own rule — the rule set is read on the engine's queue — is broken on
/// the one leg that fires with nobody at the desk.
///
/// The blocking is a timing property, so the assertion is structural, the way
/// `AutopilotLaunchTests` asserts it: the call returns while the port has not
/// answered at all. A port that never answers cannot be beaten by a race — and
/// the test can lose, because moving the read back onto the caller's thread
/// leaves `returned` unfulfilled whatever the machine.
final class AWatcherEventReturnsWhileTheKeychainStallsTests: XCTestCase {

    private var home: URL!
    private var stalled: StalledRuleKey!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = scratchDirectory("watcher-stall")
        stalled = StalledRuleKey()
    }

    override func tearDownWithError() throws {
        stalled.release()
        try super.tearDownWithError()
    }

    func testAWatcherEventReturnsWhileTheKeyPortNeverAnswers() {
        let engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: stalled, sequence: TestRuleSequence())
        let returned = expectation(description: "handle returned")

        // The thread stands for the watcher's callback queue: whatever blocks
        // this call blocks every `watch` and `stop` behind it.
        let path = home.appendingPathComponent("Downloads/report.pdf").path
        DispatchQueue.global().async {
            engine.handle([path])
            returned.fulfill()
        }

        wait(for: [returned], timeout: 5)
        // The subject really happened: the work the event enqueued went on to
        // read the rule set. Without this, a `handle` that dropped the event
        // entirely would pass the wait above — an assertion about an absence
        // passes when the subject never happened at all.
        XCTAssertTrue(stalled.waitUntilAsked(),
                      "the event's work never read the rule set, so the return proved nothing")
    }
}
