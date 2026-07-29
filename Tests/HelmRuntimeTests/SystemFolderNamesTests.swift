import XCTest
@testable import HelmRuntime

/// Finder shows "Программы", not "Applications". The names come from macOS's
/// own SystemFolderLocalizations table; only the folders macOS itself
/// localizes are eligible.
final class SystemFolderNamesTests: XCTestCase {
    private let home = "/Users/me"

    func testTopLevelSystemFoldersAreEligible() {
        XCTAssertEqual(SystemFolderNames.key(forPath: "/Applications", home: home), "Applications")
        XCTAssertEqual(SystemFolderNames.key(forPath: "/Library", home: home), "Library")
        XCTAssertEqual(SystemFolderNames.key(forPath: "/Users", home: home), "Users")
        XCTAssertEqual(SystemFolderNames.key(forPath: "/System", home: home), "System")
    }

    func testHomeFoldersAreEligible() {
        XCTAssertEqual(SystemFolderNames.key(forPath: home + "/Downloads", home: home), "Downloads")
        XCTAssertEqual(SystemFolderNames.key(forPath: home + "/Desktop", home: home), "Desktop")
        XCTAssertEqual(SystemFolderNames.key(forPath: home + "/Library", home: home), "Library")
    }

    /// A folder that merely shares a name is not a system folder.
    func testSameNameElsewhereIsNotEligible() {
        XCTAssertNil(SystemFolderNames.key(forPath: home + "/Projects/Documents", home: home))
        XCTAssertNil(SystemFolderNames.key(forPath: "/opt/homebrew/Library", home: home))
        XCTAssertNil(SystemFolderNames.key(forPath: home + "/Downloads/Music", home: home))
    }

    func testUnknownTopLevelFolderIsNotEligible() {
        XCTAssertNil(SystemFolderNames.key(forPath: "/opt", home: home))
        XCTAssertNil(SystemFolderNames.key(forPath: home, home: home))
    }

    func testTrailingSlashIsTolerated() {
        XCTAssertEqual(SystemFolderNames.key(forPath: "/Applications/", home: home), "Applications")
    }

    // MARK: - Translation

    func testEnglishNeedsNoTranslation() {
        XCTAssertNil(SystemFolderNames.display(path: "/Applications", home: home, language: "en"))
    }

    /// Reads the live macOS table; skipped when the system has no Russian
    /// localization installed.
    func testRussianComesFromTheSystemTable() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath:
            "/System/Library/CoreServices/SystemFolderLocalizations/ru.lproj"))
        XCTAssertEqual(SystemFolderNames.display(path: "/Applications", home: home, language: "ru"),
                       "Программы")
        XCTAssertEqual(SystemFolderNames.display(path: home + "/Downloads", home: home,
                                                 language: "ru"), "Загрузки")
        XCTAssertNil(SystemFolderNames.display(path: home + "/Projects/Documents", home: home,
                                               language: "ru"))
    }

    func testUnknownLanguageFallsBackToNil() {
        XCTAssertNil(SystemFolderNames.display(path: "/Applications", home: home, language: "xx"))
    }

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
