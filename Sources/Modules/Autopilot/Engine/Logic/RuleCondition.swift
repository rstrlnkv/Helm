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
    /// This brings a number into the range `JSONEncoder` will take. It does not
    /// decide whether the number is one anybody would mean — `accepts` does
    /// that, and `storable` drops what it cannot repair. The two were once
    /// claimed to be the same rule and were not: clamping a negative gives `0`,
    /// and "larger than 0 MB" is true of every file in the folder.
    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return upperBound }
        return min(max(value, lowerBound), upperBound)
    }

    /// What the editor's field will take. The comment above `clamp` says the
    /// two rules are the same, and they had already drifted: `clamp` admitted
    /// `0` and the field refused it, `clamp` admitted the upper bound and the
    /// field refused that too. Stated once here instead, so the sentence stays
    /// true. `0` is still refused at the keyboard — "larger than 0 MB" is a
    /// condition that matches every file, which is not a rule anybody means.
    static func accepts(_ value: Double) -> Bool {
        value.isFinite && value > lowerBound && value <= upperBound
    }

    static let lowerBound: Double = 0
    static let upperBound: Double = 1e9

    /// The same condition, or nothing when the number it carries is not one
    /// the editor would let anybody type.
    ///
    /// Clamping was the wrong repair and in the wrong direction. `clamp`
    /// brought a negative or a `0` up to `0`, which as "larger than 0 MB"
    /// matches **every file in the folder** — and a rule whose action is Trash
    /// then runs on all of them, on a timer, unattended. The failure mode of a
    /// corrupted number is "matches everything", so the safe repair is
    /// "matches nothing": the condition is dropped, and `RuleMatcher` already
    /// refuses a rule left with none, for this exact reason.
    ///
    /// Numbers are still brought into range where they are merely out of it —
    /// `JSONEncoder` refuses a non-finite `Double`, and the rules are one JSON
    /// value, so a single `1e999` used to discard every folder somebody had.
    var storable: RuleCondition? {
        func repaired(_ value: Double) -> Double? {
            // Non-finite first, and dropped rather than clamped. `clamp` sends
            // ±∞ and NaN to the *upper* bound, which reads as "larger than a
            // billion megabytes" — matches nothing, safe — and as "smaller than
            // a billion megabytes", which matches every file in the folder.
            // The same repair is safe under one comparison and catastrophic
            // under the other, so it is not a repair.
            guard value.isFinite else { return nil }
            let clamped = Self.clamp(value)
            return Self.accepts(clamped) ? clamped : nil
        }
        switch self {
        case let .size(comparison, megabytes):
            return repaired(megabytes).map { .size(comparison, megabytes: $0) }
        case let .dateAdded(comparison, days):
            return repaired(days).map { .dateAdded(comparison, days: $0) }
        case let .dateModified(comparison, days):
            return repaired(days).map { .dateModified(comparison, days: $0) }
        default:
            return self
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
            rule.conditions = rule.conditions.compactMap(\.storable)
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
