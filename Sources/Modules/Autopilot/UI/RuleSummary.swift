import Foundation
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine

/// A rule as one line: what it looks for, and what it does.
///
/// The row in the list is the only place most rules are ever read, so the line
/// has to be the rule rather than a label for it. Everything here is the
/// module's own strings, so the sentence changes language with the app.
enum RuleSummary {

    static func describe(_ rule: Rule) -> String {
        let conditions = rule.conditions.map(describe)
        let joiner = rule.match == .all ? " · " : " / "
        let head = conditions.isEmpty ? "—" : conditions.joined(separator: joiner)
        return head + " → " + describe(rule.action)
    }

    /// One full key per shape, so each language orders the sentence its own way
    /// instead of receiving a field, a comparison and a value to string together.
    static func describe(_ condition: RuleCondition) -> String {
        switch condition {
        case let .name(comparison, value):
            switch comparison {
            case .is: L(.ruleNameIs(Quoted(value)))
            case .contains: L(.ruleNameContains(Quoted(value)))
            case .beginsWith: L(.ruleNameBegins(Quoted(value)))
            case .endsWith: L(.ruleNameEnds(Quoted(value)))
            }
        case let .baseName(comparison, value):
            switch comparison {
            case .is: L(.ruleBaseNameIs(Quoted(value)))
            case .contains: L(.ruleBaseNameContains(Quoted(value)))
            case .beginsWith: L(.ruleBaseNameBegins(Quoted(value)))
            case .endsWith: L(.ruleBaseNameEnds(Quoted(value)))
            }
        case let .fileExtension(list):
            L(.ruleExtensionIs(list.joined(separator: ", ")))
        case let .kind(kind):
            L(.ruleKindIs(ApStr.kindName(kind)))
        case let .size(comparison, megabytes):
            comparison == .largerThan ? L(.ruleSizeLarger(number(megabytes))) : L(.ruleSizeSmaller(number(megabytes)))
        case let .dateAdded(comparison, days):
            comparison == .olderThan ? L(.ruleDateAddedOlder(ApStr.days(days))) : L(.ruleDateAddedNewer(ApStr.days(days)))
        case let .dateModified(comparison, days):
            comparison == .olderThan ? L(.ruleDateModifiedOlder(ApStr.days(days))) : L(.ruleDateModifiedNewer(ApStr.days(days)))
        case let .downloadedFrom(host):
            L(.ruleSourceContains(Quoted(host)))
        case let .tag(tag):
            L(.ruleTagIs(Quoted(tag)))
        }
    }

    static func describe(_ action: RuleAction) -> String {
        switch action {
        case let .move(to: path):
            // Redacted like every other path Helm shows: a rule's destination
            // is usually inside the home directory, and the account name is
            // not part of what the rule says.
            L(.ruleActionMove(Redact.path(path)))
        case let .sortIntoSubfolder(scheme):
            scheme == .kind ? L(.ruleActionSortKind) : L(.ruleActionSortMonth)
        case let .rename(pattern):
            L(.ruleActionRename(pattern))
        case let .addTag(tag):
            L(.ruleActionTag(tag))
        case .trash:
            HelmWord.moveToTrash
        }
    }

    /// Whole numbers stay whole: "30 days", not "30.0 days".
    ///
    /// `Int(value)` traps on ±∞ and on anything past `Int.max`, and this string
    /// is drawn on the settings page: a rule with `1e30` in a plist would trap on
    /// every opening and leave no way to delete it.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if let whole = Int(exactly: value.rounded()), value == value.rounded() {
            return String(whole)
        }
        return Fractional(value)
    }
}
