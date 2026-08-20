import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The half of the moving fact that the status alone does not cover.**
///
/// `BrewComingAndGoingIsNoticedTests` established that brew appearing and
/// vanishing are noticed on every visit. The list is guarded separately and on
/// purpose — `brew list --versions` twice plus a `brew desc` batch over every
/// package is seconds, and re-paying it on every return visit is what the guard
/// exists to prevent. But «already loaded» was the only question it asked, and
/// the packages belong to *a* brew, not to the app: uninstall Homebrew and
/// install it again between two visits — a reinstall onto a fresh Cellar, or a
/// move from `/usr/local` to `/opt/homebrew` — and the page came back listing
/// the packages of the brew that is gone, each row with an Uninstall button
/// that the engine now refuses.
///
/// So the list is keyed to the brew it was read from, which is the same
/// question `status` already answers. The control below is the guard itself:
/// an unchanged brew must still cost nothing on a second visit.
@MainActor
final class ANewBrewDoesNotInheritTheOldCellarTests: XCTestCase {

    /// brew as a path that may move, vanish and come back — the port answers
    /// `FileManager.isExecutableFile` afresh at every call.
    private final class MovingLocator: BrewLocator, @unchecked Sendable {
        private let lock = NSLock()
        private var _path: String?
        init(path: String?) { _path = path }
        var path: String? {
            get { lock.lock(); defer { lock.unlock() }; return _path }
            set { lock.lock(); _path = newValue; lock.unlock() }
        }
        func brewPath() -> String? { path }
    }

    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }

    /// Answers a different Cellar per brew path, so "the list came from the
    /// brew that is gone" is a thing a test can read rather than infer from a
    /// call count.
    private final class PerBrewCellar: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _listCalls = 0
        var listCalls: Int { lock.lock(); defer { lock.unlock() }; return _listCalls }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            guard args.first == "list" else { return (0, "") }
            lock.lock(); _listCalls += 1; lock.unlock()
            guard args.contains("--formula") else { return (0, "") }
            return launchPath.hasPrefix("/opt")
                ? (0, "wget 1.25.0\n")
                : (0, "curl 8.7.1\n")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            NoProcess()
        }
    }

    private func page(_ locator: MovingLocator, _ runner: PerBrewCellar)
    -> (HomebrewViewModel, HomebrewEngine) {
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: locator, runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport, marker: InMemoryOpMarker())
        return (HomebrewViewModel(vm: ModuleViewModel(transport: transport)), engine)
    }

    /// Homebrew's own uninstaller ran and brew.sh was followed again, both while
    /// Settings was closed. The Cellar is new; the rows must be.
    func testAReinstalledBrewIsNotDrawnWithTheOldCellar() async {
        let locator = MovingLocator(path: "/usr/local/bin/brew")
        let (model, engine) = page(locator, PerBrewCellar())
        defer { _ = engine }

        await model.loadIfNeeded()
        XCTAssertEqual(model.installed.map(\.name), ["curl"], "precondition: the old Cellar loaded")

        locator.path = nil
        await model.loadIfNeeded()          // the visit that finds brew gone
        locator.path = "/opt/homebrew/bin/brew"
        await model.loadIfNeeded()          // …and the one that finds it back

        XCTAssertEqual(model.installed.map(\.name), ["wget"], """
            the page is listing the packages of a Homebrew that no longer \
            exists, each row with an Uninstall button the engine will refuse
            """)
    }

    /// The guard itself, and it must survive: the same brew on a second visit
    /// costs no `brew list` at all.
    func testAnUnchangedBrewStillCostsNothingOnASecondVisit() async {
        let locator = MovingLocator(path: "/opt/homebrew/bin/brew")
        let runner = PerBrewCellar()
        let (model, engine) = page(locator, runner)
        defer { _ = engine }

        await model.loadIfNeeded()
        XCTAssertEqual(runner.listCalls, 2, "precondition: one `list` per kind on first open")

        await model.loadIfNeeded()

        XCTAssertEqual(runner.listCalls, 2,
                       "the return visit re-read an unchanged Cellar")
    }
}
