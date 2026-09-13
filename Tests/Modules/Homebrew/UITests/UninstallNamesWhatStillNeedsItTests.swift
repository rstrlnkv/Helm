import XCTest
import HelmContract
import HelmRuntime
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// The reading is taken for the press it belongs to, and it does not outlive it.
///
/// Two packages, asked one after the other: the second dialog must never carry
/// the first one's dependents. This is the stored-reading question the tree asks
/// everywhere — what happened between the reading and the act — and here the act
/// is a person reading a sentence and deciding.
private final class UsesRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    var answers: [String: String] = [:]

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); defer { lock.unlock() }
        guard args.first == "uses", let name = args.last else { return (0, "") }
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
final class UninstallNamesWhatStillNeedsItTests: XCTestCase {

    private func pair(_ runner: ProcessRunner) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        return (engine, HomebrewViewModel(vm: ModuleViewModel(transport: engine.transport)))
    }

    func testTheDialogCarriesWhatTheEngineAnswered() async {
        let runner = UsesRunner()
        runner.answers["openssl@3"] = "aria2\nnode\n"
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        XCTAssertEqual(vm.pendingUninstall?.name, "openssl@3")
        XCTAssertEqual(vm.dependentsOfPending, ["aria2", "node"])
        // Last, not first: it keeps the engine alive up to here, and the
        // statement form guarantees nothing past its own return.
        withExtendedLifetime(engine) {}
    }

    func testTheNextPackageDoesNotInheritTheLastOnesDependents() async {
        let runner = UsesRunner()
        runner.answers["openssl@3"] = "aria2\nnode\n"
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        vm.cancelUninstall()
        await vm.askToUninstall(BrewPackage(name: "yt-dlp", version: "2026.9.1", isCask: false))
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp")
        XCTAssertEqual(vm.dependentsOfPending, [],
                       "the second dialog offered the first package's dependents")
        withExtendedLifetime(engine) {}
    }

    func testCancellingClearsTheReading() async {
        let runner = UsesRunner()
        runner.answers["openssl@3"] = "aria2\n"
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        vm.cancelUninstall()
        XCTAssertNil(vm.pendingUninstall)
        XCTAssertEqual(vm.dependentsOfPending, [])
        withExtendedLifetime(engine) {}
    }
}
