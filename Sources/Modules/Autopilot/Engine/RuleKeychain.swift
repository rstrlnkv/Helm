import Foundation
import HelmRuntime

/// The rule-set key, in Helm's own login keychain.
///
/// The mechanism is `KeychainSealKey` (HelmRuntime) since the background scans
/// grew a seal of their own — the `SecItemAdd` dance, the "created once, never
/// rewritten" rule and the treatment of an unreadable keychain are all one
/// implementation now, and the note that used to sit here wishing for exactly
/// that is spent.
///
/// **The service and account stay exactly what they were.** This item exists on
/// every Mac that has ever run Autopilot, and moving it would read to all of
/// them as "somebody rewrote your rules" — a refusal to run the person's own
/// configuration, in the signal that exists to warn them about forgery.
public final class KeychainRuleKey: RuleKeyPort {
    private let keychain = KeychainSealKey(service: "com.helm.autopilot",
                                            account: "rule-seal",
                                            category: "autopilot")

    public init() {}

    public func key() -> RuleKey? { keychain.key() }
}
