import Foundation

/// Facts plus a rule, in, yes or no, out. No filesystem, no clock.
public enum RuleMatcher {

    public static func matches(_ facts: FileFacts, _ rule: Rule) -> Bool {
        // A rule with nothing in it matches nothing. The other reading — that
        // an empty `all` is vacuously true — would have a half-written rule act
        // on every file in the folder, which is the worst thing this module can
        // do. Logic loses to consequence here, and says so out loud.
        guard !rule.conditions.isEmpty else { return false }
        switch rule.match {
        case .all: return rule.conditions.allSatisfy { holds($0, facts) }
        case .any: return rule.conditions.contains { holds($0, facts) }
        }
    }

    static func holds(_ condition: RuleCondition, _ facts: FileFacts) -> Bool {
        switch condition {
        case let .name(comparison, value):
            return compare(facts.name, comparison, value)

        case let .fileExtension(list):
            let own = facts.fileExtension
            // A file with no extension matches no extension rule, rather than
            // every one of them.
            guard !own.isEmpty else { return false }
            return list.contains { $0.lowercased() == own }

        case let .kind(kind):
            return facts.kind == kind

        case let .size(comparison, megabytes):
            let limit = megabytes * 1_000_000
            return comparison == .largerThan ? Double(facts.bytes) > limit
                                             : Double(facts.bytes) < limit

        case let .dateAdded(comparison, days):
            return age(facts.added, facts.now, comparison, days)

        case let .dateModified(comparison, days):
            return age(facts.modified, facts.now, comparison, days)

        case let .downloadedFrom(needle):
            // A file that arrived by any other route has no source, and must
            // not quietly match.
            guard let source = facts.downloadedFrom else { return false }
            return source.localizedCaseInsensitiveContains(needle)

        case let .tag(name):
            return facts.tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private static func compare(_ subject: String, _ comparison: TextComparison,
                                _ value: String) -> Bool {
        // Case matters to a filesystem and not to a person writing a rule.
        let subject = subject.lowercased(), value = value.lowercased()
        switch comparison {
        case .is: return subject == value
        case .contains: return subject.contains(value)
        case .beginsWith: return subject.hasPrefix(value)
        case .endsWith: return subject.hasSuffix(value)
        }
    }

    /// "Older than 30 days" means 30, not 29.999: the boundary a person names
    /// is included on the older side.
    private static func age(_ date: Date, _ now: Date,
                            _ comparison: DateComparison, _ days: Double) -> Bool {
        let elapsed = now.timeIntervalSince(date) / 86_400
        return comparison == .olderThan ? elapsed >= days : elapsed < days
    }
}
