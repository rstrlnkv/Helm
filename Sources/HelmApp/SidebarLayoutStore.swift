import Foundation
import HelmRuntime
import HelmUI

/// Reads and writes the sidebar's arrangement, and never hands out one that
/// breaks the invariant.
@MainActor
enum SidebarLayoutStore {
    static let key = "sidebarLayout"

    /// The registry as the layout wants it: an id and the category it seeds
    /// from, in registry order. One place, so the window and the tests cannot
    /// disagree about what the app ships.
    static func registry() -> [(String, ModuleCategory)] {
        ModuleRegistry.all.map { ($0.idRaw, $0.moduleCategory) }
    }

    /// Always reconciled, never trusted.
    ///
    /// The bytes were written by a build that is not necessarily this one, so
    /// reconciling belongs here rather than at the write: a module added since
    /// the layout was stored has to appear the first time it is read, not after
    /// somebody happens to rearrange something.
    static func read(from store: NamespacedStore,
                     registry: [(String, ModuleCategory)]) -> SidebarLayout {
        let stored = store.data(key).flatMap {
            try? JSONDecoder().decode(SidebarLayout.self, from: $0)
        }
        // No layout yet: seed, then honour the flat order the person may have
        // arranged before sections existed. Dropping it would be the upgrade
        // rearranging their sidebar for them. Once a layout exists the flat key
        // is history and is not consulted again.
        let base = stored ?? migrated(from: store.stringArray("moduleOrder"), registry: registry)
        return base.reconciled(with: registry)
    }

    static func write(_ layout: SidebarLayout, to store: NamespacedStore) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        store.set(data, for: key)
    }

    /// The seeded arrangement, with each section's modules put in the order the
    /// person had already given the flat list.
    private static func migrated(from order: [String],
                                 registry: [(String, ModuleCategory)]) -> SidebarLayout {
        let seeded = SidebarLayout.seeded(from: registry)
        guard !order.isEmpty else { return seeded }
        var copy = seeded
        for index in copy.sections.indices {
            copy.sections[index].modules.sort { a, b in
                // A module the flat order never mentioned sorts last rather
                // than first: it is one the person never arranged.
                (order.firstIndex(of: a) ?? Int.max) < (order.firstIndex(of: b) ?? Int.max)
            }
        }
        return copy
    }
}
