import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// A selection is a claim about a list, and the list moves under it.
///
/// `brew uninstall` in a terminal, an upgrade finishing, a second search — each
/// replaces a list this page is holding a selection into. A selection that
/// survives its own package is an inspector describing something that is no
/// longer installed, with buttons that act on it.
///
/// The other half is that the three segments do not share one selection: the
/// package you were reading in Установленные is not the hit you were reading in
/// Поиск, and coming back to a segment should find what you left there.
private final class QuietRunner: ProcessRunner, @unchecked Sendable {
    var installed = "wget 1.25.0\nopenssl@3 3.6.4\n"

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        guard args.first == "list" else { return (0, "") }
        return args.contains("--formula") ? (0, installed) : (0, "")
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
final class ASelectionDoesNotOutliveItsPackageTests: XCTestCase {

    private func pair(_ runner: QuietRunner) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        return (engine, HomebrewViewModel(vm: ModuleViewModel(transport: engine.transport)))
    }

    func testASelectedPackageThatLeavesTheListIsDeselected() async {
        let runner = QuietRunner()
        let (engine, vm) = pair(runner)
        await vm.refreshInstalled()
        vm.select(BrewKey.of(name: "openssl@3", isCask: false))
        XCTAssertNotNil(vm.selected)

        runner.installed = "wget 1.25.0\n"          // somebody uninstalled it in a terminal
        await vm.refreshInstalled()
        XCTAssertNil(vm.selected, "the inspector was left describing a package that is gone")
        withExtendedLifetime(engine) {}
    }

    func testASelectionThatStillExistsSurvivesTheRefresh() async {
        let runner = QuietRunner()
        let (engine, vm) = pair(runner)
        await vm.refreshInstalled()
        vm.select(BrewKey.of(name: "openssl@3", isCask: false))

        runner.installed = "openssl@3 3.6.4\nwget 1.25.0\n"   // same set, different order
        await vm.refreshInstalled()
        XCTAssertEqual(vm.selected, BrewKey.of(name: "openssl@3", isCask: false))
        withExtendedLifetime(engine) {}
    }

    func testEachSegmentKeepsItsOwnSelection() async {
        let runner = QuietRunner()
        let (engine, vm) = pair(runner)
        await vm.refreshInstalled()
        vm.select(BrewKey.of(name: "openssl@3", isCask: false))

        vm.segment = .search
        XCTAssertNil(vm.selected, "the search segment inherited the installed segment's selection")
        vm.select(BrewKey.of(name: "helm", isCask: false))

        vm.segment = .installed
        XCTAssertEqual(vm.selected, BrewKey.of(name: "openssl@3", isCask: false),
                       "coming back to a segment lost what was selected there")
        withExtendedLifetime(engine) {}
    }

    /// `List(selection:)` writes `nil` when a click lands in the empty space
    /// below the rows — the setter has to take that, or a deselect there
    /// leaves the last id standing for ever.
    func testSelectingNilClearsTheSegment() async {
        let runner = QuietRunner()
        let (engine, vm) = pair(runner)
        await vm.refreshInstalled()
        vm.select(BrewKey.of(name: "openssl@3", isCask: false))
        vm.select(nil)
        XCTAssertNil(vm.selected)
        withExtendedLifetime(engine) {}
    }
}
