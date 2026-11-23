import Foundation
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// Stands for the installed-apps side of `AppCatalogPort`, whose duplicate ids collapse to one entry; a test sets what the next read answers.
/// `bundleIDs` is what the bundle at each path answers, kept apart from `reading` so a test can make them disagree;
/// `fire()` stands for the system saying something changed, and reaches only the observers still held.
final class FakeAppCatalog: AppCatalogPort, @unchecked Sendable {
    var reading: CatalogReading { didSet { bundleIDs = Dictionary(reading.apps.map { ($0.path, $0.id) }, uniquingKeysWith: { a, _ in a }) } }
    var bundleIDs: [String: String]
    private let handlers = Locked<[Int: @Sendable () -> Void]>([:])
    private let next = Locked(0)

    init(_ ids: [String] = [], complete: Bool = true) {
        var seen = Set<String>()
        let reading = CatalogReading(apps: ids.filter { seen.insert($0).inserted }.map { CatalogApp(id: $0, name: $0.capitalized, path: "/Applications/\($0).app") },
                                     complete: complete)
        self.reading = reading
        bundleIDs = Dictionary(reading.apps.map { ($0.path, $0.id) }, uniquingKeysWith: { a, _ in a })
    }

    private final class Token {
        let release: () -> Void
        init(_ release: @escaping () -> Void) { self.release = release }
        deinit { release() }
    }

    /// How many observers are held right now.
    var observers: Int { handlers.withLock { $0.count } }

    func fire() { for handler in handlers.withLock({ Array($0.values) }) { handler() } }
}

extension FakeAppCatalog {
    func read(reason: CatalogReadReason) -> CatalogReading { reading }
    func bundleID(atPath path: String) -> String? { bundleIDs[path] }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        let key = next.withLock { $0 += 1; return $0 }
        handlers.withLock { $0[key] = onChange }
        return Token { [handlers] in handlers.withLock { _ = $0.removeValue(forKey: key) } }
    }
}

/// Stands for the system's way of opening an application: answers what the test says and records the URL it was asked for.
final class FakeAppLauncher: AppLauncherPort, @unchecked Sendable {
    private let log = Locked<[URL]>([])
    var answer = true
    var opened: [URL] { log.value }
    func open(_ url: URL) async -> Bool {
        log.withLock { $0.append(url) }
        return answer
    }
}
