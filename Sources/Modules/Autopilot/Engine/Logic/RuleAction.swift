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

/// Whether a text field of a rule says anything: not empty and not only
/// whitespace. `RuleAction.isComplete` and `RuleCondition.isComplete` both ask
/// it, because a field the person has cleared or left blank must read as
/// unfinished the same way in an action and in a condition.
func isNamed(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

extension RuleAction {
    /// Whether the action names everything it needs to be carried out.
    ///
    /// The blank states are reachable by design rather than by accident: the
    /// editor starts a move with an empty destination because the destination
    /// only ever arrives through the panel, and a pattern or a tag is a field
    /// somebody can clear.
    ///
    /// Reaching the runner, an incomplete action would refuse every matching
    /// file, with a log line and a history row on every sweep for a rule the
    /// person believes is working. So `storable` switches such a rule off and
    /// the sweep is never offered it.
    var isComplete: Bool {
        switch self {
        case let .move(to: destination): return isNamed(destination)
        case let .rename(pattern): return isNamed(pattern)
        case let .addTag(tag): return isNamed(tag)
        // Neither has anything left to fill in.
        case .sortIntoSubfolder, .trash: return true
        }
    }
}

/// What the subfolder is named after.
public enum SortScheme: String, Codable, CaseIterable, Sendable {
    /// `Images`, `Documents`, `Archives`… — the file's kind.
    case kind
    /// `2026-07` — the month it was added.
    case month
}
