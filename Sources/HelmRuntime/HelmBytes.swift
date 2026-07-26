import Foundation

/// One size format for the whole app.
///
/// Two defects made this necessary. The modules formatted sizes two different
/// ways — one counting 1024 to the kilobyte, one counting 1000 — so the same
/// file read as a different size depending on the screen. And
/// `ByteCountFormatter` takes its unit words from whatever localizations the
/// running process happens to carry, which for Helm is English: a Russian user
/// saw "432,95 GB" where macOS itself writes "432,95 ГБ".
///
/// So the number is built here rather than delegated. Finder's conventions:
/// 1000 to the kilobyte, and precision that falls off with magnitude —
/// "20 KB", "1,7 MB", "432,95 GB".
public enum HelmBytes {
    public static func string(_ bytes: Int, language: String) -> String {
        var value = Double(max(bytes, 0))
        var step = 0
        while value >= 1000, step < unitOrder.count - 1 {
            value /= 1000
            step += 1
        }
        let decimals: Int
        switch step {
        case 0, 1: decimals = 0      // bytes, KB
        case 2: decimals = 1         // MB
        default: decimals = 2        // GB and up
        }
        return number(value, decimals: decimals, language: language)
            + " " + unit(at: step, language: language, singular: bytes == 1)
    }

    /// Swaps a trailing English unit for the language's own. Split out so the
    /// mapping can be checked without a formatter or a locale in the way.
    public static func localizedUnits(_ formatted: String, language: String) -> String {
        guard let table = units[language] else { return formatted }
        for (english, translated) in table where formatted.hasSuffix(" " + english) {
            return formatted.dropLast(english.count) + translated
        }
        return formatted
    }

    // MARK: - Internals

    private static let unitOrder = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    private static func unit(at step: Int, language: String, singular: Bool) -> String {
        let english = step == 0 && singular ? "byte" : unitOrder[step]
        return units[language]?.first { $0.0 == english }?.1 ?? english
    }

    /// The separator follows Helm's own language, not the system locale: the
    /// app lets the user pick a language, and "1.5 ГБ" would be neither.
    private static func number(_ value: Double, decimals: Int, language: String) -> String {
        let formatter = formatters.formatter(language: language, decimals: decimals)
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    /// Built once per language-and-precision pair. Constructing a
    /// `NumberFormatter` costs about fourteen microseconds, which was almost
    /// all of what it cost to render a file size — and a list renders two
    /// hundred of them on every frame the pointer moves over it.
    private static let formatters = FormatterCache()

    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cache: [String: NumberFormatter] = [:]

        func formatter(language: String, decimals: Int) -> NumberFormatter {
            let key = "\(language)#\(decimals)"
            lock.lock()
            defer { lock.unlock() }
            if let existing = cache[key] { return existing }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            formatter.minimumFractionDigits = 0      // 1,50 GB reads as noise
            formatter.maximumFractionDigits = decimals
            cache[key] = formatter
            return formatter
        }
    }

    /// Longest suffixes first so "bytes" is matched before "byte".
    private static let units: [String: [(String, String)]] = [
        "ru": [("bytes", "байт"), ("byte", "байт"), ("KB", "КБ"), ("MB", "МБ"),
               ("GB", "ГБ"), ("TB", "ТБ"), ("PB", "ПБ")],
        "zh": [("bytes", "字节"), ("byte", "字节")],
        "ja": [("bytes", "バイト"), ("byte", "バイト")],
        "es": [("bytes", "bytes"), ("byte", "byte")],
        "fr": [("bytes", "octets"), ("byte", "octet"), ("KB", "Ko"), ("MB", "Mo"),
               ("GB", "Go"), ("TB", "To"), ("PB", "Po")],
        "de": [("bytes", "Bytes"), ("byte", "Byte")],
        "pt": [("bytes", "bytes"), ("byte", "byte")],
    ]
}
