import Foundation

/// How a screenshot is called, and how the next name is found when one is taken.
///
/// The **words** are macOS's own — "Screenshot 2026-09-30 at 14.02.11" in
/// English, "Снимок экрана — 2026-09-30 в 14.02.11" in Russian — and they are
/// not here: the engine takes a `ShotNaming` built by the UI target from
/// Helm's own `.strings`, which copy the template out of `screencaptureui`'s
/// table once, at development time. The engine cannot call `L()`, and a
/// template spelled in eight languages inside an engine would be the second
/// copy nothing compares against the first.
public struct ShotNaming: Sendable {
    /// `%@` for the date and `%@` for the time, in that order, with the word
    /// already in it: "Screenshot %@ at %@".
    public let template: String
    public let locale: Locale

    public init(template: String, locale: Locale) {
        self.template = template
        self.locale = locale
    }

    public static let english = ShotNaming(template: "Screenshot %@ at %@",
                                           locale: Locale(identifier: "en_US"))
}

public enum ShotNames {

    /// "Screenshot 2026-09-30 at 14.02.11", without an extension.
    ///
    /// The date is always year-month-day, as macOS writes it, and the time takes
    /// the locale's own hour cycle with its colons turned to full stops — a
    /// colon is the one character a Finder name may not carry. `timeZone` is an
    /// argument because a name is a statement about the wall clock, and a test
    /// that read this Mac's would be a reading of where it happened to be.
    public static func base(date: Date, naming: ShotNaming, timeZone: TimeZone = .current) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"

        let time = DateFormatter()
        time.locale = naming.locale
        time.timeZone = timeZone
        time.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmmss", options: 0,
                                                   locale: naming.locale) ?? "HH:mm:ss"
        let clock = time.string(from: date).replacingOccurrences(of: ":", with: ".")

        return String(format: naming.template, day.string(from: date), clock)
    }

    /// The names to try, in order: the plain one, then "(1)", "(2)" and so on.
    ///
    /// A name taken is macOS's own case — two captures in one second — and the
    /// answer here is to go on counting, **never to overwrite**. The limit is a
    /// bound on the loop and not a number a person will meet.
    public static let limit = 1000

    public static func candidate(base: String, pathExtension: String, attempt: Int) -> String {
        let stem = attempt == 0 ? base : "\(base) (\(attempt))"
        return pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"
    }
}
