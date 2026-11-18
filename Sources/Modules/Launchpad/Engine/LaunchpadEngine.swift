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
    private let store: LayoutStore
    private let lock = NSLock()
    /// The latest catalog read, so an edit reconciles against what the person was looking at.
    private var lastCatalog: CatalogReading?

    public convenience init(catalog: AppCatalogPort = FileSystemAppCatalog()) {
        self.init(catalog: catalog, store: LayoutStore())
    }

    init(catalog: AppCatalogPort, store: LayoutStore) {
        self.catalog = catalog
        self.store = store
    }

    public func activate() {}
    public func deactivate() {}

    /// Reconciled in memory; writes nothing.
    func read() -> LaunchpadSnapshot {
        lock.lock(); defer { lock.unlock() }
        let reading = catalog.read()
        lastCatalog = reading
        return snapshot(reading, stored: store.load(), layout: nil, saved: true)
    }

    /// nil = refused (a vanished id, an empty name): nothing written. Otherwise the new snapshot,
    /// with `saved` false when the write did not land — the result is still returned.
    func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot? {
        lock.lock(); defer { lock.unlock() }
        let reading = lastCatalog ?? catalog.read()
        lastCatalog = reading
        let stored = store.load()
        let base = Self.layout(of: stored).reconciled(catalog: reading.apps.map(\.id), complete: reading.complete)
        guard let edited = base.applying(edit) else { return nil }
        let saved = (stored != .unreadable || store.moveUnreadableAside()) && store.save(edited)
        return snapshot(reading, stored: saved ? .loaded(edited) : stored, layout: edited, saved: saved)
    }

    private static func layout(of read: LayoutRead) -> LaunchpadLayout {
        if case .loaded(let layout) = read { return layout }
        return .empty
    }

    private func snapshot(_ reading: CatalogReading, stored: LayoutRead, layout: LaunchpadLayout?, saved: Bool) -> LaunchpadSnapshot {
        let order = reading.apps.map(\.id)
        let reconciled = layout ?? Self.layout(of: stored).reconciled(catalog: order, complete: reading.complete)
        var snap = LaunchpadSnapshot(apps: Dictionary(reading.apps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                                     order: order, layout: reconciled, catalogComplete: reading.complete, layoutRead: stored)
        snap.saved = saved
        return snap
    }
}
