/// `CaseIterable` earns its keep in `ConditionLabelTests`, which walks every case
/// and fails when one is added without a word for the log — otherwise the reason
/// the module is holding sleep would be the one thing missing from the line that
/// exists to explain it.
///
/// **The raw value is the wire name**, so the two sides of the transport name
/// the same thing. It used to have none, and the spelling was written out three
/// times over: a `wireName` extension in the engine, a `switch` over string
/// literals in `KAStr` turning it back into a word, and two inline
/// `["externalDisplay", "power", "app"]` arrays in the views. A case renamed in
/// one of them is an error in none — the state simply arrives and matches
/// nothing, which on this page reads as a Mac that is awake for no reason.
///
/// Not the log's vocabulary: `ConditionLabel` spells `.externalDisplay` as
/// `display`, and deliberately — a log line is read by a person scanning for
/// the shape of a session, and it has its own test. Two vocabularies are fine
/// while each has one owner; three spellings of one of them was the defect.
public enum ActiveCondition: String, Hashable, Sendable, CaseIterable {
    case manual, timer, externalDisplay, power, app

    /// The ones the machine decides rather than the person: a display arriving,
    /// the charger going in, an app the rules name. Both screens ask this —
    /// the panel tile to say a session is being held for you, the settings page
    /// to count them — and both spelled the three out inline, so «which of
    /// these are automatic» was answered in two places and owned by neither.
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
        if i.manual || i.timerRunning {
            var c: Set<ActiveCondition> = []
            if i.manual { c.insert(.manual) }; if i.timerRunning { c.insert(.timer) }
            if i.externalDisplay { c.insert(.externalDisplay) }
            if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
            return Result(isActive: true, conditions: c)
        }
        if i.suppressed { return .inactive }
        var c: Set<ActiveCondition> = []
        if i.externalDisplay { c.insert(.externalDisplay) }
        if i.onPower { c.insert(.power) }; if i.appRunning { c.insert(.app) }
        return Result(isActive: !c.isEmpty, conditions: c)
    }
}
