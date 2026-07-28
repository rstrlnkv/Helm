import XCTest
@testable import HelmRuntime

/// The unit boundaries.
///
/// `HelmBytes.string` picks the unit by dividing while the value is ≥ 1000, and
/// *then* rounds the mantissa to the unit's precision. The two steps disagree:
/// 999_999 bytes divides once to 999.999 KB, which is under the threshold, and
/// is then rounded to 0 decimals — so the screen reads "1000 KB" for a figure
/// Finder writes as "1 MB". The same happens one unit up (999_999_999 →
/// "1000 MB") and again at GB, where the precision is two decimals so the
/// window is only 5 bytes wide but the string is just as wrong.
///
/// A size that reads "1000 KB" is the number nobody writes: it is the only
/// four-digit mantissa the formatter can produce, and it appears in the Disk
/// module's ring, the Duplicates total, the Uninstaller's "freed" line and
/// Leftovers — every place Helm quotes a size.
final class HelmBytesBoundaryTests: XCTestCase {

    /// Structural, not a value comparison: whichever unit is chosen, the
    /// mantissa the user reads must be under 1000, because 1000 of a unit is
    /// the next unit. Sweeping the four decades around each boundary rather
    /// than naming one number, so a fix that special-cases 999_999 does not
    /// pass.
    func testMantissaIsNeverAThousandOrMore() {
        var offenders: [(Int, String)] = []
        for language in ["en", "ru", "fr", "de", "ja", "zh", "es", "pt"] {
            for boundary in [1_000, 1_000_000, 1_000_000_000, 1_000_000_000_000] {
                for delta in [-1, -2, -5, -50, -500, -5_000] where boundary + delta > 0 {
                    let bytes = boundary + delta
                    let text = HelmBytes.string(bytes, language: language)
                    let mantissa = Self.mantissa(of: text)
                    if let mantissa, mantissa >= 1000 {
                        offenders.append((bytes, "\(language): \(text)"))
                    }
                }
            }
        }
        XCTAssertEqual(offenders.count, 0,
                       "a mantissa of 1000 or more means the wrong unit was chosen: "
                       + offenders.map(\.1).joined(separator: ", "))
    }

    /// The concrete sentence, in the language the bug was reported in.
    /// Finder writes "1 MB" here; Helm writes "1000 KB".
    func testJustUnderAMegabyteReadsAsOneMegabyte() {
        XCTAssertEqual(HelmBytes.string(999_999, language: "en"), "1 MB")
    }

    func testJustUnderAGigabyteReadsAsOneGigabyte() {
        XCTAssertEqual(HelmBytes.string(999_999_999, language: "en"), "1 GB")
    }

    /// The leading run of digits, as a number. Works for every language here:
    /// the fraction separator is "," or "." and the unit is always separated
    /// from the number by a space or (ja/zh) follows it directly.
    private static func mantissa(of text: String) -> Double? {
        let digits = text.prefix { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
        return Double(digits.replacingOccurrences(of: ",", with: "."))
    }
}
