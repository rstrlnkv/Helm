import XCTest
@testable import HelmRuntime

/// Sizes are the numbers users compare between screens, so one formatter has
/// to produce all of them — and in Russian macOS writes "ГБ", never "GB".
final class HelmBytesTests: XCTestCase {
    func testUnitsAreTranslated() {
        XCTAssertEqual(HelmBytes.localizedUnits("1,5 GB", language: "ru"), "1,5 ГБ")
        XCTAssertEqual(HelmBytes.localizedUnits("340 MB", language: "ru"), "340 МБ")
        XCTAssertEqual(HelmBytes.localizedUnits("12 KB", language: "ru"), "12 КБ")
        XCTAssertEqual(HelmBytes.localizedUnits("2 TB", language: "ru"), "2 ТБ")
    }

    func testByteWordIsTranslated() {
        XCTAssertEqual(HelmBytes.localizedUnits("512 bytes", language: "ru"), "512 байт")
        XCTAssertEqual(HelmBytes.localizedUnits("1 byte", language: "ru"), "1 байт")
    }

    func testEnglishIsLeftAlone() {
        XCTAssertEqual(HelmBytes.localizedUnits("1.5 GB", language: "en"), "1.5 GB")
    }

    /// Only the trailing unit is a unit: a file called "GB" in the number's
    /// place must not be rewritten.
    func testOnlyTheTrailingUnitIsReplaced() {
        XCTAssertEqual(HelmBytes.localizedUnits("1 GB", language: "de"), "1 GB")
        XCTAssertEqual(HelmBytes.localizedUnits("1 KB", language: "ja"), "1 KB")
    }

    func testUnknownLanguageIsUnchanged() {
        XCTAssertEqual(HelmBytes.localizedUnits("7 MB", language: "xx"), "7 MB")
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
