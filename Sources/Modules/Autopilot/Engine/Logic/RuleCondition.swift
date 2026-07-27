import Foundation

/// One thing a rule asks about a file.
///
/// An enum rather than a `field`/`comparison`/`value` triple, because the three
/// are not independent: "size begins with 4 MB" and "downloaded from larger
/// than" are states the triple can hold and this cannot. The editor builds the
/// same shapes the matcher reads.
public enum RuleCondition: Codable, Equatable, Sendable {
    case name(TextComparison, String)
    /// Lowercase, no dots. A file matches if its own extension is in the list.
    case fileExtension([String])
    case kind(FileKind)
    case size(SizeComparison, megabytes: Double)
    case dateAdded(DateComparison, days: Double)
    case dateModified(DateComparison, days: Double)
    /// Substring of `kMDItemWhereFroms`, usually a host.
    case downloadedFrom(String)
    case tag(String)
}

public enum TextComparison: String, Codable, CaseIterable, Sendable {
    case `is`, contains, beginsWith, endsWith
}

public enum SizeComparison: String, Codable, CaseIterable, Sendable {
    case largerThan, smallerThan
}

public enum DateComparison: String, Codable, CaseIterable, Sendable {
    case olderThan, newerThan
}

/// Whether every condition has to hold, or one of them.
///
/// Hazel's answer to what these two cannot express is a nested group; that is
/// also where a rule stops being readable at a glance, and it is not here.
public enum RuleMatch: String, Codable, CaseIterable, Sendable {
    case all, any
}

public extension RuleCondition {
    /// A number this condition can be stored with.
    ///
    /// `JSONEncoder` refuses a non-finite `Double`, and the rules are one JSON
    /// value: a single `1e999` in one condition of one rule made saving throw,
    /// which took *every folder* with it. The number is clamped rather than the
    /// save abandoned — losing somebody's other folders to a typo in this one
    /// is a far worse answer than storing a bound they will see on the screen.
    ///
    /// The bounds are the same ones the editor's field enforces, so a value
    /// arriving from a hand-edited plist ends up where a typed one would.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return upperBound }
        return min(max(value, lowerBound), upperBound)
    }

    static let lowerBound: Double = 0
    static let upperBound: Double = 1e9

    /// The same condition with any number it carries brought into range.
    var storable: RuleCondition {
        switch self {
        case let .size(comparison, megabytes):
            .size(comparison, megabytes: Self.clamp(megabytes))
        case let .dateAdded(comparison, days):
            .dateAdded(comparison, days: Self.clamp(days))
        case let .dateModified(comparison, days):
            .dateModified(comparison, days: Self.clamp(days))
        default:
            self
        }
    }
}

public extension WatchedFolder {
    /// The folder with every rule's numbers brought into range. Applied on the
    /// way into storage, so nothing unencodable can reach the one JSON value
    /// that holds all of them.
    var storable: WatchedFolder {
        var copy = self
        copy.rules = rules.map { rule in
            var rule = rule
            rule.conditions = rule.conditions.map(\.storable)
            return rule
        }
        return copy
    }
}

public struct Rule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var enabled: Bool
    public var match: RuleMatch
    public var conditions: [RuleCondition]
    public var action: RuleAction

    public init(id: String = UUID().uuidString, name: String, enabled: Bool = false,
                match: RuleMatch = .all, conditions: [RuleCondition] = [],
                action: RuleAction) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.match = match
        self.conditions = conditions
        self.action = action
    }
}
