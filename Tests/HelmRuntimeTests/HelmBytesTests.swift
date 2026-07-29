import XCTest
@testable import HelmRuntime

/// Sizes are the numbers users compare between screens, so one formatter has
/// to produce all of them — and in Russian macOS writes "ГБ", never "GB".
/// The unit words are asserted through `string`, the only way the app asks for
/// one. They used to be asserted through a separate suffix-swapping helper that
/// no screen called, so the table below was covered by a function nobody ran.
final class HelmBytesTests: XCTestCase {
    func testUnitsAreTranslated() {
        XCTAssertEqual(HelmBytes.string(1_500_000_000, language: "ru"), "1,5 ГБ")
        XCTAssertEqual(HelmBytes.string(340_000_000, language: "ru"), "340 МБ")
        XCTAssertEqual(HelmBytes.string(12_000, language: "ru"), "12 КБ")
        XCTAssertEqual(HelmBytes.string(2_000_000_000_000, language: "ru"), "2 ТБ")
    }

    /// Each of these is the spelling in `FileSizeFormatting.loctable`, the table
    /// `ByteCountFormatter` reads: Russian abbreviates the byte, French writes a
    /// lowercase kilo (`ko`) beside an uppercase mega (`Mo`), and German uses
    /// one form for one byte and for many.
    func testByteWordIsTranslated() {
        XCTAssertEqual(HelmBytes.string(512, language: "ru"), "512 Б")
        XCTAssertEqual(HelmBytes.string(1, language: "ru"), "1 Б")
        XCTAssertEqual(HelmBytes.string(512, language: "de"), "512 Byte")
        XCTAssertEqual(HelmBytes.string(1, language: "de"), "1 Byte")
        XCTAssertEqual(HelmBytes.string(512, language: "zh"), "512 字节")
        XCTAssertEqual(HelmBytes.string(1, language: "ja"), "1 バイト")
    }

    func testFrenchKiloIsLowercaseAndTheRestAreNot() {
        XCTAssertEqual(HelmBytes.string(20_000, language: "fr"), "20 ko")
        XCTAssertEqual(HelmBytes.string(1_700_000, language: "fr"), "1,7 Mo")
        XCTAssertEqual(HelmBytes.string(432_950_000_000, language: "fr"), "432,95 Go")
        XCTAssertEqual(HelmBytes.string(1, language: "fr"), "1 octet")
        XCTAssertEqual(HelmBytes.string(512, language: "fr"), "512 octets")
    }

    /// A language whose table stops at the byte keeps the English abbreviation
    /// above it — which is what `FileSizeFormatting.loctable` itself does.
    func testLanguagesWithoutTheirOwnAbbreviationKeepEnglish() {
        XCTAssertEqual(HelmBytes.string(1_000_000_000, language: "de"), "1 GB")
        XCTAssertEqual(HelmBytes.string(1_000, language: "ja"), "1 KB")
        XCTAssertEqual(HelmBytes.string(1_000, language: "zh"), "1 KB")
    }

    func testUnknownLanguageFallsBackToEnglishUnits() {
        XCTAssertEqual(HelmBytes.string(7_000_000, language: "xx"), "7 MB")
    }

    // MARK: - End to end

    func testZeroReadsAsANumberNotAWord() {
        XCTAssertEqual(HelmBytes.string(0, language: "en"), "0 bytes")
    }

    /// The unit words must not depend on which localizations the running
    /// process happens to carry — that made an earlier version of these
    /// assertions pass or fail with the machine's system language.
    func testMagnitudesAndUnitsAreDeterministic() {
        XCTAssertEqual(HelmBytes.string(1_500_000_000, language: "en"), "1.5 GB")
        XCTAssertEqual(HelmBytes.string(1_500_000_000, language: "ru"), "1,5 ГБ")
        XCTAssertEqual(HelmBytes.string(340_000, language: "en"), "340 KB")
        XCTAssertEqual(HelmBytes.string(1, language: "en"), "1 byte")
        XCTAssertEqual(HelmBytes.string(432_950_000_000, language: "ru"), "432,95 ГБ")
    }

    /// Sizes are compared between screens, so one file is one number
    /// everywhere: 1000 to the kilobyte, as Finder counts.
    func testKilobyteIsAThousandBytes() {
        XCTAssertEqual(HelmBytes.string(1_000, language: "en"), "1 KB")
        XCTAssertEqual(HelmBytes.string(999, language: "en"), "999 bytes")
    }
}
