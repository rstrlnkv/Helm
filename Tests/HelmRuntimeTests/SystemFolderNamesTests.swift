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
}
