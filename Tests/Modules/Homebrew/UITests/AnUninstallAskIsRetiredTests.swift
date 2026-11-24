import XCTest
import HelmContract
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

@MainActor
private func pair(_ runner: ProcessRunner) -> (HomebrewEngine, HomebrewViewModel) {
    let engine = HomebrewEngine(locator: FixedLocator(), runner: runner,
                                privileged: NoPrivileges(), user: "tester",
                                marker: InMemoryOpMarker())
    return (engine, HomebrewViewModel(work: engine))
}

/// An answer that arrives after the press it belonged to is over says nothing.
///
/// Nothing on the page is disabled while the query is out, so two presses put
/// two queries in flight. The first one's answer must not raise a dialog nobody
/// asked for over the app's only irreversible deletion, nor swap the title and
/// the list under someone reading them. `LatestRequest` retires it, as for
/// `search(_:)`.
@MainActor
final class ALateReadingCannotRaiseADialogTests: XCTestCase {

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
        let runner = FakeBrew(uses: ["openssl@3": "aria2\nnode\n"], park: "openssl@3")
        let (engine, vm) = pair(runner)
        let first = Task { await vm.askToUninstall(parked) }
        await fulfillment(of: [runner.parked], timeout: 5)
        await vm.askToUninstall(pressedSecond)
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp", "the second press never landed")
        runner.release()
        await first.value
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp",
                       "a late answer moved the dialog onto a package nobody is being asked about")
        XCTAssertEqual(vm.dependentsOfPending, .read([]),
                       "the dialog on screen drew another package's dependents")
        withExtendedLifetime(engine) {}
    }

    /// The same two presses, then the person closes the dialog: nothing may
    /// reopen a confirmation for an irreversible deletion by itself.
    func testALateAnswerDoesNotReopenAClosedDialog() async {
        let runner = FakeBrew(uses: ["openssl@3": "aria2\nnode\n"], park: "openssl@3")
        let (engine, vm) = pair(runner)
        let first = Task { await vm.askToUninstall(parked) }
        await fulfillment(of: [runner.parked], timeout: 5)
        await vm.askToUninstall(pressedSecond)
        vm.cancelUninstall()
        runner.release()
        await first.value
        XCTAssertNil(vm.pendingUninstall,
                     "a query nobody was waiting for raised a confirmation dialog by itself")
        XCTAssertEqual(vm.dependentsOfPending, .notAsked)
        withExtendedLifetime(engine) {}
    }
}

/// **Leaving the page must retire an uninstall ask that is still out.**
///
/// The press launches an unstructured `Task` not tied to the view, and the
/// answer can take the whole query deadline (`defaultQueryTimeout`) when another
/// `brew` holds the lock. Meanwhile the person can switch modules or close the
/// Settings window, and `.helmIdlesOffScreen()` unmounts the page.
///
/// `pendingUninstall` lives on `HomebrewViewModel`, which outlives the page, and
/// the dialog's `isPresented` is derived from it alone. An answer landing with no
/// page mounted must not leave it set, or the next visit raises a confirmation
/// nobody asked for over a stale dependents reading. `LatestRequest` retires
/// work on a later press and on a cancel; only the page knows it has gone.
@MainActor
final class LeavingThePageRetiresAnUninstallAskTests: XCTestCase {

    // MARK: - What the page's departure reaches

    /// One press, no second press and no cancel — the person simply leaves. The
    /// answer comes back to a view model that outlives the page and must find
    /// its request retired.
    func testAnAnswerArrivingAfterTheDepartureRaisesNothing() async {
        let runner = FakeBrew(uses: ["openssl@3": "aria2\nnode\n"], park: "openssl@3")
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
        XCTAssertEqual(vm.dependentsOfPending, .notAsked,
                       "the names read for a press nobody is waiting on were kept")
        withExtendedLifetime(engine) {}
    }
}

