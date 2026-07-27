import Foundation
import HelmRuntime
import HelmUI
import Module_Rules_Engine

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
            "\(RuStr.fieldName) \(describe(comparison)) “\(value)”"
        case let .fileExtension(list):
            "\(RuStr.fieldExtension) \(RuStr.comparisonIs) \(list.joined(separator: ", "))"
        case let .kind(kind):
            "\(RuStr.fieldKind) \(RuStr.comparisonIs) \(RuStr.kindName(kind))"
        case let .size(comparison, megabytes):
            "\(RuStr.fieldSize) \(comparison == .largerThan ? RuStr.comparisonLarger : RuStr.comparisonSmaller) \(format(megabytes)) \(RuStr.unitMegabytes)"
        case let .dateAdded(comparison, days):
            "\(RuStr.fieldDateAdded) \(describe(comparison)) \(format(days)) \(RuStr.unitDays)"
        case let .dateModified(comparison, days):
            "\(RuStr.fieldDateModified) \(describe(comparison)) \(format(days)) \(RuStr.unitDays)"
        case let .downloadedFrom(host):
            "\(RuStr.fieldSource) \(RuStr.comparisonContains) “\(host)”"
        case let .tag(tag):
            "\(RuStr.fieldTag) \(RuStr.comparisonIs) “\(tag)”"
        }
    }

    static func describe(_ action: RuleAction) -> String {
        switch action {
        case let .move(to: path):
            // Redacted like every other path Helm shows: a rule's destination
            // is usually inside the home directory, and the account name is
            // not part of what the rule says.
            "\(RuStr.actionMove): \(Redact.path(path))"
        case let .sortIntoSubfolder(scheme):
            "\(RuStr.actionSort) \(scheme == .kind ? RuStr.schemeKind : RuStr.schemeMonth)"
        case let .rename(pattern):
            "\(RuStr.actionRename): \(pattern)"
        case let .addTag(tag):
            "\(RuStr.actionTag): \(tag)"
        case .trash:
            RuStr.actionTrash
        }
    }

    private static func describe(_ comparison: TextComparison) -> String {
        switch comparison {
        case .is: RuStr.comparisonIs
        case .contains: RuStr.comparisonContains
        case .beginsWith: RuStr.comparisonBegins
        case .endsWith: RuStr.comparisonEnds
        }
    }

    private static func describe(_ comparison: DateComparison) -> String {
        comparison == .olderThan ? RuStr.comparisonOlder : RuStr.comparisonNewer
    }

    /// Whole numbers stay whole: "30 days", not "30.0 days".
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
