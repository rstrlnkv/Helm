import XCTest
@testable import HelmRuntime

/// Finder shows "Программы", not "Applications". The names come from macOS's
/// own SystemFolderLocalizations table; only the folders macOS itself
/// localizes are eligible.
final class SystemFolderNamesTests: XCTestCase {
    private let home = "/Users/me"

    /// Every language Helm ships must actually reach a table.
    ///
    /// Testing Russian alone hid a defect for the whole life of the module:
    /// the lproj directory was built from `AppLanguage.rawValue`, which
    /// happens to equal the directory name for seven of the eight — and does
    /// not for Chinese, where macOS ships `zh_CN.lproj`, `zh_TW.lproj` and
    /// `zh_HK.lproj` and no `zh.lproj`. The table silently came back empty, so
    /// the Disk ring showed a Chinese user `Applications` where Finder says
    /// 应用程序. The module's whole premise is that folders carry the names
    /// Finder gives them.
    func testEveryShippedLanguageResolvesTheSystemTable() throws {
        let root = "/System/Library/CoreServices/SystemFolderLocalizations"
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root + "/ru.lproj"))
        // `/Users`, not `/Applications`: French calls the latter
        // "Applications" too, and `display` correctly answers nil when the
        // translation equals the key — that is nothing to translate, not a
        // missing table. `/Users` differs in all seven.
        for language in ["ru", "es", "fr", "de", "ja", "zh", "pt"] {
            let translated = SystemFolderNames.display(path: "/Users", home: home,
                                                       language: language)
            XCTAssertNotNil(translated,
                            "\(language): /Users did not resolve to a system name — "
                            + "the localization table for this language never loaded")
            XCTAssertNotEqual(translated, "Users", "\(language) returned the English name")
        }
    }
}
