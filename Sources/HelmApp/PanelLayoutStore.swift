import HelmRuntime
import HelmUI

/// Reads and writes what the panel holds, and never hands out a layout that
/// breaks the invariant.
@MainActor
enum PanelLayoutStore {
    /// **Not `panelLayout`.** That key is in `ObsoleteDefaults.retired`, so it
    /// is deleted at every launch, and a value left under it holds another
    /// format that would decode as nothing.
    static let key = "panelWidgets"

    /// Always reconciled, never trusted: the bytes were written by a build that
    /// is not necessarily this one, so a module that arrived with this update
    /// has to appear the first time the panel is opened rather than after
    /// somebody happens to rearrange something.
    ///
    /// `offered` is the ids this build can draw right now, in the sidebar's
    /// arrangement. It orders a first layout and the ids arriving in a later
    /// one; a stored layout keeps its own order.
    static func read(from store: NamespacedStore, offered: [String],
                     sizes: [String: PanelWidgetSize] = [:]) -> PanelLayout {
        let stored = store.readJSON(PanelLayout.self, for: key)
        guard let stored else { return PanelLayout.seeded(from: offered, sizes: sizes) }
        return stored.reconciled(arriving: offered)
    }

    /// Written on every change, not on «Done».
    ///
    /// The editor has a Done, but the panel can close without it being pressed:
    /// a click outside, Escape, the icon's own click.
    static func write(_ layout: PanelLayout, to store: NamespacedStore) {
        store.writeJSON(layout, for: key)
    }
}
