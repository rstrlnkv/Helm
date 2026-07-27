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

    static func describe(_ condition: RuleCondition) -> String {
        switch condition {
        case let .name(comparison, value):
            "\(ApStr.fieldName) \(describe(comparison)) “\(value)”"
        case let .fileExtension(list):
            "\(ApStr.fieldExtension) \(ApStr.comparisonIs) \(list.joined(separator: ", "))"
        case let .kind(kind):
            "\(ApStr.fieldKind) \(ApStr.comparisonIs) \(ApStr.kindName(kind))"
        case let .size(comparison, megabytes):
            "\(ApStr.fieldSize) \(comparison == .largerThan ? ApStr.comparisonLarger : ApStr.comparisonSmaller) \(format(megabytes)) \(ApStr.unitMegabytes)"
        case let .dateAdded(comparison, days):
            "\(ApStr.fieldDateAdded) \(describe(comparison)) \(ApStr.days(days))"
        case let .dateModified(comparison, days):
            "\(ApStr.fieldDateModified) \(describe(comparison)) \(ApStr.days(days))"
        case let .downloadedFrom(host):
            "\(ApStr.fieldSource) \(ApStr.comparisonContains) “\(host)”"
        case let .tag(tag):
            "\(ApStr.fieldTag) \(ApStr.comparisonIs) “\(tag)”"
        }
    }

    static func describe(_ action: RuleAction) -> String {
        switch action {
        case let .move(to: path):
            // Redacted like every other path Helm shows: a rule's destination
            // is usually inside the home directory, and the account name is
            // not part of what the rule says.
            "\(ApStr.actionMove): \(Redact.path(path))"
        case let .sortIntoSubfolder(scheme):
            "\(ApStr.actionSort) \(scheme == .kind ? ApStr.schemeKind : ApStr.schemeMonth)"
        case let .rename(pattern):
            "\(ApStr.actionRename): \(pattern)"
        case let .addTag(tag):
            "\(ApStr.actionTag): \(tag)"
        case .trash:
            ApStr.actionTrash
        }
    }

    private static func describe(_ comparison: TextComparison) -> String {
        switch comparison {
        case .is: ApStr.comparisonIs
        case .contains: ApStr.comparisonContains
        case .beginsWith: ApStr.comparisonBegins
        case .endsWith: ApStr.comparisonEnds
        }
    }

    private static func describe(_ comparison: DateComparison) -> String {
        comparison == .olderThan ? ApStr.comparisonOlder : ApStr.comparisonNewer
    }

    /// Whole numbers stay whole: "30 days", not "30.0 days".
    ///
    /// `Int(value)` traps on ±∞ and on anything past `Int.max`, and this string
    /// is drawn on the settings page — so a rule planted with `1e30` in a plist
    /// crashed the app every time the page opened, leaving no way to delete the
    /// rule that did it. `Int(exactly:)` asks instead of assuming.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if let whole = Int(exactly: value.rounded()), value == value.rounded() {
            return String(whole)
        }
        return String(format: "%.1f", value)
    }

    private static func format(_ value: Double) -> String { number(value) }
}
