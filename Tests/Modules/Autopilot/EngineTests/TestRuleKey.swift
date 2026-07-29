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
    private let material = Data(repeating: 0x11, count: 32)
    private var exists: Bool
    private let available: Bool

    /// `established` is "this Mac has run a build that seals before" — the
    /// state every machine is in from the second launch onwards.
    init(established: Bool = false, available: Bool = true) {
        self.exists = established
        self.available = available
    }

    func key() -> RuleKey? {
        guard available else { return nil }
        defer { exists = true }
        return RuleKey(material: material, firstUse: !exists)
    }
}
