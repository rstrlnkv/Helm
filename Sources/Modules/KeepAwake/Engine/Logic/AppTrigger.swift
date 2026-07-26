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
        rules.contains { $0.isSatisfied(running: running, externalDisplay: externalDisplay,
                                        onPower: onPower) }
    }

    public static func encode(_ rules: [AppTrigger]) -> String {
        guard let data = try? JSONEncoder().encode(rules) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ raw: String) -> [AppTrigger] {
        guard let data = raw.data(using: .utf8),
              let rules = try? JSONDecoder().decode([AppTrigger].self, from: data)
        else { return [] }
        return rules
    }

    /// Earlier versions stored a plain list of bundle ids. Those apps kept the
    /// Mac awake unconditionally, so that is what they migrate to.
    public static func migrating(from bundleIDs: [String]) -> [AppTrigger] {
        bundleIDs.map { AppTrigger(bundleID: $0) }
    }
}
