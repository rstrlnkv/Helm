import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The page's half of «empty, unreadable and gone are one report».
///
/// The engine answers which of the three a folder is, and whether anything is
/// watching. This is the sentence a person gets for it — one per folder, beside
/// the path, without pressing anything: the switch says «on» over all four
/// states and only one of them is working.
@MainActor
final class AFolderThatIsGoneSaysSoTests: XCTestCase {

    private let folder = WatchedFolder(id: "downloads", path: "/tmp/watched")

    private func model(on wire: AutopilotWire) async -> AutopilotViewModel {
        let model = AutopilotViewModel(vm: ModuleViewModel(transport: wire))
        await model.load()
        return model
    }

    private func status(_ state: FolderState, watching: Bool? = true) -> AutopilotStatus {
        AutopilotStatus(refusal: nil, folders: ["downloads": state], watching: watching)
    }

    // MARK: - Which of the three

    func testAFolderThatWasReadSaysNothing() async {
        let model = await model(on: AutopilotWire(folders: [folder], status: status(.read)))

        XCTAssertNil(model.notice(for: folder))
    }

    func testAFolderThatIsNoLongerThereSaysSo() async {
        let model = await model(on: AutopilotWire(folders: [folder], status: status(.missing)))

        XCTAssertEqual(model.notice(for: folder), ApStr.folderMissing())
    }

    func testAFolderHelmMayNotReadSaysSo() async {
        let model = await model(on: AutopilotWire(folders: [folder], status: status(.refused)))

        XCTAssertEqual(model.notice(for: folder), ApStr.folderUnreadable())
    }

    /// Three states, three sentences — in every language, because a table entry
    /// copied from the row above is how two of them become one.
    func testTheThreeSentencesAreThreeSentences() {
        for language in AppLanguage.allCases {
            let said = [ApStr.folderMissing(language: language),
                        ApStr.folderUnreadable(language: language),
                        ApStr.notWatching(language: language)]
            XCTAssertEqual(Set(said).count, 3, "\(language.rawValue) says the same thing twice")
        }
    }

    // MARK: - Whether anything is watching

    func testAFolderNothingIsWatchingSaysSo() async {
        let model = await model(on: AutopilotWire(folders: [folder],
                                                  status: status(.read, watching: false)))

        XCTAssertEqual(model.notice(for: folder), ApStr.notWatching())
    }

    /// An engine that has not been asked to watch anything yet says nothing
    /// about it: «I do not know» is not «nothing is watching», and drawing it as
    /// one would put a warning on every page that opens before the module is
    /// activated.
    func testAnEngineThatHasNotAnsweredYetIsNotAWarning() async {
        let model = await model(on: AutopilotWire(folders: [folder],
                                                  status: status(.read, watching: nil)))

        XCTAssertNil(model.notice(for: folder))
    }

    /// A folder somebody switched off is not being watched on purpose.
    func testAFolderThatIsSwitchedOffIsNotWarnedAbout() async {
        let off = WatchedFolder(id: "downloads", path: "/tmp/watched", enabled: false)
        let model = await model(on: AutopilotWire(folders: [off],
                                                  status: status(.read, watching: false)))

        XCTAssertNil(model.notice(for: off))
    }

    /// And the reading wins: a folder that is gone is not "not being watched",
    /// which is true of it and is not the thing to say.
    func testAMissingFolderIsNotDescribedAsUnwatched() async {
        let model = await model(on: AutopilotWire(folders: [folder],
                                                  status: status(.missing, watching: false)))

        XCTAssertEqual(model.notice(for: folder), ApStr.folderMissing())
    }

    // MARK: - After a run

    /// A Run now walks the folder, so its report is the newest answer there is —
    /// and a page holding a stale one would go on saying a folder is fine while
    /// the run that just finished found it gone.
    func testARunUpdatesWhatIsSaidAboutTheFolder() async {
        let wire = AutopilotWire(folders: [folder], status: status(.read),
                                 report: SweepReport(folderID: "downloads", examined: 0,
                                                     acted: 0, refused: 0, failed: 0,
                                                     folder: .missing))
        let model = await model(on: wire)
        XCTAssertNil(model.notice(for: folder), "precondition: the page opened on a folder that was fine")

        await model.runNow(folder)

        XCTAssertEqual(model.notice(for: folder), ApStr.folderMissing())
    }
}
