import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// An answer that arrives after the press it belonged to is over says nothing.
///
/// The press is asynchronous and nothing on the page is disabled while the query
/// is out — the page's own `disabled` tracks long operations, not queries. So two
/// presses put two queries in flight, and with no token the last continuation to
/// resume wins: cancel the dialog that opened for the second package and the
/// first one's answer raises a dialog nobody asked for, over the app's only
/// irreversible deletion; or the title and the list swap under someone reading
/// them. `LatestRequest` is what `search(_:)` in the same view model already
/// uses, for the reason written out there.
private final class ParkedUsesRunner: ProcessRunner, @unchecked Sendable {
    /// Fulfilled on the runner's own thread the moment the parked query is
    /// inside the tool, so the test knows it is in flight rather than hoping.
    let parked = XCTestExpectation(description: "the first query reached brew")
    private let held = DispatchSemaphore(value: 0)
    private let park: String
    /// Written once before any run and read-only afterwards, which is what
    /// makes concurrent runs safe here without a lock.
    private let answers: [String: String]

    init(park: String, answers: [String: String]) {
        self.park = park
        self.answers = answers
    }

    /// Lets the parked query answer at last. A real semaphore and not a
    /// cooperative yield: a yield buys a turn on the pool and no wall-clock
    /// time, so it cannot hold one query open across another.
    func release() { held.signal() }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        guard args.first == "uses", let name = args.last else { return (0, "") }
        if name == park {
            parked.fulfill()
            held.wait()
        }
        return (0, answers[name] ?? "")
    }

    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

@MainActor
final class ALateReadingCannotRaiseADialogTests: XCTestCase {

    private func pair(_ runner: ProcessRunner) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        return (engine, HomebrewViewModel(vm: ModuleViewModel(transport: engine.transport)))
    }

    private var parked: BrewPackage {
        BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false)
    }
    private var pressedSecond: BrewPackage {
        BrewPackage(name: "yt-dlp", version: "2026.9.1", isCask: false)
    }

    /// Two rows pressed one after the other while the first query is still out:
    /// the dialog on screen belongs to the second press, and the first press's
    /// names must not land in it.
    func testALateAnswerDoesNotOverwriteTheDialogOnScreen() async {
        let runner = ParkedUsesRunner(park: "openssl@3",
                                      answers: ["openssl@3": "aria2\nnode\n"])
        let (engine, vm) = pair(runner)
        let first = Task { await vm.askToUninstall(parked) }
        await fulfillment(of: [runner.parked], timeout: 5)
        await vm.askToUninstall(pressedSecond)
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp", "the second press never landed")
        runner.release()
        await first.value
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp",
                       "a late answer moved the dialog onto a package nobody is being asked about")
        XCTAssertEqual(vm.dependentsOfPending, [],
                       "the dialog on screen drew another package's dependents")
        withExtendedLifetime(engine) {}
    }

    /// The same two presses, and then the person closes the dialog. Nothing is
    /// on screen and nothing may put anything there: a confirmation for an
    /// irreversible deletion that opens by itself is the worst shape this can
    /// take.
    func testALateAnswerDoesNotReopenAClosedDialog() async {
        let runner = ParkedUsesRunner(park: "openssl@3",
                                      answers: ["openssl@3": "aria2\nnode\n"])
        let (engine, vm) = pair(runner)
        let first = Task { await vm.askToUninstall(parked) }
        await fulfillment(of: [runner.parked], timeout: 5)
        await vm.askToUninstall(pressedSecond)
        vm.cancelUninstall()
        runner.release()
        await first.value
        XCTAssertNil(vm.pendingUninstall,
                     "a query nobody was waiting for raised a confirmation dialog by itself")
        XCTAssertEqual(vm.dependentsOfPending, [])
        withExtendedLifetime(engine) {}
    }
}
