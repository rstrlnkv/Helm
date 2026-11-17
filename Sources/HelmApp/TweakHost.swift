import Combine
import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI

/// Owns the lifecycle of every tweak: a store of its own, an enabled flag, and the engine and model built
/// while it is on.
///
/// **Why not `ModuleHost`'s own enable and disable.** The Tweaks entry is a `ModuleDescriptor`, so
/// `ModuleHost` already runs *its* lifecycle: the store, the switch, `shutdown`, the reset, the
/// sidebar's off-means-General rule. What a module costs the host beyond that is `ModuleHost.Live`'s
/// hotkeys, scans, menu bar and panel, and a tweak has none of them; sharing the code would carry
/// eight closures a tweak never fills (`ModuleHost.Live` has ten; a tweak fills `stop` and, as `card`, `page`). A tweak needs build, activate, then stop and deactivate, and this is
/// that. The entry's `Model` is this object, and its engine (`TweaksEngine`) calls `activateEnabled()`
/// and `stopAll()`, so a tweak stops whenever the entry does: on its own switch, on `shutdown`, on reset.
///
/// **Off until switched on** (`TweakDescriptor`): a fresh store builds and activates nothing.
///
/// **Namespaced `tweak.<id>`.** A module id cannot hold a dot (`ModuleIdsAreUsableAsKeysAndAsFolderNamesTests`),
/// so no tweak's store can be a module's.
@MainActor final class TweakHost: ObservableObject {

    struct Live {
        let engine: any ModuleEngine
        /// The tweak's own model, held so it lives and dies with this entry; everything that draws from it
        /// goes through the closures below.
        let model: AnyObject
        let card: @MainActor () -> AnyView
        let stop: @MainActor () -> Void
    }

    private let registry: [any TweakDescriptor]
    private let backing: KeyValueStore

    /// Keyed by `ModuleID.rawValue`.
    @Published private(set) var live: [String: Live] = [:]

    init(registry: [any TweakDescriptor] = TweakRegistry.all, backing: KeyValueStore = UserDefaults.standard) {
        self.registry = registry
        self.backing = backing
    }

    var descriptors: [any TweakDescriptor] { registry }

    /// The tweak's store namespace. A function and not a literal at the `NamespacedStore(namespace:` call, which
    /// `StoreNamespacesAreModuleIdsTests` holds to the registered modules' ids.
    static func namespace(for d: any TweakDescriptor) -> String { "tweak.\(d.idRaw)" }

    private func store(for d: any TweakDescriptor) -> NamespacedStore {
        NamespacedStore(namespace: Self.namespace(for: d), backing: backing)
    }

    func isEnabled(_ d: any TweakDescriptor) -> Bool {
        store(for: d).bool("enabled", default: false)
    }

    /// Every tweak that is on and not yet live, built and started. Idempotent, for the reason
    /// `ModuleHost.bootstrap` is: a second engine assigned over the first is an orphan that still holds
    /// whatever it had registered.
    func activateEnabled() {
        for d in registry where isEnabled(d) && live[d.idRaw] == nil { enable(d) }
    }

    func setEnabled(_ d: any TweakDescriptor, _ on: Bool) {
        store(for: d).set(on, for: "enabled")
        if on {
            if live[d.idRaw] == nil { enable(d) }
        } else {
            disable(d)
        }
    }

    /// Every live tweak stopped, its model first and its engine after, and dropped; no flag moves.
    ///
    /// Stopping, not somebody switching a tweak off: the next `activateEnabled()` builds the same set again.
    /// Safe to run twice.
    func stopAll() {
        for key in live.keys.sorted() { teardown(key) }
    }

    private func enable(_ d: any TweakDescriptor) {
        HelmLog.shared.info("host", "tweak enable \(d.idRaw)")
        live[d.idRaw] = makeLive(d, store: store(for: d))
    }

    private func disable(_ d: any TweakDescriptor) {
        HelmLog.shared.info("host", "tweak disable \(d.idRaw)")
        teardown(d.idRaw)
    }

    private func teardown(_ key: String) {
        guard let running = live[key] else { return }
        running.stop()
        running.engine.deactivate()
        live[key] = nil
    }

    /// Generic so the descriptor's `Model` is known for the whole of the build, as `ModuleHost.makeLive` is.
    private func makeLive<D: TweakDescriptor>(_ d: D, store s: NamespacedStore) -> Live {
        let parts = d.makeTweak(store: s)
        let model = parts.model
        parts.engine.activate()
        return Live(engine: parts.engine, model: model,
                    card: { d.card(model) },
                    stop: { d.stop(model) })
    }
}
