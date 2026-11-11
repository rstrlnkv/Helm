import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// Switching the offer on has to act now, and nothing held it.
///
/// `setWatchingTrash` writes the setting, starts the watcher, and calls
/// `trashChanged` — which is what makes the host sweep. Its own doc comment says
/// why: "the person just asked to be told about apps in the Trash, and the ones
/// already sitting there are the first thing they meant". CLAUDE.md puts the
/// general form of it more bluntly — a setting that only takes effect at the
/// next launch is one people report as broken.
///
/// The failure is silent and looks like nothing at all. The switch goes on, the
/// setting is stored, the watcher starts, and the apps already in the Trash are
/// simply not mentioned until something else happens to trigger a sweep. Both
/// halves of the contract were untested: `setWatchingTrash` had no test at all,
/// and the signal it sends crosses into `HelmApp`, which cannot import this
/// target to check.
final class TheOfferSwitchTakesEffectNowTests: XCTestCase {

    private struct NoApps: AppLister {
        func installedApps() -> [InstalledApp] { [] }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { [] }
        func isKnownToSystem(bundleID: String) -> Bool { false }
        func trashedApps() -> [TrashedApp]? { [] }
    }

    private struct NoFiles: FileSystemPort {
        func exists(_ url: URL) -> Bool { false }
        func size(_ url: URL) -> Int { 0 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }

    /// How many times the engine said "look again".
    private final class Told: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        func tell() { lock.lock(); stored += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private func engine(watching: Bool, told: Told) -> (UninstallerEngine, NamespacedStore) {
        let store = NamespacedStore(namespace: "uninstaller", backing: InMemoryKeyValueStore())
        store.set(watching, for: "watchTrash")
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/ann"),
                                       apps: NoApps(), fs: NoFiles(), trash: NoTrash(),
                                       running: NoRunning(), store: store,
                                       trashChanged: { told.tell() })
        return (engine, store)
    }

    func testTurningTheOfferOnAsksTheHostToSweepAtOnce() {
        let told = Told()
        let (engine, _) = engine(watching: false, told: told)

        engine.setWatchingTrash(true)

        XCTAssertEqual(told.count, 1,
                       "the switch went on and nothing asked the host to look — the apps "
                       + "already in the Trash stay unmentioned until the next launch")
    }

    /// Off is not a request to look at anything, so it must stay quiet.
    func testTurningTheOfferOffAsksForNothing() {
        let told = Told()
        let (engine, _) = engine(watching: true, told: told)

        engine.setWatchingTrash(false)

        XCTAssertEqual(told.count, 0, "switching the offer off asked the host to sweep")
    }

    /// Setting it to what it already is changes nothing — the guard at the top
    /// of `setWatchingTrash`. Without it, every visit to the page that writes
    /// the switch back would put a window in front of somebody.
    func testSettingItToWhatItAlreadyIsEmitsNothing() {
        let told = Told()
        let (engine, _) = engine(watching: true, told: told)

        engine.setWatchingTrash(true)

        XCTAssertEqual(told.count, 0, "a switch that was already on asked for a sweep anyway")
    }

    /// And the answer outlives the call: the setting is what the next launch
    /// reads, and what `trashedAppLeftovers` consults before offering anything.
    func testTheSwitchIsRemembered() async {
        let (engine, store) = engine(watching: false, told: Told())

        engine.setWatchingTrash(true)

        XCTAssertTrue(store.bool("watchTrash", default: false))
        let offered = await engine.trashedAppLeftovers()
        XCTAssertTrue(offered.isEmpty, "nothing is in this fixture's Trash to offer")
    }
}
