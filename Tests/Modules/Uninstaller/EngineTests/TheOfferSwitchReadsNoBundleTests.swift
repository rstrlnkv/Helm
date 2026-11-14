import Foundation
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// The press that switches the offer on asks one question of the Trash, whether
/// it can be read, and answers it without opening a bundle: `setWatchingTrash`
/// runs on main, and `trashedApps()` reads an `Info.plist` per bundle.
final class TheOfferSwitchReadsNoBundleTests: XCTestCase {

    private final class Counting: AppLister, @unchecked Sendable {
        private let lock = NSLock()
        private var listed = 0
        private var asked = 0
        func installedApps() -> [InstalledApp] { [] }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { [] }
        func isKnownToSystem(bundleID: String) -> Bool { false }
        func trashedApps() -> [TrashedApp]? {
            lock.lock(); listed += 1; lock.unlock(); return []
        }
        func trashIsReadable() -> Bool {
            lock.lock(); asked += 1; lock.unlock(); return true
        }
        var listedCount: Int { lock.lock(); defer { lock.unlock() }; return listed }
        var askedCount: Int { lock.lock(); defer { lock.unlock() }; return asked }
    }

    func testThePressAsksWhetherTheTrashIsReadableAndListsNoBundle() {
        let lister = Counting()
        let store = NamespacedStore(namespace: "uninstaller", backing: InMemoryKeyValueStore())
        let engine = UninstallerEngine(home: URL(fileURLWithPath: "/Users/ann"),
                                       apps: lister, fs: FakeFS(existing: [:]),
                                       trash: NoTrash(), running: NoRunning(), store: store)

        engine.setWatchingTrash(true)

        XCTAssertEqual(lister.askedCount, 1, "precondition: the switch asked the cheap question")
        XCTAssertEqual(lister.listedCount, 0,
                       "the press listed the Trash's bundles on the main thread")
    }
}
