import Foundation
import HelmRuntime

/// "30 days" where it follows a comparison.
///
/// `Plural.days` counts, and counting is the nominative: «30 дней», «2 дня».
/// Both places a rule is read put the unit straight after «старше» or «новее»,
/// and those govern the genitive — so the row and the summary said «старше 1
/// день» and «старше 2 дня», the second of which is not the same word the
/// count would use. Genitive singular after one, genitive plural after
/// everything else, including 2–4 where the nominative takes the paucal.
///
/// Here rather than beside `Plural` in `HelmRuntime` because this is not a
/// count: it is a count in a particular grammatical position, and only this
/// module puts a number there. Language is a parameter, not a global read, so
/// the agreement can be asserted without asserting what machine ran the test.
public enum DayUnit {

    /// The number and its unit: "30 дней", "1 day".
    public static func afterComparison(_ count: Int, language: String) -> String {
        guard language == "ru" else { return Plural.days(count, language: language) }
        return "\(count) " + Plural.russian(count, "дня", "дней", "дней")
    }

    /// Just the unit, for the row that draws the number in a field of its own.
    public static func wordAfterComparison(_ count: Int, language: String) -> String {
        let counted = afterComparison(count, language: language)
        // The languages that write the number with no space (ja, zh) come back
        // unchanged rather than mangled.
        guard counted.hasPrefix("\(count)") else { return counted }
        return String(counted.dropFirst("\(count)".count)).trimmingCharacters(in: .whitespaces)
    }

    /// The same two, from the `Double` a rule actually stores.
    ///
    /// Rounded through `Int(exactly:)`: the value comes out of a plist any
    /// process running as the user can write, and `Int(Double.infinity)` traps
    /// rather than throwing — the crash `RuleSummary.number` carries the note
    /// about. A number no rule could mean is shown as the em dash that function
    /// already uses for it.
    public static func afterComparison(_ count: Double, language: String) -> String {
        guard let n = whole(count) else { return "—" }
        return afterComparison(n, language: language)
    }

    public static func wordAfterComparison(_ count: Double, language: String) -> String {
        guard let n = whole(count) else { return "—" }
        return wordAfterComparison(n, language: language)
    }

    private static func whole(_ count: Double) -> Int? {
        guard count.isFinite else { return nil }
        return Int(exactly: count.rounded())
    }
}
