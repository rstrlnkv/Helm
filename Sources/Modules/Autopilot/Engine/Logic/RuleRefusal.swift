import Foundation

/// Why none of the stored rules are running.
///
/// The three are not one state and must not be drawn as one sentence: a person
/// whose keychain is locked has rules that are almost certainly their own and a
/// wait in front of them, and a person whose plist was rewritten has neither.
/// Only one of them can be answered by throwing the rules away.
public enum RuleRefusal: String, Equatable, Sendable {
    /// The rules in the plist do not match their seal — something other than
    /// Helm wrote them.
    case tampered
    /// The key the seal is checked against could not be read, so whose rules
    /// these are is unknown. Refused in the safe direction: nothing runs.
    case noKey
    /// The stored record is not a rule list this build can parse at all. Not
    /// `tampered`: the seal fits, so it is Helm's own or a newer Helm's. Its way
    /// out is Reset, or a newer Helm that reads the record; Discard is
    /// `tampered`'s alone, so nothing in this build deletes a record it cannot read.
    case unreadable
}
