import Foundation
@testable import Module_Autopilot_Engine

/// A rule-set key that behaves like the keychain item does — created once,
/// present thereafter, and sometimes not available at all — without going near
/// the keychain.
///
/// Every engine a test builds takes one of these. The production port writes
/// `com.helm.autopilot` into the *user's* login keychain, and a suite that left
/// that behind would be a harness leaving something behind; worse, the second
/// run would find the first run's key and no longer be testing a first run.
final class TestRuleKey: RuleKeyPort, @unchecked Sendable {
    /// The key itself, so a test can ask the same questions of a file that the
    /// engine holding one of these will ask — whether a mark on it is Helm's.
    static let material = Data(repeating: 0x11, count: 32)
    private let material = TestRuleKey.material
    private let lock = NSLock()
    private var exists: Bool
    private let available: Bool
    private var asked = 0

    /// How many times the engine has gone to the keychain. The real port can sit
    /// behind a modal prompt, so *when* it is consulted is a property worth
    /// asserting on rather than a detail — see `AutopilotLaunchTests`.
    var reads: Int { lock.withLock { asked } }

    /// `established` is "this Mac has run a build that seals before" — the
    /// state every machine is in from the second launch onwards.
    init(established: Bool = false, available: Bool = true) {
        self.exists = established
        self.available = available
    }

    /// Locked, because the engine now resolves the key off the thread that
    /// asked for it and a test reads this counter from a third.
    func key() -> RuleKey? {
        lock.lock()
        defer { lock.unlock() }
        asked += 1
        guard available else { return nil }
        defer { exists = true }
        return RuleKey(material: material, firstUse: !exists)
    }
}

/// A key port that has been asked and has not answered.
///
/// This is what an ad-hoc build meets every time it is rebuilt: the binary's
/// designated requirement is its cdhash, so a rebuild is a different
/// application to the keychain, the item's access list no longer matches, and
/// `SecItemCopyMatching` sits inside a modal prompt until a person deals with
/// it. Measured on an installed build: 20.7 s and 31.1 s on two launches.
///
/// Nothing here answers on its own. The test decides when — and mostly never,
/// which is the case that matters. Beside `TestRuleKey` because two files ask
/// the same question of it now: what may run while the keychain has not
/// answered — the launch, and a watcher event.
final class StalledRuleKey: RuleKeyPort, @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let answered = DispatchSemaphore(value: 0)

    func key() -> RuleKey? {
        entered.signal()
        answered.wait()
        return nil
    }

    /// True once something is blocked inside `key()`.
    func waitUntilAsked() -> Bool { entered.wait(timeout: .now() + 5) == .success }

    /// Released in `tearDown` so no test leaves a thread parked forever.
    func release() { answered.signal() }
}
