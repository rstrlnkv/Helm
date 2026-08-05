import Foundation
import HelmRuntime
import HelmUI

/// Reads and writes what the panel holds, and never hands out a layout that
/// breaks the invariant.
@MainActor
enum PanelLayoutStore {
    /// **Not `panelLayout`.** That key is in `ObsoleteDefaults.retired` — a
    /// grid the app had once and rolled back — so it is deleted at every launch
    /// and a layout stored under it would live exactly until the next start.
    /// The name also carried a different format, and a value left on somebody's
    /// disk would decode as nothing at all.
    static let key = "panelWidgets"

    /// Always reconciled, never trusted: the bytes were written by a build that
    /// is not necessarily this one, so a module that arrived with this update
    /// has to appear the first time the panel is opened rather than after
    /// somebody happens to rearrange something.
    ///
    /// `offered` is the ids this build can draw right now, in the order the
    /// person arranged them — the sidebar's arrangement, which is the one
    /// order Helm has.
    static func read(from store: NamespacedStore, offered: [String]) -> PanelLayout {
        let stored = store.data(key).flatMap {
            try? JSONDecoder().decode(PanelLayout.self, from: $0)
        }
        guard let stored else { return PanelLayout.seeded(from: offered) }
        return stored.reconciled(arriving: offered)
    }

    /// Written on every change, not on «Done».
    ///
    /// There is no Done in this editor: the panel closes when it loses focus,
    /// which is most of the ways out of it. A layout that only saved on a
    /// button somebody never pressed would be a panel that forgets what you
    /// just did every time you look away from it.
    static func write(_ layout: PanelLayout, to store: NamespacedStore) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        store.set(data, for: key)
    }
}
