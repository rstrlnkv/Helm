import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **An unanswered `listApps` read as «you have no applications», and it never
/// tried again.**
///
/// Measured with a transport that answers nothing: `apps` 0, `loadingApps` false,
/// and the footer «0 apps» / «0 приложений» — a sentence about somebody's Mac
/// that Helm never checked, on the first screen of the module. `loadedApps` was
/// set whatever came back, so the next visit to the page would not ask again;
/// only the Refresh button would.
///
/// `UnStr.appsCount(nil)` — «Counting apps…» — is what the page already says for
/// "I do not know yet", so the repair is to stay in that state rather than to
/// invent a sentence: keep the list, leave the flag alone, and let the next
/// appearance ask.
@MainActor
final class AnUnansweredListIsNotAnEmptyMacTests: XCTestCase {

    /// Both silences the wire has, and `TransportClient.request` folds them to
    /// one nil: a `send` that throws, and the empty `Data` the engine itself
    /// answers when it has gone under a page that is still up. The wire owns the
    /// list — this file and the empty-state one both ran over it.
    private static let silences = UninstallerWire.Answer.silences

    private let tool = InstalledApp(name: "Tool", bundleID: "com.acme.tool",
                                    path: "/Applications/Tool.app", sizeBytes: 4_096)

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
    }

    private func model(_ wire: UninstallerWire) -> UninstallerViewModel {
        UninstallerViewModel(vm: ModuleViewModel(transport: wire))
    }

    // MARK: -

    /// The claim: a list that was never answered is not a count of zero.
    func testAnUnansweredListIsNotACountOfNoApps() async {
        for silence in Self.silences {
            let wire = UninstallerWire(apps: [tool], answering: silence)
            let uvm = model(wire)

            await uvm.loadAppsIfNeeded()

            XCTAssertTrue(wire.commands.contains(.listApps),
                          "precondition: the list really was asked for (\(silence))")
            XCTAssertNil(uvm.appCount, """
                the footer says «\(UnStr.appsCount(uvm.appCount))» about a Mac whose \
                applications Helm never managed to read (\(silence))
                """)
            XCTAssertFalse(uvm.loadingApps, "and it is not still loading either (\(silence))")
        }
    }

    /// And the next appearance asks again. Without this the module holds "you have
    /// no applications" for the life of the process.
    func testAnUnansweredListIsAskedForAgainOnTheNextVisit() async {
        for silence in Self.silences {
            let wire = UninstallerWire(apps: [tool], answering: silence)
            let uvm = model(wire)
            await uvm.loadAppsIfNeeded()
            XCTAssertTrue(uvm.apps.isEmpty, "precondition: nothing arrived (\(silence))")

            wire.answers(.reply)
            await uvm.loadAppsIfNeeded()

            XCTAssertEqual(uvm.apps.map(\.bundleID), [tool.bundleID],
                           "the page never asked again, so the module holds an empty list "
                           + "for as long as the app runs (\(silence))")
            XCTAssertEqual(uvm.appCount, 1, "and the count arrived with it (\(silence))")
        }
    }

    /// The other half, and what keeps the retry from being «ask on every
    /// appearance»: a Mac that really has no applications answered, and that
    /// answer is kept.
    func testAnAnsweredEmptyListIsACountOfNoAppsAndIsNotAskedAgain() async {
        let wire = UninstallerWire(apps: [], answering: .reply)
        let uvm = model(wire)

        await uvm.loadAppsIfNeeded()
        await uvm.loadAppsIfNeeded()

        XCTAssertEqual(uvm.appCount, 0, "an answer of «none» is an answer")
        XCTAssertEqual(wire.commands.filter { $0 == .listApps }.count, 1,
                       "the list was read a second time for a question already answered")
    }

    /// A Refresh that goes unanswered may not empty the list the person is
    /// looking at either.
    func testAnUnansweredRefreshKeepsTheListAlreadyOnScreen() async {
        for silence in Self.silences {
            let wire = UninstallerWire(apps: [tool], answering: .reply)
            let uvm = model(wire)
            await uvm.loadAppsIfNeeded()
            XCTAssertEqual(uvm.apps.count, 1, "precondition: the list is up (\(silence))")

            wire.answers(silence)
            await uvm.reloadApps()

            XCTAssertEqual(uvm.apps.map(\.bundleID), [tool.bundleID],
                           "a Refresh nobody answered cleared the list (\(silence))")
            XCTAssertEqual(uvm.appCount, 1,
                           "and the count went with it (\(silence))")
        }
    }

    /// **And the footer draws it.** The model can be as careful as it likes about
    /// what it does not know while the page derives a count of its own from an
    /// empty list, which is what it did: `loading ? nil : apps.count`.
    ///
    /// **This test asserted `UnStr.appsCount(nil)` here until 2026-08-20, and
    /// that was the defect written down as a requirement.** «Counting apps…» is
    /// the honest sentence for a reply on its way and a false one for a reply
    /// that never came — and the body 600 pt above was already saying «Helm
    /// could not read the list of applications» with a *Reload list* button
    /// under it. One state, a failure and a claim of progress at once. The
    /// footer says nothing now, and the two halves are one value
    /// (`AppsEmpty.status`), so they cannot drift apart again.
    func testTheFooterSaysNothingAboutAListNobodyAnswered() async {
        let wire = UninstallerWire(apps: [tool], answering: .nothing)
        let vm = ModuleViewModel(transport: wire)
        let page = UninstallerSettingsPage(vm: vm)
        let uvm = UninstallerViewModel.shared(vm: vm)

        await uvm.loadAppsIfNeeded()

        XCTAssertTrue(wire.commands.contains(.listApps),
                      "precondition: the list really was asked for")
        XCTAssertEqual(page.appsEmpty, .neverAnswered,
                       "precondition: the body is drawing the refusal this footer sits under")
        XCTAssertNil(page.statusLine, """
            the footer says «\(page.statusLine ?? "")» beside a body reporting that the \
            list could not be read
            """)
    }

    /// And it reaches the log, which is the one place a person can look
    /// afterwards. Counts and outcomes only — nothing here names an application.
    func testAnUnansweredListSaysSoInTheLog() async {
        let wire = UninstallerWire(apps: [tool], answering: .nothing)
        let uvm = model(wire)

        await uvm.loadAppsIfNeeded()

        XCTAssertNil(uvm.appCount, "precondition: the list really was not answered")
        XCTAssertTrue(logged.contains { $0.contains("app list reply lost") }, """
            a list whose reply never came wrote nothing to the log: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains(tool.bundleID) },
                       "and the line must not name the software: \(logged)")
    }
}
