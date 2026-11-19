import Foundation
import HelmContract
import HelmRuntime

/// The app launcher's arrangement: what is installed, what the person put where, what they hid.
///
/// **Synchronous and blocking on disk** — a model hops with `offTheCooperativePool`. One lock
/// covers read, reconcile, edit and save, taken inside one synchronous call and never held
/// across a suspension. The layout is never cached: every `read()` asks the catalog and the file again;
/// only the latest catalog read is kept, so an edit reconciles against what the person saw.
public final class LaunchpadEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down. **The string never changes.**
    public static let moduleID = "launchpad"

    private let catalog: AppCatalogPort
    private let launcher: AppLauncherPort
    private let store: LayoutStore
    /// The localized name of the default arrangement's folder of utilities, asked when a default is built: the engine holds no strings.
    private let utilitiesFolderName: @Sendable () -> String
    private let lock = NSLock()
    /// The latest catalog read, so an edit reconciles against what the person was looking at.
    private var lastCatalog: CatalogReading?

    public convenience init(utilitiesFolderName: @escaping @Sendable () -> String) {
        self.init(catalog: FileSystemAppCatalog(), launcher: SystemAppLauncher(), store: LayoutStore(), utilitiesFolderName: utilitiesFolderName)
    }

    init(catalog: AppCatalogPort, launcher: AppLauncherPort, store: LayoutStore, utilitiesFolderName: @escaping @Sendable () -> String = { "Utilities" }) {
        self.catalog = catalog
        self.launcher = launcher
        self.store = store
        self.utilitiesFolderName = utilitiesFolderName
    }

    public func activate() {}
    public func deactivate() {}

    /// Reconciled in memory; writes nothing.
    public func read() -> LaunchpadSnapshot {
        lock.lock(); defer { lock.unlock() }
        let reading = catalog.read()
        lastCatalog = reading
        return snapshot(reading, stored: store.load(), layout: nil, saved: true)
    }

    /// nil = refused (a vanished id, an empty name): nothing written, one line in the log without a name. Otherwise the new
    /// snapshot, with `saved` false when the write did not land — the result is still returned.
    public func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        let reading = lastCatalog ?? catalog.read()
        lastCatalog = reading
        let stored = store.load()
        let base = storedLayout(of: stored, reading).reconciled(catalog: reading.apps.map(\.id), complete: reading.complete)
        // Reconciled again so an edit that empties the arrangement (a reset) returns the apps in catalog order, as a read would.
        var applied = base.applying(edit)
        if edit == .resetArrangement { applied?.items = defaultArrangement(reading).items }
        guard let edited = applied?.reconciled(catalog: reading.apps.map(\.id), complete: reading.complete) else {
            HelmLog.shared.info(Self.moduleID, "an arrangement edit was refused")
            return nil
        }
        let saved = (stored != .unreadable || store.moveUnreadableAside()) && store.save(edited)
        return snapshot(reading, stored: saved ? .loaded(edited) : stored, layout: edited, saved: saved)
    }

    public func hide(_ id: AppID) -> LaunchpadSnapshot? { apply(.hide(id)) }
    public func unhide(_ id: AppID) -> LaunchpadSnapshot? { apply(.unhide(id)) }
    /// Folders and order go back to the default arrangement; hidden apps stay hidden. Never refused.
    public func resetArrangement() -> LaunchpadSnapshot? { apply(.resetArrangement) }

    /// Calls `onChange` when the installed apps may have changed, until the token is let go.
    /// The engine holds nothing: the token's lifetime is the caller's.
    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        catalog.observeChanges(onChange)
    }

    /// Opens the app with this id **if a fresh read still finds it** and the bundle at its path
    /// still answers the id. The read does not become `lastCatalog`: it is for this launch only.
    /// Blocking disk work goes off the cooperative pool and no lock is held across a suspension.
    public func launch(_ id: AppID) async -> LaunchOutcome {
        let catalog = self.catalog
        let resolution = await offTheCooperativePool {
            LaunchResolution.resolve(id: id, reading: catalog.read(), bundleID: { catalog.bundleID(atPath: $0) })
        }
        switch resolution {
        case .gone:
            HelmLog.shared.info(Self.moduleID, "a launch was refused: the app is no longer installed")
            return .gone
        case .unreadable:
            HelmLog.shared.info(Self.moduleID, "a launch was refused: the app was not among those that could be read")
            return .unreadable
        case .open(let url):
            guard await launcher.open(url) else {
                HelmLog.shared.warn(Self.moduleID, "a launch was refused by the system")
                return .failed
            }
            return .launched
        }
    }

    /// What is stored; the default arrangement when there is no file (an unreadable one shows the catalog's order, as its warning says).
    private func storedLayout(of read: LayoutRead, _ reading: CatalogReading) -> LaunchpadLayout {
        switch read {
        case .loaded(let layout): layout
        case .absent: defaultArrangement(reading)
        case .unreadable: .empty
        }
    }

    private func defaultArrangement(_ reading: CatalogReading) -> LaunchpadLayout {
        .defaultArrangement(for: reading.apps, utilitiesFolderName: utilitiesFolderName())
    }

    private func snapshot(_ reading: CatalogReading, stored: LayoutRead, layout: LaunchpadLayout?, saved: Bool) -> LaunchpadSnapshot {
        let order = reading.apps.map(\.id)
        let reconciled = layout ?? storedLayout(of: stored, reading).reconciled(catalog: order, complete: reading.complete)
        var snap = LaunchpadSnapshot(apps: Dictionary(reading.apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                                     order: order, layout: reconciled, catalogComplete: reading.complete, layoutRead: stored)
        snap.saved = saved
        return snap
    }
}
