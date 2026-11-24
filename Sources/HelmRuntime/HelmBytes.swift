import Foundation

/// One size format for the whole app.
///
/// One format, so a file reads as one size on every screen. Built here rather
/// than delegated, because `ByteCountFormatter` takes its unit words from the
/// localizations the running process carries, which for Helm is English: "GB"
/// where macOS itself writes "ГБ". Finder's conventions:
/// 1000 to the kilobyte, and precision that falls off with magnitude —
/// "20 KB", "1,7 MB", "432,95 GB".
public enum HelmBytes {

    /// Finder's precision: it falls off with magnitude.
    private static func precision(_ step: Int) -> Int {
        switch step {
        case 0, 1: 0      // bytes, KB
        case 2: 1         // MB
        default: 2        // GB and up
        }
    }

    private static func rounded(_ value: Double, to decimals: Int) -> Double {
        let scale = pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }
    public static func string(_ bytes: Int, language: String) -> String {
        var value = Double(max(bytes, 0))
        var step = 0
        // The unit is chosen against the number that will be *shown*, not the
        // one before rounding: 999 999 is 999.999 KB, under the threshold, and
        // would print "1000 KB" where the Finder says "1 MB".
        while step < unitOrder.count - 1, rounded(value, to: precision(step)) >= 1000 {
            value /= 1000
            step += 1
        }
        let decimals = precision(step)
        return number(value, decimals: decimals, language: language)
            + " " + unit(at: step, language: language, singular: bytes == 1)
    }

    // MARK: - Internals

    private static let unitOrder = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    private static func unit(at step: Int, language: String, singular: Bool) -> String {
        let english = step == 0 && singular ? "byte" : unitOrder[step]
        return units[language]?.first { $0.0 == english }?.1 ?? english
    }

    /// A bare number in the app's language, for the screens that show one
    /// beside a size: the same separator, the same formatter cache.
    public static func decimal(_ value: Double, decimals: Int, language: String) -> String {
        number(value, decimals: decimals, language: language)
    }

    /// A count of things — files, packages, rules — grouped the way the
    /// language groups digits: 1 499 308 in Russian and French, 1.499.308 in
    /// German, 1,499,308 in English.
    ///
    /// Seven ungrouped digits are read by counting them, which is the one thing
    /// a magnitude is not for.
    ///
    /// Separate from `decimal` rather than a flag on it: `decimal` writes the
    /// mantissa of a size, where a grouping separator would be a second decimal
    /// mark inside one number. The two share the cache and nothing else.
    public static func grouped(_ count: Int, language: String) -> String {
        return formatter(language: language, decimals: 0, grouped: true)
            .string(from: NSNumber(value: count)) ?? String(count)
    }

    /// The separator follows Helm's own language, not the system locale: the
    /// app lets the user pick a language, and "1.5 ГБ" would be neither.
    private static func number(_ value: Double, decimals: Int, language: String) -> String {
        return formatter(language: language, decimals: decimals, grouped: false)
            .string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    /// Built once per language-and-precision pair: constructing a
    /// `NumberFormatter` is most of what rendering a size costs, and a list
    /// renders hundreds of them on every frame the pointer moves over it.
    private static let formatters = LockedMemo<String, NumberFormatter>()

    private static func formatter(language: String, decimals: Int,
                                  grouped: Bool) -> NumberFormatter {
        // Grouping is part of the key: a size mantissa and a count of files
        // want opposite answers and would otherwise be handed the same
        // formatter, whichever asked first.
        formatters.value(for: "\(language)#\(decimals)#\(grouped)") {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = grouped
            formatter.minimumFractionDigits = 0      // 1,50 GB reads as noise
            formatter.maximumFractionDigits = decimals
            return formatter
        }
    }

    /// Longest suffixes first so "bytes" is matched before "byte".
    ///
    /// Every spelling here is the one in Foundation's
    /// `FileSizeFormatting.loctable`, the table `ByteCountFormatter` reads and
    /// so the one behind every size the Finder shows: Russian abbreviates the
    /// byte (`Б`), French writes the kilo lower case (`ko`), German does not
    /// pluralise `Byte`.
    private static let units: [String: [(String, String)]] = [
        "ru": [("bytes", "Б"), ("byte", "Б"), ("KB", "КБ"), ("MB", "МБ"),
               ("GB", "ГБ"), ("TB", "ТБ"), ("PB", "ПБ")],
        "zh": [("bytes", "字节"), ("byte", "字节")],
        "ja": [("bytes", "バイト"), ("byte", "バイト")],
        "es": [("bytes", "bytes"), ("byte", "byte")],
        "fr": [("bytes", "octets"), ("byte", "octet"), ("KB", "ko"), ("MB", "Mo"),
               ("GB", "Go"), ("TB", "To"), ("PB", "Po")],
        "de": [("bytes", "Byte"), ("byte", "Byte")],
        "pt": [("bytes", "bytes"), ("byte", "byte")],
    ]
}
