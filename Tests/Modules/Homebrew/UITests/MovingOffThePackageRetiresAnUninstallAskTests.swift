import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Moving off the package must retire an uninstall ask that is still out.**
///
/// The third file in this family, and the one that covers the gestures the
/// other two do not. `ALateReadingCannotRaiseADialogTests` retires an ask with
/// a second press and with a cancel; `LeavingThePageRetiresAnUninstallAskTests`
/// retires it by unmounting the page. All three exist for one sentence: «a
/// confirmation for an irreversible deletion that opens by itself is the worst
/// shape this can take».
///
/// `askToUninstall` is asynchronous, and the `brew uses --installed` behind it
/// can be out for the whole query deadline — `defaultQueryTimeout` in
/// `Sources/Modules/Homebrew/Engine/SystemPorts.swift`, 90 s, reached whenever
/// another `brew` holds the lock. In that window the person can move off the
/// package three ways without pressing Cancel and without leaving the page:
///
/// - **Back** on the narrow screen, which is `select(nil)`;
/// - **another row**, which is `List(selection:)`'s setter, `select(id)`;
/// - **another segment**, which is the segmented picker writing `segment`.
///
/// None of the three is a second press and none is a cancel, so `LatestRequest`
/// does not cover them; none unmounts the page, so `.onDisappear` does not
/// either. The answer landed afterwards and raised the modal confirmation over
/// whatever the person had moved to — a list, a different package, a different
/// segment.
///
/// The subject of the ask is the *pair* `(segment, selection[segment])`: it is
/// raised from the package `packageDetail` is drawing, and `packageDetail`
/// reads both. So both fields retire it, which is two write points rather than
/// three gestures — the picker's binding writes `segment` and never goes
/// through `select(_:)`.
private final class ParkedUsesRunner: ProcessRunner, @unchecked Sendable {
    /// Fulfilled on the runner's own thread the moment the parked query is
    /// inside the tool, so the test knows it is in flight rather than hoping.
    let parked = XCTestExpectation(description: "the query reached brew")
    private let held = DispatchSemaphore(value: 0)
    private let park: String
    private let answers: [String: String]

    init(park: String, answers: [String: String]) {
        self.park = park
        self.answers = answers
    }

    /// A real semaphore and not a cooperative yield, for the reason the two
    /// sibling files give: a yield buys a turn on the pool and no wall-clock
    /// time, so it cannot hold a query open across the gesture under test.
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
final class MovingOffThePackageRetiresAnUninstallAskTests: XCTestCase {

    private func pair(_ runner: ProcessRunner) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        return (engine, HomebrewViewModel(vm: ModuleViewModel(transport: engine.transport)))
    }

    private var pressed: BrewPackage {
        BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false)
    }
    private var neighbour: BrewPackage {
        BrewPackage(name: "yt-dlp", version: "2026.9.1", isCask: false)
    }

    /// Selects the pressed package, puts the ask in flight and waits until the
    /// query is inside the tool. The caller then makes its gesture and calls
    /// `release`.
    private func askInFlight(_ vm: HomebrewViewModel,
                             _ runner: ParkedUsesRunner) async -> Task<Void, Never> {
        vm.select(pressed.id)
        let ask = Task { await vm.askToUninstall(pressed) }
        await fulfillment(of: [runner.parked], timeout: 5)
        XCTAssertNil(vm.pendingUninstall, "the ask landed before the gesture — nothing was in flight")
        return ask
    }

    private func runner() -> ParkedUsesRunner {
        ParkedUsesRunner(park: "openssl@3", answers: ["openssl@3": "aria2\nnode\n"])
    }

    // MARK: - The ask does land when nothing moves

    /// Assert the subject happened before asserting an absence: without this
    /// the three cases below would pass against an `askToUninstall` that raises
    /// nothing at all, which is the default in a test process the moment
    /// anything upstream of the query stops answering.
    func testTheAskStillLandsWhenTheSelectionDoesNotMove() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)
        runner.release()
        await ask.value
        XCTAssertEqual(vm.pendingUninstall?.name, "openssl@3",
                       "the confirmation this file is about never opens — the three cases below "
                       + "would then prove nothing")
        XCTAssertEqual(vm.dependentsOfPending, ["aria2", "node"])
        withExtendedLifetime(engine) {}
    }

    // MARK: - The three gestures

    /// Back on the narrow screen: `backBar` calls `select(nil)` and nothing
    /// else. The list comes up, and the answer must not put a confirmation
    /// over it.
    func testBackRetiresTheAsk() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)

        vm.select(nil)

        runner.release()
        await ask.value
        XCTAssertNil(vm.pendingUninstall,
                     "pressing Back left the query out, and its answer raised a confirmation for "
                     + "the app's only irreversible deletion over the package list")
        XCTAssertEqual(vm.dependentsOfPending, [])
        withExtendedLifetime(engine) {}
    }

    /// Another row: `List(selection:)`'s setter, the same door a click on any
    /// neighbouring row goes through. The screen is describing yt-dlp and the
    /// dialog would offer to delete openssl@3.
    func testSelectingAnotherPackageRetiresTheAsk() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)

        vm.select(neighbour.id)

        runner.release()
        await ask.value
        XCTAssertNil(vm.pendingUninstall,
                     "a confirmation for openssl@3 opened over a page describing yt-dlp")
        XCTAssertEqual(vm.dependentsOfPending, [])
        withExtendedLifetime(engine) {}
    }

    /// Another segment: the segmented picker writes `segment` through its own
    /// binding and never touches `select(_:)`, so this is the gesture a fix
    /// made at the selection setter alone does not close.
    func testSwitchingSegmentRetiresTheAsk() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)

        vm.segment = .updates

        runner.release()
        await ask.value
        XCTAssertNil(vm.pendingUninstall,
                     "a confirmation for a package in Installed opened over the Updates segment")
        XCTAssertEqual(vm.dependentsOfPending, [])
        withExtendedLifetime(engine) {}
    }

    // MARK: - What must not be retired

    /// A write that changes nothing is not a move. `List(selection:)` writes
    /// the id it already holds on an ordinary re-click, and retiring on every
    /// write would cancel an ask that is still about the package on screen.
    func testReselectingTheSamePackageKeepsTheAsk() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)

        vm.select(pressed.id)

        runner.release()
        await ask.value
        XCTAssertEqual(vm.pendingUninstall?.name, "openssl@3",
                       "a write of the selection's own value retired an ask about the package "
                       + "still on screen")
        withExtendedLifetime(engine) {}
    }
}
