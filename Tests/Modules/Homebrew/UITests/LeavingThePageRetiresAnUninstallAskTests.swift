import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Leaving the page must retire an uninstall ask that is still out.**
///
/// `ALateReadingCannotRaiseADialogTests` says the sentence this file proves the
/// other half of: «a confirmation for an irreversible deletion that opens by
/// itself is the worst shape this can take». There it is a second press and a
/// cancel that retire the first query. Neither of those is the case here.
///
/// The press launches an unstructured `Task` that is not tied to the view's
/// lifetime, and the answer it waits for can take the whole query deadline —
/// `defaultQueryTimeout` in `Sources/Modules/Homebrew/Engine/SystemPorts.swift`,
/// 90 s, reached whenever another `brew` holds the lock. In that window the
/// person can switch modules in the sidebar or close the Settings window, and
/// both hosting controllers carry `.helmIdlesOffScreen()`, so either unmounts
/// the page.
///
/// `pendingUninstall` used to be the page's `@State` and died with the subtree.
/// It lives on `HomebrewViewModel` now, and `HomebrewViewModel.shared(vm:)`
/// caches that for the app's lifetime — so the answer lands on a live view model
/// with no page mounted, sets `pendingUninstall`, and nothing clears it. The
/// dialog's `isPresented` is derived from that property alone: the next visit to
/// Homebrew raises a confirmation nobody asked for, over a dependents reading
/// taken arbitrarily long ago.
///
/// `LatestRequest` does not cover this on its own. It retires work on a later
/// press and on a cancel; leaving the page is neither, and only the page knows
/// it has gone.
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

    /// A real semaphore and not a cooperative yield, for the reason the sibling
    /// file gives: a yield buys a turn on the pool and no wall-clock time, so it
    /// cannot hold a query open across the departure this test is about.
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
final class LeavingThePageRetiresAnUninstallAskTests: XCTestCase {

    // MARK: - The page is the only thing that knows it has gone

    /// The page it is a rule about, named once.
    private static let page = "Sources/Modules/Homebrew/UI/HomebrewSettingsPage.swift"

    /// A source scan, because the defect is invisible to anything that can be
    /// called: `onDisappear` is delivered by SwiftUI to a mounted subtree, and
    /// the view model below cannot tell a page that left from one that never
    /// drew. The behavioural half proves the mechanism the wiring leans on; this
    /// half proves the page is wired to it at all.
    ///
    /// Comments and the insides of string literals are blanked, so a doc comment
    /// that merely *says* the page retires the ask does not satisfy the check —
    /// which is exactly how this defect arrived.
    func testThePageRetiresThePendingAskWhenItDisappears() throws {
        let code = SwiftSource.code(try RepoSource.text(of: Self.page))
        // Assert the subject happened before asserting anything about it: a
        // page that no longer raises the ask would otherwise pass this by
        // having nothing to retire.
        XCTAssertTrue(code.contains("askToUninstall"),
                      "\(Self.page) no longer raises the uninstall ask — this rule is about a page that does")

        guard let start = code.range(of: ".onDisappear") else {
            return XCTFail("\(Self.page) never retires the uninstall ask it can leave in flight: "
                           + "the query outlives the subtree, so the answer raises a confirmation "
                           + "for an irreversible deletion on the next visit to Homebrew")
        }
        let tail = code[start.upperBound...]
        guard let close = tail.firstIndex(of: "}") else {
            return XCTFail("\(Self.page)'s .onDisappear closure has no end — the scan cannot read it")
        }
        XCTAssertTrue(tail[..<close].contains("cancelUninstall("),
                      ".onDisappear on \(Self.page) does not call cancelUninstall(), "
                      + "so an uninstall ask still out when the page unmounts stays out")
    }

    // MARK: - What the page's departure reaches

    private func pair(_ runner: ProcessRunner) -> (HomebrewEngine, HomebrewViewModel) {
        let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                    privileged: NoPrivileges(), user: "tester",
                                    marker: InMemoryOpMarker())
        return (engine, HomebrewViewModel(vm: ModuleViewModel(transport: engine.transport)))
    }

    /// One press, no second press and no cancel — the person simply leaves. The
    /// answer comes back to a view model that outlives the page and must find
    /// its request retired.
    func testAnAnswerArrivingAfterTheDepartureRaisesNothing() async {
        let runner = ParkedUsesRunner(park: "openssl@3",
                                      answers: ["openssl@3": "aria2\nnode\n"])
        let (engine, vm) = pair(runner)
        let pressed = BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false)
        let ask = Task { await vm.askToUninstall(pressed) }
        await fulfillment(of: [runner.parked], timeout: 5)

        // What `.onDisappear` does. The page is gone from here on.
        vm.cancelUninstall()

        runner.release()
        await ask.value
        XCTAssertNil(vm.pendingUninstall,
                     "an answer to a press whose page has gone raised a confirmation for the "
                     + "app's only irreversible deletion, on the next visit to Homebrew")
        XCTAssertEqual(vm.dependentsOfPending, [],
                       "the names read for a press nobody is waiting on were kept")
        withExtendedLifetime(engine) {}
    }
}