/// **Moving off the package must retire an uninstall ask that is still out.**
///
/// `askToUninstall` is asynchronous and its `brew uses --installed` can be out
/// for the whole query deadline. Meanwhile the person can move off the package
/// without pressing Cancel and without leaving the page:
///
/// - **deselecting** in the list, which is `select(nil)`;
/// - **another row**, which is `List(selection:)`'s setter, `select(id)`;
/// - **another segment**, which is the segmented picker writing `segment`.
///
/// None is a second press, a cancel or an unmount. The subject of the ask is the
/// *pair* `(segment, selection[segment])`, which `packageDetail` reads, so a
/// write to either field retires it; the picker's binding writes `segment` and
/// never goes through `select(_:)`.
@MainActor
final class MovingOffThePackageRetiresAnUninstallAskTests: XCTestCase {

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
                             _ runner: FakeBrew) async -> Task<Void, Never> {
        vm.select(pressed.id)
        let ask = Task { await vm.askToUninstall(pressed) }
        await fulfillment(of: [runner.parked], timeout: 5)
        XCTAssertNil(vm.pendingUninstall, "the ask landed before the gesture — nothing was in flight")
        return ask
    }

    private func runner() -> FakeBrew {
        FakeBrew(uses: ["openssl@3": "aria2\nnode\n"], park: "openssl@3")
    }

    // MARK: - The ask does land when nothing moves

    /// The subject happened: without this the cases below would pass against an
    /// `askToUninstall` that raises nothing at all.
    func testTheAskStillLandsWhenTheSelectionDoesNotMove() async {
        let runner = self.runner()
        let (engine, vm) = pair(runner)
        let ask = await askInFlight(vm, runner)
        runner.release()
        await ask.value
        XCTAssertEqual(vm.pendingUninstall?.name, "openssl@3",
                       "the confirmation this file is about never opens — the three cases below "
                       + "would then prove nothing")
        XCTAssertEqual(vm.dependentsOfPending, .read(["aria2", "node"]))
        withExtendedLifetime(engine) {}
    }

    // MARK: - The three gestures

    /// Each row is its own door, and a fresh runner, pair and ask are built for it.
    func testEveryGestureThatMovesOffThePackageRetiresTheAsk() async {
        let gestures: [(gesture: (HomebrewViewModel) -> Void, message: String)] = [
            // Deselecting the package: `select(nil)` and nothing else. The answer
            // must not put a confirmation over the empty inspector.
            ({ $0.select(nil) },
             "pressing Back left the query out, and its answer raised a confirmation for "
             + "the app's only irreversible deletion over the package list"),
            // Another row: `List(selection:)`'s setter, the same door a click on any
            // neighbouring row goes through. The screen is describing yt-dlp and the
            // dialog would offer to delete openssl@3.
            ({ [neighbour] in $0.select(neighbour.id) },
             "a confirmation for openssl@3 opened over a page describing yt-dlp"),
            // Another segment: the segmented picker writes `segment` through its own
            // binding and never touches `select(_:)`, so this is the gesture a fix
            // made at the selection setter alone does not close.
            ({ $0.segment = .updates },
             "a confirmation for a package in Installed opened over the Updates segment"),
        ]
        for (gesture, message) in gestures {
            let runner = self.runner()
            let (engine, vm) = pair(runner)
            let ask = await askInFlight(vm, runner)

            gesture(vm)

            runner.release()
            await ask.value
            XCTAssertNil(vm.pendingUninstall, message)
            XCTAssertEqual(vm.dependentsOfPending, .notAsked, message)
            withExtendedLifetime(engine) {}
        }
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

/// The reading is taken for the press it belongs to, and it does not outlive it.
///
/// Two packages asked one after the other: the second dialog never carries the
/// first one's dependents. Both doors to `brew uninstall` read the dependents
/// first and draw one note.
@MainActor
final class UninstallNamesWhatStillNeedsItTests: XCTestCase {

    func testTheDialogCarriesWhatTheEngineAnswered() async {
        let runner = FakeBrew(uses: ["openssl@3": "aria2\nnode\n"])
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        XCTAssertEqual(vm.pendingUninstall?.name, "openssl@3")
        XCTAssertEqual(vm.dependentsOfPending, .read(["aria2", "node"]))
        // Last, not first: it keeps the engine alive up to here, and the
        // statement form guarantees nothing past its own return.
        withExtendedLifetime(engine) {}
    }

    func testTheNextPackageDoesNotInheritTheLastOnesDependents() async {
        let runner = FakeBrew(uses: ["openssl@3": "aria2\nnode\n"])
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        vm.cancelUninstall()
        await vm.askToUninstall(BrewPackage(name: "yt-dlp", version: "2026.9.1", isCask: false))
        XCTAssertEqual(vm.pendingUninstall?.name, "yt-dlp")
        XCTAssertEqual(vm.dependentsOfPending, .read([]),
                       "the second dialog offered the first package's dependents")
        withExtendedLifetime(engine) {}
    }

    func testCancellingClearsTheReading() async {
        let runner = FakeBrew(uses: ["openssl@3": "aria2\n"])
        let (engine, vm) = pair(runner)
        await vm.askToUninstall(BrewPackage(name: "openssl@3", version: "3.5.0", isCask: false))
        vm.cancelUninstall()
        XCTAssertNil(vm.pendingUninstall)
        XCTAssertEqual(vm.dependentsOfPending, .notAsked)
        withExtendedLifetime(engine) {}
    }
}
