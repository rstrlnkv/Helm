/// **The raw value is the name in the published state**, so the engine and its
/// page name the same thing, and a renamed case is a build error rather than a
/// state that matches nothing.
///
/// Not the log's vocabulary: `ConditionLabel` spells `.externalDisplay` as
/// `display`, and deliberately — a log line is read by a person scanning for
/// the shape of a session. Two vocabularies are fine while each has one owner.
public enum ActiveCondition: String, Hashable, Sendable, CaseIterable {
    case manual, timer, externalDisplay, power, app

    /// The ones the machine decides rather than the person: a display arriving,
    /// the charger going in, an app the rules name. Both screens ask this —
    /// the panel tile to say a session is being held for you, the settings page
    /// to count them.
    public static let automatic: Set<ActiveCondition> = [.externalDisplay, .power, .app]
}

enum Conditions {
    struct Inputs: Equatable, Sendable {
        var manual = false
        var timerRunning = false
        var externalDisplay = false
        var onPower = false
        var appRunning = false
        var suppressed = false   // manual-off while an auto condition holds
    }
    struct Result: Equatable, Sendable {
        var isActive: Bool
        var conditions: Set<ActiveCondition>
        static let inactive = Result(isActive: false, conditions: [])
    }
    static func resolve(_ i: Inputs) -> Result {
        let held = i.manual || i.timerRunning
        if !held && i.suppressed { return .inactive }
        var c: Set<ActiveCondition> = []
        if i.manual { c.insert(.manual) }; if i.timerRunning { c.insert(.timer) }
        if i.externalDisplay { c.insert(.externalDisplay) }
        if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
        return Result(isActive: held || !c.isEmpty, conditions: c)
    }
}
