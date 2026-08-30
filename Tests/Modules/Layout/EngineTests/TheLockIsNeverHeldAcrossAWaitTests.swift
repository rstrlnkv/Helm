import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// The engine's lock is taken on the key tap's own callback, which runs on
/// main. Anything it is held across, a keystroke waits behind.
///
/// **This was already written down, one line above where it was broken.**
/// `emitState` hoists `secure.isSecure()` out of the critical section under a
/// comment saying «a hung app there blocks for the messenger's timeout; holding
/// the lock across it would freeze the tap callback — which runs on main» — and
/// then called `ledger.totals(now:)` inside it. That is a `queue.sync` onto the
/// serial queue which also performs the file write, so a write in flight holds
/// it and the tap callback stalls behind an unbounded disk wait. `reloadSettings`
/// had the same shape: `appRules` hoisted for that reason, five more
/// `UserDefaults` reads — which can go out to `cfprefsd` — left inside.
///
/// **A source-shape check, because the behaviour is not reachable from a test.**
/// Making the reads block on demand means a fake store that sleeps and a fake
/// ledger queue that stalls, and then asserting on a timing window — a test
/// that fails on a busy machine and passes on a fast one. What is checkable is
/// the arrangement: a call out of the object between `lock.lock()` and
/// `lock.unlock()`. That is exactly how the defect looks, and it is how both of
/// these looked.
final class TheLockIsNeverHeldAcrossAWaitTests: XCTestCase {

    /// The ports and the two stores — everything whose duration this object does
    /// not decide. `HelmLog` writes a file; `emitState` reaches the transport
    /// and every subscriber on it; `DispatchQueue` and `await` are the shapes
    /// that hand the wait to somebody else entirely.
    private let reachOut = ["typing.", "sources.", "spell.", "secure.", "selection.",
                            "sound?.", "announcer.", "ledger.", "tap.", "settings.",
                            "HelmLog", "emitState(", "await ", "DispatchQueue"]

    func testNothingSlowRunsWhileTheTapIsWaitingForTheLock() throws {
        let path = "Sources/Modules/Layout/Engine/LayoutEngine.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertTrue(lines.contains { $0.contains("lock.lock()") },
                      "\(path) no longer takes this lock — the check has lost its subject")

        var depth = 0
        var held: [String] = []
        for (index, line) in lines.enumerated() {
            let opens = line.components(separatedBy: "lock.lock()").count - 1
            let closes = line.components(separatedBy: "lock.unlock()").count - 1
            // `lock.lock(); x = y; lock.unlock()` on one line is a critical
            // section that cannot span anything, whatever it names.
            let sameLine = opens > 0 && closes > 0
            if depth > 0 && !sameLine, let found = reachOut.first(where: line.contains) {
                held.append("\(index + 1): \(found.trimmingCharacters(in: .whitespaces)) — "
                            + line.trimmingCharacters(in: .whitespaces))
            }
            depth = max(0, depth + opens - closes)
        }

        XCTAssertEqual(held, [], """
            the engine holds its lock across \(held.count) call(s) it does not decide the \
            duration of. The tap callback takes this lock on main, so every one of these is a \
            keystroke waiting on a store, a port or a disk write:
            \(held.joined(separator: "\n"))
            """)
    }
}
