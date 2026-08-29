import Foundation

/// A span of time, spelled the way the reader's language spells one.
///
/// Beside `Bytes` and `HelmDates` for the reason they are there: a `Foundation`
/// formatter built with no locale answers in the **system's** language, and
/// this app's language is a setting of its own. `DateComponentsFormatter` is
/// asked rather than a table of unit names invented here — the same rule as
/// reading a pane's name out of macOS instead of translating it again.
///
/// **The unit grows on its own.** What this draws starts at seconds on a quiet
/// day and reaches hours over a year, so a page that picked minutes once ends
/// up showing «4 081 минута». Seconds while it is seconds, minutes once there
/// are minutes, hours and minutes after an hour — and never three parts, since
/// this is read at the hero's size and «1 h 20 min 30 s» is not read at all.
public enum HelmDuration {

    /// The span, or an empty string when there is none.
    ///
    /// Empty rather than «0 s»: a page with nothing to show draws no figure,
    /// and this is the value it tests for. A formatter asked for zero answers
    /// «0 сек.», which is a number standing in for an absence.
    public static func string(_ seconds: TimeInterval,
                              language: AppLanguage = AppLanguage.current) -> String {
        guard seconds >= 1 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.calendar = {
            var calendar = Calendar.current
            calendar.locale = Locale(identifier: language.rawValue)
            return calendar
        }()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = allowedUnits(for: seconds)
        // Otherwise an hour and a half is «1 h 30 min 0 s»: the formatter pads
        // every allowed unit that is not the largest.
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: seconds) ?? ""
    }

    /// Two units at most, and only ones the figure has reached.
    private static func allowedUnits(for seconds: TimeInterval) -> NSCalendar.Unit {
        if seconds < 60 { return [.second] }
        if seconds < 3600 { return [.minute] }
        return [.hour, .minute]
    }
}
