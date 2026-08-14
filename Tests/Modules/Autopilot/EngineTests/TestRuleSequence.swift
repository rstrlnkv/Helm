import Foundation
@testable import Module_Autopilot_Engine

/// The mark, behaving the way the keychain item does — absent until something
/// raises it, present thereafter, sometimes unreadable, and sometimes readable
/// but not writable.
///
/// The last two are the point. A double simpler than the port it stands for
/// cannot fail the way the port can: with a single `UInt64` in it, "the keychain
/// would not answer" and "the mark could not be raised" are states no test could
/// write down — and those are precisely the two the engine has to survive
/// without either running an old rule set or refusing to save a new one.
///
/// It stands for one item on one Mac, so a test that builds two engines hands
/// both the same instance.
final class TestRuleSequence: RuleSequencePort, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64?
    private let available: Bool
    private let writable: Bool
    private var raises = 0

    /// `at` is a Mac that has already sealed a numbered rule set.
    init(at: UInt64? = nil, available: Bool = true, writable: Bool = true) {
        self.value = at
        self.available = available
        self.writable = writable
    }

    /// What the keychain holds, for a test that wants to say the mark went up.
    var mark: UInt64? { lock.withLock { value } }
    var raiseCount: Int { lock.withLock { raises } }

    func highWater() -> RuleSequence {
        lock.lock()
        defer { lock.unlock() }
        guard available else { return .unavailable }
        return value.map(RuleSequence.at) ?? .absent
    }

    @discardableResult
    func raise(to seq: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard writable else { return false }
        value = seq
        raises += 1
        return true
    }
}
