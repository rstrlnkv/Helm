import XCTest
import HelmContract
import HelmUI
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// Opening the page enumerates the app folders once.
///
/// `listApps()` reads `/Applications`, `~/Applications` and both Setapp folders
/// and parses an `Info.plist` per bundle; `appSizes()` then called
/// `installedApps()` again to learn which bundles to measure — the same
/// listing, the same plists, seconds later, for a list the view model was
/// already holding. Two enumerations per visit, and the second one's answer was
/// thrown away except for its paths.
///
/// The list travels in the command payload instead. This counts calls rather
/// than timing them: a duration is a race, a call count is not.
@MainActor
final class AppListEnumeratedOnceTests: XCTestCase {

    private final class CountingLister: AppLister, @unchecked Sendable {
        private let lock = NSLock()
        private var listings = 0
        let apps: [InstalledApp]

        init(apps: [InstalledApp]) { self.apps = apps }

        var installedAppsCalls: Int { lock.lock(); defer { lock.unlock() }; return listings }

        func installedApps() -> [InstalledApp] {
            lock.lock(); listings += 1; lock.unlock()
            return apps
        }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] {
            Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0.path.count) })
        }
        func installedBundleIDs() -> Set<String> { Set(apps.map(\.bundleID)) }
        func isKnownToSystem(bundleID: String) -> Bool { false }
    }

    private struct SilentFS: FileSystemPort {
        func exists(_ url: URL) -> Bool { false }
        func size(_ url: URL) -> Int { 0 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }

    private struct SilentTrash: TrashPort {
        func trashItem(_ url: URL) -> TrashOutcome { .success }
    }

    private struct NothingRunning: RunningAppsPort {
        func isRunning(bundleID: String) -> Bool { false }
        func quit(bundleID: String, force: Bool) {}
    }

    private let installed = [
        InstalledApp(name: "Tool", bundleID: "com.acme.tool", path: "/Applications/Tool.app", sizeBytes: 0),
        InstalledApp(name: "Other", bundleID: "com.acme.other", path: "/Applications/Other.app", sizeBytes: 0),
    ]

    /// The engine wires its transport handler with `[weak self]`, so a test that
    /// keeps only the view model gets `Data()` back from every request and a
    /// count of zero — which looks like a pass for "enumerated once" read
    /// carelessly. It is held for the length of the test.
    private var engine: UninstallerEngine?

    private func page(_ lister: CountingLister) -> UninstallerViewModel {
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/x"),
                                       apps: lister, fs: SilentFS(), trash: SilentTrash(),
                                       running: NothingRunning())
        self.engine = engine
        return UninstallerViewModel(vm: ModuleViewModel(transport: engine.transport))
    }

    func testOnePageLoadEnumeratesTheAppFoldersOnce() async {
        let lister = CountingLister(apps: installed)
        let uvm = page(lister)

        await uvm.loadAppsIfNeeded()

        XCTAssertEqual(lister.installedAppsCalls, 1,
                       "the page enumerated every installed app twice for one visit")
    }

    /// And the sizes still arrive: passing the list in must not turn the
    /// measurement into a no-op that a call count alone would call a success.
    func testTheSizesStillReachTheList() async {
        let uvm = page(CountingLister(apps: installed))

        await uvm.loadAppsIfNeeded()

        XCTAssertEqual(uvm.apps.map(\.sizeBytes),
                       installed.map { $0.path.count },
                       "the sizes the engine measured never reached the rows")
    }
}
