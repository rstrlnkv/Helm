import Foundation

/// Which rule set of the person's the plist holds, counted.
///
/// The seal says a rule set was written through Helm and says nothing about
/// *when*: an old `(payload, MAC)` pair verifies for ever, and the plist it
/// lives in is readable by anything running as this user and is in every
/// backup. So each save numbers the rule set inside the sealed message, and the
/// highest number this Mac has ever sealed is kept out of that file.
public enum RuleSequence: Equatable, Sendable {
    /// The highest number this Mac has sealed.
    case at(UInt64)
    /// This Mac has never sealed a numbered rule set — every installation until
    /// its first save under this build, which is why it is not a refusal.
    case absent
    /// The keychain would not answer. Distinct from `absent` on purpose: "never
    /// sealed one" is a fact and "cannot tell" is a refusal, and folding the two
    /// would make a locked keychain the way past the check.
    case unavailable
}

/// Where the mark is kept, as a port: the production answer is a keychain item
/// whose access list names only Helm, and a test must not write to the user's.
public protocol RuleSequencePort: Sendable {
    func highWater() -> RuleSequence
    /// Records a new mark. False when it could not be written — which costs a
    /// save nothing and leaves the rollback window one save wide.
    @discardableResult
    func raise(to seq: UInt64) -> Bool
}
