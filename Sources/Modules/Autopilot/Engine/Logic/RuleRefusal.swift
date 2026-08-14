import Foundation

/// Why none of the stored rules are running.
///
/// The two are not one state and must not be drawn as one sentence: a person
/// whose keychain is locked has rules that are almost certainly their own and a
/// wait in front of them, and a person whose plist was rewritten has neither.
/// Only one of them can be answered by throwing the rules away.
public enum RuleRefusal: String, Codable, Equatable, Sendable {
    /// The rules in the plist do not match their seal — something other than
    /// Helm wrote them.
    case tampered
    /// The key the seal is checked against could not be read, so whose rules
    /// these are is unknown. Refused in the safe direction: nothing runs.
    case noKey
}
