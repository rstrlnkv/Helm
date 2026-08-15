import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The three empty histories, and the five presets, in every language.
///
/// **Parameterized by the language rather than reading `AppLanguage.current`.**
/// The suite runs in whatever this Mac is set to, so an assertion over `current`
/// checks one language eight times — and this Mac's is not English, which is how
/// a mutation planted in an English value once passed.
@MainActor
final class ThreeEmptiesSpeakInEightTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    // MARK: - The reason the page actually reaches

    /// Each of the three states built out of what the engine answers, so the
    /// sentences below are ones this page can really draw. **The state is
    /// asserted before the reason** — a reason computed over a page that never
    /// reached that state is a check that cannot fail.
    func testTheThreeStatesEachReachTheirOwnReason() async {
        let watched = WatchedFolder(id: "f", path: home + "/Downloads", rules: [])
        var running = watched
        running.rules = [Rule(id: "r", name: "r", enabled: true,
                              conditions: [.fileExtension(["pdf"])], action: .trash)]

        for (folders, expected) in [([], HistoryEmpty.Reason.noFolders),
                                    ([watched], .everyRuleOff),
                                    ([running], .nothingYet)] {
            let wire = AutopilotWire(folders: folders)
            let model = model(on: wire)
            await model.load()

            XCTAssertEqual(model.folders.map(\.id), folders.map(\.id),
                           "precondition: the page is holding the rule set this is about")
            XCTAssertTrue(model.runs.isEmpty, "precondition: and nothing has happened")
            XCTAssertEqual(model.historyEmpty, expected)
        }
    }

    /// And a page with a pass on it has no empty state at all, which is what
    /// makes the three above statements about an empty screen rather than the
    /// only thing this function ever returns.
    func testAPageWithAPassOnItHasNoEmptyState() async {
        let record = ActionRecord(at: Date(), rule: "r", file: "a.pdf", kind: .trashed,
                                  detail: "", path: home + "/Downloads/a.pdf", run: "run")
        let wire = AutopilotWire(folders: [WatchedFolder(id: "f", path: home + "/Downloads")],
                                 history: [record])
        let model = model(on: wire)

        await model.load()

        XCTAssertFalse(model.runs.isEmpty, "precondition: there is a pass on the page")
        XCTAssertNil(model.historyEmpty)
    }

    // MARK: - What each one says

    /// Three states, three sentences, eight languages — and no two of them the
    /// same, which is the whole of the finding: one sentence was drawn over all
    /// three.
    func testEachEmptyStateSaysSomethingDifferentInEveryLanguage() {
        let reasons: [HistoryEmpty.Reason] = [.noFolders, .everyRuleOff, .nothingYet]
        for language in AppLanguage.allCases {
            var said = Set<String>()
            for reason in reasons {
                let line = ApStr.historyEmpty(reason, language: language)
                XCTAssertFalse(line.isEmpty, "\(language.rawValue) says nothing for \(reason)")
                said.insert(line)
            }
            XCTAssertEqual(said.count, reasons.count,
                           "\(language.rawValue): two empty states collapsed onto one sentence")
        }
    }

    /// Translated, not fallen back to English. `L()` answers the key itself when
    /// a language has no entry, so a missing translation is a silent English
    /// string on a Russian screen rather than an error.
    func testEveryEmptyStateIsTranslated() {
        for reason in [HistoryEmpty.Reason.noFolders, .everyRuleOff, .nothingYet] {
            let english = ApStr.historyEmpty(reason, language: .en)
            for language in AppLanguage.allCases where language != .en {
                XCTAssertNotEqual(ApStr.historyEmpty(reason, language: language), english,
                                  "\(language.rawValue) fell back to English for \(reason)")
            }
        }
    }

    // MARK: - The presets

    /// Five names, five different names, in every language. A preset whose name
    /// collided with another's would be two rows a person cannot tell apart.
    func testEveryPresetIsNamedAndTranslated() {
        for language in AppLanguage.allCases {
            var names = Set<String>()
            for kind in PresetKind.allCases {
                let name = ApStr.presetName(kind, language: language)
                XCTAssertFalse(name.isEmpty, "\(language.rawValue) has no name for \(kind)")
                if language != .en {
                    XCTAssertNotEqual(name, ApStr.presetName(kind, language: .en),
                                      "\(language.rawValue) fell back to English for \(kind)")
                }
                names.insert(name)
            }
            XCTAssertEqual(names.count, PresetKind.allCases.count,
                           "\(language.rawValue): two presets share a name")
        }
    }

    /// The button that adds a folder says which folder, in macOS's own word for
    /// it — never a ninth translation of a name the system already has.
    func testTheButtonNamesTheFolderInTheSystemsOwnWord() async throws {
        let model = model(on: AutopilotWire())
        await model.load()
        let offer = try XCTUnwrap(model.presets.first { $0.preset.folder == .downloads })

        // Asserted first, and of the two languages that genuinely rename this
        // folder: `display` answers nil both for English and for a language
        // that keeps the English word — German and Portuguese both say
        // «Downloads» — so a loop that only ever saw the fallback would prove
        // nothing about reading the system's table at all.
        for language in [AppLanguage.ru, .fr] {
            XCTAssertNotEqual(SystemFolderNames.display(path: home + "/Downloads", home: home,
                                                        language: language.rawValue),
                              "Downloads",
                              "precondition: macOS renames this folder in \(language.rawValue)")
        }

        for language in AppLanguage.allCases {
            let folder = SystemFolderNames.display(path: home + "/Downloads", home: home,
                                                   language: language.rawValue) ?? "Downloads"
            XCTAssertTrue(ApStr.seePreset(in: folder, language: language).contains(folder),
                          "\(language.rawValue) dropped the folder name off the button")
        }
        XCTAssertEqual(offer.folderName(home: home),
                       SystemFolderNames.display(path: home + "/Downloads", home: home,
                                                 language: AppLanguage.current.rawValue)
                           ?? "Downloads")
    }
}
