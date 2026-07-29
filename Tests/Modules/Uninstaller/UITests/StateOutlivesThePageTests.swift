import XCTest
import HelmContract
import HelmUI
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// What a sidebar click may not cost.
///
/// Leaving a module's page in Settings tears down the type-erased subtree and
/// every `@State` in it; coming back builds a new one. The uninstaller kept
/// `checked`, `step`, `groups`, `selectedLeftovers` and `failures` there, so one
/// click on Disk and back threw away, depending on where the person was:
///
///   • the apps they had ticked — the count read 0;
///   • a leftovers scan of every ticked app, seconds of work, and the review
///     screen with it;
///   • the failure report, which is the only record of what macOS refused and
///     why. Nothing else in the app can produce it a second time.
///
/// The view model was already cached per host view model, which is half of a
/// cache: ARCHITECTURE.md — "a cached view model feeding a list the page throws
/// away is not a cache".
@MainActor
final class StateOutlivesThePageTests: XCTestCase {

    // MARK: - Fixtures

    private struct SilentFS: FileSystemPort {
        func exists(_ url: URL) -> Bool { false }
        func size(_ url: URL) -> Int { 0 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }
    private struct StubTrash: TrashPort {
        let refuses: Bool
        func trashItem(_ url: URL) -> TrashOutcome {
            // 513 = NSFileWriteNoPermissionError, what macOS answers for a
            // protected bundle.
            refuses ? TrashOutcome(succeeded: false, errorCode: 513, message: "denied") : .success
        }
    }
    private struct NothingRunning: RunningAppsPort {
        func isRunning(bundleID: String) -> Bool { false }
        func quit(bundleID: String, force: Bool) {}
    }
    private struct FixedLister: AppLister {
        let apps: [InstalledApp]
        func installedApps() -> [InstalledApp] { apps }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
        func isKnownToSystem(bundleID: String) -> Bool { false }
    }

    private let installed = [
        InstalledApp(name: "Tool", bundleID: "com.acme.tool", path: "/Applications/Tool.app", sizeBytes: 10),
        InstalledApp(name: "Other", bundleID: "com.acme.other", path: "/Applications/Other.app", sizeBytes: 20),
    ]

    /// Held for the length of the test: the engine wires its handler weakly.
    private var engine: UninstallerEngine?

    private func host(trashRefuses: Bool = false) -> ModuleViewModel {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: FixedLister(apps: installed), fs: SilentFS(),
                                       trash: StubTrash(refuses: trashRefuses),
                                       running: NothingRunning())
        self.engine = engine
        return ModuleViewModel(transport: engine.transport)
    }

    /// What building the page does, and all it may do: `UninstallerSettingsPage`
    /// asks for the shared view model in its own `init`.
    private func openPage(_ vm: ModuleViewModel) -> UninstallerViewModel {
        _ = UninstallerSettingsPage(vm: vm)
        return UninstallerViewModel.shared(vm: vm)
    }

    // MARK: -

    /// The cache itself: same host view model, same instance, list intact.
    func testTheSecondVisitGetsTheSameViewModelAndItsList() async {
        let vm = host()
        let first = openPage(vm)
        await first.loadAppsIfNeeded()
        XCTAssertEqual(first.apps.count, 2, "precondition: the first visit loaded the list")

        let second = openPage(vm)

        XCTAssertTrue(first === second, "each visit built its own view model")
        XCTAssertEqual(second.apps.map(\.bundleID), installed.map(\.bundleID),
                       "the second visit came back to an empty list")
    }

    /// Ticking an app and leaving the page: the count read 0 on return.
    func testTicksSurviveAPageTeardown() async {
        let vm = host()
        let uvm = openPage(vm)
        await uvm.loadAppsIfNeeded()
        uvm.setChecked("com.acme.tool", true)

        let reopened = openPage(vm)

        XCTAssertEqual(reopened.checked, ["com.acme.tool"],
                       "the ticked app was thrown away with the page")
    }

    /// The review screen: a scan of every ticked app, and the step showing it.
    func testTheReviewedScanSurvivesAPageTeardown() async {
        let vm = host()
        let uvm = openPage(vm)
        await uvm.loadAppsIfNeeded()
        uvm.setChecked("com.acme.tool", true)
        await uvm.prepareReview()
        XCTAssertEqual(uvm.step, .review, "precondition: the review screen is up")

        let reopened = openPage(vm)

        XCTAssertEqual(reopened.step, .review, "the review screen fell back to the picker")
        XCTAssertEqual(reopened.groups.map(\.app.bundleID), ["com.acme.tool"],
                       "the scan of every ticked app was discarded")
    }

    /// The failure report is the only record of what macOS refused and why —
    /// reached the way a person reaches it, through a removal that was refused.
    func testTheFailureReportSurvivesAPageTeardown() async {
        let vm = host(trashRefuses: true)
        let uvm = openPage(vm)
        await uvm.loadAppsIfNeeded()
        uvm.setChecked("com.acme.tool", true)
        await uvm.prepareReview()
        await uvm.removeSelection()
        XCTAssertEqual(uvm.failures.map(\.path), ["/Applications/Tool.app"],
                       "precondition: macOS refused the bundle and the report says so")

        let reopened = openPage(vm)

        XCTAssertEqual(reopened.failures.map(\.path), ["/Applications/Tool.app"],
                       "the only record of what macOS refused went with the page")
    }
}

/// The structural half of the same claim, and the one that stays true when
/// somebody adds the sixth piece of state.
///
/// The behavioural tests above pass for as long as the view model holds these;
/// they say nothing about a *new* `@State` on the page. This reads the page's
/// own source, the way `NamedControlsTests` reads every module's.
final class PageKeepsNoDurableStateTests: XCTestCase {

    /// State whose loss a person notices: what they ticked, where they are, what
    /// was scanned, and what was refused. `search`, `tab` and `diskAccess` are
    /// deliberately not here — a search term is re-typed in a second, and the
    /// permission is re-probed on every appearance.
    private static let mustOutlivePage = ["checked", "step", "groups",
                                          "selectedLeftovers", "failures"]

    func testThePageDeclaresNoStateThatMustOutliveIt() throws {
        let page = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UITests
            .deletingLastPathComponent()   // Uninstaller
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources/Modules/Uninstaller/UI/UninstallerSettingsPage.swift")
        let source = try String(contentsOf: page, encoding: .utf8)

        let offenders = source
            .components(separatedBy: "\n")
            .filter { $0.contains("@State") }
            .filter { line in
                Self.mustOutlivePage.contains { line.contains(" \($0) ") || line.contains(" \($0):") }
            }

        XCTAssertEqual(offenders, [],
                       "state a sidebar click destroys is declared on the page rather than "
                       + "on the view model that outlives it")
    }
}
