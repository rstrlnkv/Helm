import Foundation

/// "Keep the Mac awake while this app runs" — optionally narrowed to the
/// situation the user actually cares about: at the desk (external display) or
/// plugged in. Both qualifiers on one rule mean both must hold.
public struct AppTrigger: Codable, Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public var bundleID: String
    public var needsExternalDisplay: Bool
    public var needsPower: Bool

    public init(bundleID: String, needsExternalDisplay: Bool = false, needsPower: Bool = false) {
        self.bundleID = bundleID
        self.needsExternalDisplay = needsExternalDisplay
        self.needsPower = needsPower
    }

    /// The four states the two flags can express, named the way the row reads.
    /// One control instead of two switches: "only with a display" and "only on
    /// power" together mean both must hold, which two independent toggles do
    /// not say out loud.
    public enum Condition: String, CaseIterable, Sendable {
        case always, externalDisplay, power, displayAndPower
    }

    public var condition: Condition {
        switch (needsExternalDisplay, needsPower) {
        case (false, false): .always
        case (true, false): .externalDisplay
        case (false, true): .power
        case (true, true): .displayAndPower
        }
    }

    public mutating func set(_ condition: Condition) {
        needsExternalDisplay = condition == .externalDisplay || condition == .displayAndPower
        needsPower = condition == .power || condition == .displayAndPower
    }

    func isSatisfied(running: Set<String>, externalDisplay: Bool, onPower: Bool) -> Bool {
        guard running.contains(bundleID) else { return false }
        if needsExternalDisplay && !externalDisplay { return false }
        if needsPower && !onPower { return false }
        return true
    }
}

public enum AppTriggerRules {
    public static func isHolding(_ rules: [AppTrigger], running: Set<String>,
                                 externalDisplay: Bool, onPower: Bool) -> Bool {
        !holding(rules, running: running, externalDisplay: externalDisplay,
                 onPower: onPower).isEmpty
    }

    /// **Which** rules are satisfied, not merely whether any is.
    ///
    /// The screen said «App» — the only rule type anybody actually uses, and
    /// the only one that could not say what it was talking about. A person with
    /// four apps in the list could not tell which of them was holding the Mac,
    /// on the screen whose whole job is to answer that.
    ///
    /// Bundle ids, not names: the ids are what the module stores and what it
    /// matched on, and turning one into a name is a Launch Services lookup that
    /// belongs on the screen doing the drawing. It keeps names off the wire and
    /// out of the log, which is the standing rule.
    public static func holding(_ rules: [AppTrigger], running: Set<String>,
                               externalDisplay: Bool, onPower: Bool) -> [String] {
        rules.filter { $0.isSatisfied(running: running, externalDisplay: externalDisplay,
                                      onPower: onPower) }
             .map(\.bundleID)
    }

    public static func encode(_ rules: [AppTrigger]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ raw: String) -> [AppTrigger] { readable(raw) ?? [] }

    /// `nil` for a string that is not rules, told apart from `[]` — which is a
    /// legitimate thing for the file to say and means the person has chosen no
    /// apps. The two are the same answer to the module and a different thing to
    /// say about somebody's file.
    public static func readable(_ raw: String) -> [AppTrigger]? {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([AppTrigger].self, from: data)
        else { return nil }
        return deduplicated(decoded)
    }

    /// One rule per app, first one wins.
    ///
    /// `AppTrigger` is `Identifiable` on its bundle id and the settings page
    /// draws `ForEach(id: \.element.bundleID)`, whose behaviour with a repeated
    /// id SwiftUI's own documentation leaves undefined — in the list that
    /// carries a per-row condition menu and a remove button keyed on the index.
    /// Two writers produce duplicates without anybody using the picker: a
    /// hand-edited plist, and `migrating(from:)` over an `autoApps` array that
    /// nothing ever deduplicated.
    private static func deduplicated(_ rules: [AppTrigger]) -> [AppTrigger] {
        var seen = Set<String>()
        return rules.filter { seen.insert($0.bundleID).inserted }
    }

    /// Earlier versions stored a plain list of bundle ids. Those apps kept the
    /// Mac awake unconditionally, so that is what they migrate to.
    public static func migrating(from bundleIDs: [String]) -> [AppTrigger] {
        deduplicated(bundleIDs.map { AppTrigger(bundleID: $0) })
    }
}
