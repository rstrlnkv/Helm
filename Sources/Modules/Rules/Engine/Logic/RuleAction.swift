import Foundation

/// The one thing a rule does when it matches.
///
/// One, not a list. Two actions in a row is an order to get right and a failure
/// to report half-way through — "moved but could not rename" is a state with no
/// good screen. Rules stack instead, and each one either happened or did not.
///
/// Nothing here runs code. Hazel's script action is its most powerful, and it is
/// the one Helm cannot responsibly ship: the app is ad-hoc signed and
/// unsandboxed, and the rules live in a plist any process can write, so a script
/// action turns "a file appeared" into arbitrary execution.
public enum RuleAction: Codable, Equatable, Sendable {
    /// One destination, an absolute path.
    case move(to: String)
    /// Into a subfolder of the folder the file is already in.
    case sortIntoSubfolder(SortScheme)
    case rename(pattern: String)
    case addTag(String)
    /// Through `UserFileScope.partition`, inside the engine, like everywhere
    /// else in Helm.
    case trash
}

/// What the subfolder is named after.
public enum SortScheme: String, Codable, CaseIterable, Sendable {
    /// `Images`, `Documents`, `Archives`… — the file's kind.
    case kind
    /// `2026-07` — the month it was added.
    case month
}
