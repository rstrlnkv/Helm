import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **`loadedStatus` is a local flag standing in for a live external fact.**
///
///     public func loadIfNeeded() async {
///         guard !loadedStatus else { return }
///
/// Whether Homebrew is installed is not a property of this process. It is a
/// file on disk that `FSBrewLocator` re-reads on every call, and it changes
/// under the app for the most ordinary reasons there are: somebody follows
/// brew.sh in a terminal, or runs Homebrew's own uninstaller, with Helm's
/// window open beside it. `HomebrewSettingsPage.body` branches on
/// `status.installed` and on nothing else, so the whole page is downstream of
/// this one boolean.
///
/// The flag is written by the first `refreshStatus` and never cleared, and
/// nothing else on the page asks the question again: the Refresh button calls
/// `refresh(_:)`, which reloads a *list*; the segment picker the same. The only
/// path that re-reads the status is `refreshAfterOp`, which needs an operation
/// to have run — and the operation you cannot run is the one on the install
/// screen you are stuck on. So brew appearing is noticed never, and brew
/// vanishing is noticed never, for the life of the process. The family CLAUDE.md
/// names on 2026-08-12: a local flag against a live fact, with no reverse
/// channel from the port that knows.
///
/// **The locator fake has to be able to move**, or none of this is
/// representable. Every `BrewLocator` in this suite is a `FixedLocator`
/// answering one constant path for ever — simpler than the port it stands for,
/// which answers `FileManager.isExecutableFile` afresh at every call.
@MainActor
final class BrewComingAndGoingIsNoticedTests: XCTestCase {

    // MARK: - Fakes

    /// brew as it really is: a path that may or may not be there *this time*.
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

    /// Answers the two `list` calls and counts them, so a test can say what a
    /// second visit to the page cost.
    private final class CountingBrew: ProcessRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return _calls }
        var listCalls: Int { calls.filter { $0.first == "list" }.count }

        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) {
            lock.lock(); _calls.append(args); lock.unlock()
            guard args.first == "list", args.contains("--formula") else { return (0, "") }
            return (0, "wget 1.25.0\n")
        }

        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            NoProcess()
        }
    }

    /// The engine has to outlive the call: it wires the transport handler with
    /// `[weak self]`, so a dropped engine answers zero bytes to everything.
    private func page(_ locator: MovingLocator, _ runner: CountingBrew)
    -> (HomebrewViewModel, HomebrewEngine) {
        let transport = LocalTransport()
        let engine = HomebrewEngine(locator: locator, runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    transport: transport, marker: InMemoryOpMarker())
        return (HomebrewViewModel(vm: ModuleViewModel(transport: transport)), engine)
    }

    // MARK: - The fact moves

    /// Somebody installs Homebrew in a terminal while the page sits on its
    /// "Homebrew is not installed" screen. Returning to the page — the `.task`
    /// runs again, because leaving Settings tears the subtree down — must show
    /// the manager, not the install screen for the rest of the app's life.
    func testBrewInstalledInATerminalIsNoticedOnTheNextVisit() async {
        let locator = MovingLocator(path: nil)
        let (model, engine) = page(locator, CountingBrew())
        defer { _ = engine }

        await model.loadIfNeeded()
        XCTAssertFalse(model.status.installed, "precondition: the page opened with no brew")

        locator.path = "/opt/homebrew/bin/brew"
        await model.loadIfNeeded()

        XCTAssertTrue(model.status.installed, """
            Homebrew was installed while the page was open and the module never \
            looked again: the install screen is now the only thing this module \
            can draw until the app is restarted
            """)
    }

    /// And the other direction, which is the one that offers buttons that
    /// cannot work: Homebrew's own uninstaller ran, and the page is still
    /// listing packages with Uninstall and Upgrade beside them.
    func testBrewRemovedInATerminalIsNoticedOnTheNextVisit() async {
        let locator = MovingLocator(path: "/opt/homebrew/bin/brew")
        let (model, engine) = page(locator, CountingBrew())
        defer { _ = engine }

        await model.loadIfNeeded()
        XCTAssertTrue(model.status.installed, "precondition: the page opened with brew present")

        locator.path = nil
        await model.loadIfNeeded()

        XCTAssertFalse(model.status.installed, """
            Homebrew was uninstalled while the page was open and the module still \
            says it is installed — the rows keep their Uninstall buttons and every \
            press is refused by an engine that knows better
            """)
    }

    // MARK: - The control

    /// What the guard exists for, and it must survive the fix: the *expensive*
    /// half — `brew list --versions` twice plus a `brew desc` batch over every
    /// package — is not paid again on a return visit. Asking the locator is two
    /// `isExecutableFile` calls; asking brew is seconds.
    func testASecondVisitDoesNotPayForTheInstalledListAgain() async {
        let locator = MovingLocator(path: "/opt/homebrew/bin/brew")
        let runner = CountingBrew()
        let (model, engine) = page(locator, runner)
        defer { _ = engine }

        await model.loadIfNeeded()
        XCTAssertEqual(runner.listCalls, 2, "precondition: one `list` per kind on first open")

        await model.loadIfNeeded()

        XCTAssertEqual(runner.listCalls, 2, """
            the return visit ran `brew list --versions` again over an unchanged \
            machine — the reason `loadIfNeeded` has a guard at all
            """)
    }
}
