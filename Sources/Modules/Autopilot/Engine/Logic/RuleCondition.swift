import Foundation
import HelmRuntime

/// One thing a rule asks about a file.
///
/// An enum rather than a `field`/`comparison`/`value` triple, because the three
/// are not independent: "size begins with 4 MB" and "downloaded from larger
/// than" are states the triple can hold and this cannot. The editor builds the
/// same shapes the matcher reads.
public enum RuleCondition: Codable, Equatable, Sendable {
    case name(TextComparison, String)
    /// The name without its extension. A second condition rather than a changed
    /// `.name`, because a rule saying "name contains .pdf" works today and
    /// turning it into one that never fires is a break with no error and no
    /// message — an Autopilot that simply stops tidying.
    case baseName(TextComparison, String)
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

public extension RuleCondition {
    /// The extensions somebody typed into the editor's one field: "pdf, .PNG"
    /// is `["pdf", "png"]`.
    ///
    /// **In the engine because the parse is the rule.** The list's contract is
    /// two words on the case above — lowercase, no dots — and `RuleMatcher`
    /// compares it against an extension that never carries one, so a condition
    /// that keeps the dot a person typed is `isComplete`, may be switched on,
    /// and can never match a file. That is a rule which looks like it works,
    /// which is the one thing this module must not draw.
    ///
    /// **Here and not in `storable`.** Every launch reads the stored rules
    /// through `storable`, so stripping the dot there would change what a rule
    /// already on somebody's Mac does: a condition inert since the day it was
    /// written would begin moving or trashing files, unattended, because Helm
    /// was updated. A rule may come to match *less* on its own — that is what
    /// this module's repairs do — and it comes to match more only with somebody
    /// typing it.
    ///
    /// A dot on its own is not an extension and is dropped with the empties, so
    /// the field cannot produce the entry that would match every file.
    static func fileExtension(typed text: String) -> RuleCondition {
        .fileExtension(text.split(separator: ",").compactMap { entry in
            let trimmed = entry.trimmingCharacters(in: .whitespaces).lowercased()
            let named = String(trimmed.drop(while: { $0 == "." }))
            return named.isEmpty ? nil : named
        })
    }
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
    /// Non-finite takes the upper bound, and the choice is written here rather
    /// than inside the clamp: `clampedIfFinite` refuses ±∞ and NaN precisely
    /// because sending them to *a* bound is safe under one comparison and
    /// catastrophic under the other, which is the paragraph on `storable`.
    static func clamp(_ value: Double) -> Double {
        value.clampedIfFinite(to: lowerBound...upperBound) ?? upperBound
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

    /// Whether this condition names everything it needs to be asked of a file.
    ///
    /// `RuleAction.isComplete` from the other side. The blank states are the
    /// editor's own: a text comparison starts with an empty value, an extension
    /// list starts empty, and «name begins with ‹nothing›» is true of every
    /// file in the folder — with the action set to Trash, that is a working
    /// all-matcher three ordinary gestures from a blank rule. The safe reading
    /// of half-written is the matcher's for an empty rule: it must not run.
    ///
    /// Every case named, and no `default`, like `storable` above and for the
    /// same reason: a tenth condition must be a build error here, not a
    /// condition the switch silently calls finished.
    var isComplete: Bool {
        func named(_ value: String) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        switch self {
        case let .name(_, value), let .baseName(_, value),
             let .downloadedFrom(value), let .tag(value):
            return named(value)
        case let .fileExtension(list):
            return list.contains(where: named)
        // A kind is picked from a popup, and every position of the popup names
        // one — there is no half-written state to refuse.
        case .kind:
            return true
        // The numbers the editor's own field would take, which is the bound
        // `storable` already reads. Reachable only by hand-edited plist.
        case let .size(_, megabytes: value),
             let .dateAdded(_, days: value), let .dateModified(_, days: value):
            return Self.accepts(value)
        }
    }

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
        // **Every case named, and no `default`.** The three that carry a number
        // are repaired; the six that carry text or a kind have nothing to
        // repair and say so by name. A `default: return self` stood here, and
        // of all the places in this app to swallow an unhandled case this was
        // the worst one: a tenth condition carrying a `Double` would fall
        // through it unrepaired, and the paragraph three lines above records
        // what that costs — a single `1e999` makes `JSONEncoder` throw, the
        // rules are one JSON value, and the save takes *every folder* the
        // person has with it. Adding such a case is now a build error.
        switch self {
        case let .size(comparison, megabytes):
            return repaired(megabytes).map { .size(comparison, megabytes: $0) }
        case let .dateAdded(comparison, days):
            return repaired(days).map { .dateAdded(comparison, days: $0) }
        case let .dateModified(comparison, days):
            return repaired(days).map { .dateModified(comparison, days: $0) }
        case .name, .baseName, .fileExtension, .kind, .downloadedFrom, .tag:
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
            // Switched off rather than dropped, which is the difference between
            // a rule that reached storage in a state nobody could have typed
            // and a rule somebody has not finished writing. A move with no
            // destination refuses every file it matches, logging and writing a
            // history row on every sweep; the person keeps the rule and the
            // sweep is never offered it.
            if !rule.canBeEnabled { rule.enabled = false }
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

    /// Whether this rule could actually do something if it were switched on.
    ///
    /// A rule with no conditions matches nothing, a rule with a half-written
    /// one matches every file in the folder, and a rule whose action names
    /// nothing refuses everything; each way the switch would be switching on a
    /// rule that cannot work — and the middle one is the worst thing this
    /// module can do, one popup selection from the editor's blank state. All
    /// three halves live here rather than in the editor's `.disabled` so the
    /// screen and `storable` cannot answer differently.
    public var canBeEnabled: Bool {
        !conditions.isEmpty && conditions.allSatisfy(\.isComplete) && action.isComplete
    }
}
