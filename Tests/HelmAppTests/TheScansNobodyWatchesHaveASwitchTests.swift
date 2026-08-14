import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import HelmApp

/// The section that finally says Helm reads the disk on its own.
///
/// `ScanCoordinator` walks the volume for three modules while the Mac is idle,
/// and `AppSettings.disabledScans` — the one switch — was written by **nothing**
/// in `Sources/`: the only way to learn any of this was the log. `ScanConsent`
/// holds the arithmetic; what is held here is the half a person can see, which
/// is the half that was missing.
@MainActor
final class TheScansNobodyWatchesHaveASwitchTests: XCTestCase {

    /// The rows are the list the coordinator actually loops over, not a list
    /// written again for the screen. A hand-written second copy is the comment
    /// CLAUDE.md § A hand-written list warns about: a scan added to
    /// `ScanRunner.scannableModules` and forgotten here reads as consent nobody
    /// was asked for.
    func testEveryScanThatCanRunHasARowOnTheScreen() {
        let everyModule = Set(ModuleRegistry.all.map(\.idRaw))
        let rows = MenuBarSettingsView.scanRows(enabled: everyModule,
                                                disabledScans: [],
                                                lastRun: [:])
        XCTAssertEqual(rows.map(\.id), ScanRunner.scannableModules)
        XCTAssertTrue(rows.allSatisfy(\.isOn))
    }

    /// The screen and the getter answer the same question, so they read the
    /// same default: Disk's whole-volume walk is off until somebody says
    /// otherwise, and the row has to show that rather than its own guess.
    func testTheScreenStartsWhereTheStoredDefaultStarts() {
        let rows = MenuBarSettingsView.scanRows(enabled: Set(ModuleRegistry.all.map(\.idRaw)),
                                                disabledScans: AppSettings.defaultDisabledScans,
                                                lastRun: [:])
        XCTAssertEqual(rows.first { !$0.isOn }.map(\.id), "disk",
                       "the one scan off by default is Disk's, and the row must say so")
        XCTAssertEqual(rows.filter(\.isOn).count, ScanRunner.scannableModules.count - 1)
    }

    /// Every sentence of the section, in the eight languages — including the
    /// one this machine is not set to. A test gated on `.current` checks one.
    func testTheSectionIsWrittenInAllEightLanguages() {
        let sentences: [(String, (AppLanguage) -> String)] = [
            ("heading", { AppStr.backgroundScansSection(language: $0) }),
            ("note", { AppStr.backgroundScansNote(language: $0) }),
            ("never run", { AppStr.scanNeverRun(language: $0) }),
            ("last run", { AppStr.scanLastRun("…", language: $0) }),
        ]
        for (name, sentence) in sentences {
            let english = sentence(.en)
            XCTAssertFalse(english.isEmpty, "\(name) says nothing in English")
            for language in AppLanguage.allCases where language != .en {
                let translated = sentence(language)
                XCTAssertFalse(translated.isEmpty, "\(language.rawValue) says nothing for \(name)")
                XCTAssertNotEqual(translated, english,
                                  "\(language.rawValue) fell back to English for the \(name), "
                                  + "which is what a missing row in the table looks like")
            }
        }
    }

    /// **The finding itself, and it is about the tree rather than a value.**
    /// The switch existed, the coordinator read it, the seal defended it — and
    /// no screen wrote it. A stored setting nothing in the app can set is not a
    /// setting; it is a constant with a keychain item.
    func testTheSettingHasAWriterThatIsNotItsOwnDeclaration() throws {
        let files = try RepoSource.swiftFiles(under: "Sources")
            .filter { $0 != "Sources/HelmApp/AppSettings.swift" }
        XCTAssertGreaterThan(files.count, 100,
                             "only \(files.count) source files were read, so a pass means nothing")
        var writers: [String] = []
        for file in files {
            let code = try RepoSource.lines(of: file).map(RepoSource.code)
            if code.contains(where: { $0.contains("AppSettings.disabledScans =") }) {
                writers.append(file)
            }
        }
        XCTAssertFalse(writers.isEmpty,
                       "nothing outside its own declaration writes AppSettings.disabledScans, "
                       + "so the background scans are again a thing the app does with no way "
                       + "for anybody to answer about it")
    }
}
