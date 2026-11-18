import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// Stands for the installed-apps side of `AppCatalogPort`; `observers` counts the watches still held, and
/// `fire()` stands for the system saying something changed.
final class RigCatalog: AppCatalogPort, @unchecked Sendable {
    var reading: CatalogReading
    private let handlers = Locked<[Int: @Sendable () -> Void]>([:])
    private let next = Locked(0)

    init(_ ids: [String]) {
        reading = CatalogReading(apps: ids.map { CatalogApp(id: $0, name: $0.capitalized, path: "/Applications/\($0).app") }, complete: true)
    }

    private final class Token {
        let release: () -> Void
        init(_ release: @escaping () -> Void) { self.release = release }
        deinit { release() }
    }

    var observers: Int { handlers.withLock { $0.count } }
    func fire() { for handler in handlers.withLock({ Array($0.values) }) { handler() } }

    func read() -> CatalogReading { reading }
    func bundleID(atPath path: String) -> String? { reading.apps.first { $0.path == path }?.id }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        let key = next.withLock { $0 += 1; return $0 }
        handlers.withLock { $0[key] = onChange }
        return Token { [handlers] in handlers.withLock { _ = $0.removeValue(forKey: key) } }
    }
}

/// Stands for the system's way of opening an app: it opens nothing, answers what the test says. The real launcher is never built here.
final class RigLauncher: AppLauncherPort, @unchecked Sendable {
    func open(_ url: URL) async -> Bool { false }
}

/// The real engine over a fake catalog and a scratch layout folder, and the model on top of it.
@MainActor struct LaunchpadRig {
    let catalog: RigCatalog
    let store: LayoutStore
    let model: LaunchpadViewModel

    init(_ test: XCTestCase, apps: [String] = ["a", "b", "c"], label: String) {
        catalog = RigCatalog(apps)
        store = LayoutStore(directory: test.scratchDirectory(label))
        let engine = LaunchpadEngine(catalog: catalog, launcher: RigLauncher(), store: store)
        model = LaunchpadViewModel(work: engine, store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()))
    }

    /// An arrangement that is not alphabetical, saved as the person's.
    static let arranged = LaunchpadLayout(items: [.app("c"), .app("a"), .app("b")])
    static let alphabetical = LaunchpadLayout(items: [.app("a"), .app("b"), .app("c")])

    func arrange() { XCTAssertTrue(store.save(Self.arranged)) }
    var stored: LayoutRead { store.load() }
}
