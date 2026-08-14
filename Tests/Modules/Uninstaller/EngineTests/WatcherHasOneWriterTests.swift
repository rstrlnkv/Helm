import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// `UninstallerEngine` is `@unchecked Sendable`, and its one mutable field is
/// the trash `watcher`.
///
/// `activate()` and `deactivate()` write it from `ModuleHost`, which is
/// `@MainActor`. `setWatchingTrash` writes it too — through
/// `startWatchingTrashIfAsked` — and it is reached from the transport handler,
/// which `LocalTransport.send` runs on the *caller's* executor with no hop of
/// its own. Two writers on two threads, and the compiler was told to trust the
/// author. Keep Awake had the identical shape and fixed it by putting every
/// writer on the main actor.
///
/// **The assertion is which thread wrote, not what it wrote.** A test that
/// switched the offer from two tasks and compared the answer would pass with
/// the race present, because both writers write the same thing; the property
/// that makes `@unchecked Sendable` true is that only one executor ever touches
/// the field. The store is the seam that can see it: `setWatchingTrash` writes
/// the setting on its way to the watcher, so where that write lands is where
/// the watcher assignment lands.
final class WatcherHasOneWriterTests: XCTestCase {

    /// Notes the thread of every write, and hands reads back like any store.
    private final class ThreadNotingStore: KeyValueStore, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Any] = [:]
        private var threads: [String: Bool] = [:]

        func object(forKey key: String) -> Any? { lock.withLock { values[key] } }

        func set(_ value: Any?, forKey key: String) {
            lock.withLock {
                values[key] = value
                threads[key] = Thread.isMainThread
            }
        }

        /// nil when nothing was written under that key at all.
        func wroteOnMain(_ key: String) -> Bool? { lock.withLock { threads[key] } }
    }

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

    func testTheOfferSwitchWritesOnTheMainActorWhoeverSentTheCommand() async throws {
        let backing = ThreadNotingStore()
        let transport = LocalTransport()
        let engine = UninstallerEngine(
            home: URL(fileURLWithPath: NSTemporaryDirectory()),
            apps: NoApps(), fs: NoFiles(), trash: NoTrash(), running: NoRunning(),
            store: NamespacedStore(namespace: "uninstaller", backing: backing),
            transport: transport)

        // A command from off the main thread, which is the ordinary case: the
        // view model awaits `client.send` from wherever its task is running.
        let command = EngineCommand(name: UninstallerCommand.setWatchingTrash.rawValue,
                                    payload: try JSONEncoder().encode(true))
        try await Task.detached { _ = try await transport.send(command) }.value

        // The subject happened at all, first — an assertion about where a write
        // landed passes for free when there was no write.
        XCTAssertEqual(backing.object(forKey: "module.uninstaller.watchTrash") as? Bool, true,
                       "the command never reached the engine, so the rest asserts nothing")
        XCTAssertEqual(backing.wroteOnMain("module.uninstaller.watchTrash"), true,
                       "the watcher was replaced from a pool thread while `activate` and "
                       + "`deactivate` write it from the main actor")
        withExtendedLifetime(engine) {}
    }
}
