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
