import Combine
import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI

/// Owns module lifecycle: per-module namespaced store, enabled flag, and
/// the engine and model built for every enabled module, at launch or when it is
/// switched on.
@MainActor final class ModuleHost: ObservableObject {
    static let shared = ModuleHost()

    struct Live {
        let descriptor: any ModuleDescriptor
        let engine: any ModuleEngine
        /// The module's own model, held so it lives and dies with this entry;
        /// everything that draws from it goes through the closures below, and the
        /// trash sweep's one `as?` in `AppDelegate`.
        let model: AnyObject
        let store: NamespacedStore
        let page: @MainActor () -> AnyView
        let menuBar: @MainActor () -> MenuBarContribution?
        let activity: @MainActor () -> ModuleActivity?
        let statusAppearance: @MainActor () -> StatusAppearance
        let statusChanges: @MainActor () -> AnyPublisher<Void, Never>?
        let panelWidget: @MainActor (PanelWidgetSize) -> AnyView?
        let panelWidgetSizes: @MainActor () -> Set<PanelWidgetSize>
        let backgroundScan: @MainActor () async -> ScanReport?
        let stop: @MainActor () -> Void
        let hotkeyPressed: @MainActor (ModuleHotkey) -> Void
    }

    /// Keyed by `ModuleID.rawValue`.
    @Published private(set) var live: [String: Live] = [:]

    private init() {}

    private func store(for d: any ModuleDescriptor) -> NamespacedStore {
        NamespacedStore(namespace: type(of: d).id.rawValue, backing: UserDefaults.standard)
    }

    func isEnabled(_ d: any ModuleDescriptor) -> Bool {
        store(for: d).bool("enabled", default: true)
    }

    /// Which modules are on, as ids — the question the sidebar and the consent
    /// section each ask about a *group*, and each had answered one store read
    /// per module of their own.
    var enabledModuleIDs: Set<String> {
        Set(ModuleRegistry.all.filter(isEnabled).map(\.idRaw))
    }

    /// Idempotent, on the same test `setEnabled` has always made and this one
    /// had not: a module already live is left alone.
    ///
    /// It used to assign a second engine over the first without deactivating
    /// it, so every extra call orphaned one engine per enabled module — each
    /// still holding whatever it had registered, and each then freed with it
    /// still registered. For Layout that is a live `CGEvent` tap on the main
    /// run loop pointing at freed memory (`CGKeyTap`), which is a crash inside
    /// whatever the person is typing; for Keep Awake it is power assertions held
    /// until the process exits. The `deinit`s are the backstop for the
    /// routes nobody remembers; not building the orphan is the fix.
    func bootstrap() {
        AppSettings.migrateAndPurge(in: UserDefaults.standard)
        for d in ModuleRegistry.all
        where isEnabled(d) && live[type(of: d).id.rawValue] == nil { enable(d) }
    }

    /// A stand-in engine is live (`ModuleEngine.standsIn`): what is shown is not what
    /// the Mac is in, and the host's own store is the real one.
    func standsInLive(_ key: String) -> Bool { live[key]?.engine.standsIn ?? false }
    var anyStandsIn: Bool { live.values.contains { $0.engine.standsIn } }

    func setEnabled(_ d: any ModuleDescriptor, _ on: Bool) {
        if !on, standsInLive(type(of: d).id.rawValue) {
            HelmLog.shared.warn("host", "refused: a stand-in engine is live, \(type(of: d).id.rawValue) stays on")
            return
        }
        store(for: d).set(on, for: "enabled")
        if on {
            if live[type(of: d).id.rawValue] == nil { enable(d) }
            // Only from here, never from `bootstrap`: this is somebody switching
            // a module on, which is the moment a module may act unasked.
            NotificationCenter.default.post(name: .helmModuleEnabled,
                                            object: type(of: d).id.rawValue)
        } else {
            disable(d)
        }
    }

    /// Every live engine deactivated and dropped; nobody's enabled flag moves.
    ///
    /// This is quitting — or a test suite tidying up after `bootstrap()` — not
    /// somebody switching a module off: no store write, no `.helmModuleDisabled`
    /// post, and the next `bootstrap()` builds the same set again. `disable`
    /// stays the route for the person's own switch, with the persistence and
    /// the notification that act carries.
    func shutdown() {
        for key in live.keys.sorted() {
            live[key]?.stop()
            live[key]?.engine.deactivate()
            live[key]?.descriptor.detachMenuBarPresence()
            live[key] = nil
            // The same sweep `disable` does: a scan task can outlive the
            // engine that started it.
            HelmActivity.sweep(module: key)
        }
    }

    /// Measured **around** the construction, which is the whole point.
    ///
    /// The reading used to be taken on the line before the module was built, so
    /// `module.disk.enable: 9 MB` was the process total *before* Disk existed and
    /// said nothing whatever about Disk. Nine such lines at launch read like nine
    /// per-module costs and were nine consecutive totals.
    ///
    /// What this can and cannot answer, so nobody reads more into it than it holds:
    /// it is what switching the module on cost and what switching it off gave back.
    /// It is **not** how much the module holds while it runs — every module lives in
    /// one process and one malloc zone, and there is no per-subsystem accounting to
    /// ask. The pair is still the signal that matters: 3 MB on and nothing back off
    /// is the leak family of a model that outlives its module.
    private func enable(_ d: any ModuleDescriptor) {
        let key = type(of: d).id.rawValue
        HelmLog.shared.info("host", "enable \(key)")
        let before = MemoryFootprint.current()
        let s = store(for: d)
        live[key] = makeLive(d, store: s)
        if let before, let after = MemoryFootprint.current() {
            HelmLog.shared.memory("module.\(key).enable", grewBy: after - before)
        }
    }

    /// Generic so the descriptor's `Model` is known for the whole of the build:
    /// everything that takes the model is closed over it here, and nothing
    /// outside this function has to name its type or cast to it.
    private func makeLive<D: ModuleDescriptor>(_ d: D, store s: NamespacedStore) -> Live {
        let parts = d.makeModule(store: s)
        let model = parts.model
        parts.engine.activate()
        // After the engine is running, and from here rather than from
        // `makeModule`: a module's own menu-bar item is part of it running, not
        // part of it being constructed. Keyboard's indicator was built inside
        // the engine's construction, so every process that built a module —
        // the offscreen render harness included — got a status item on its Mac.
        d.attachMenuBarPresence()
        return Live(descriptor: d, engine: parts.engine, model: model, store: s,
                    page: { d.settingsPage(model) },
                    menuBar: { d.menuBar(model) },
                    activity: { d.activity(model) },
                    statusAppearance: { d.statusAppearance(model) },
                    statusChanges: { d.statusChanges(model) },
                    panelWidget: { d.panelWidget($0, model) },
                    panelWidgetSizes: { d.panelWidgetSizes(model) },
                    backgroundScan: { await d.backgroundScan(parts) },
                    stop: { d.stop(model) },
                    hotkeyPressed: { d.hotkeyPressed($0, model) })
    }

    /// Every module's declared shortcuts, one loop. A key is held only while its
    /// module is live: `isLive` reads `live`, and `HotkeyManager` asks again on
    /// every module switch.
    func registerHotkeys() {
        for d in ModuleRegistry.all {
            let id = type(of: d).id.rawValue
            for hotkey in type(of: d).hotkeys {
                HotkeyManager.shared.register(
                    hotkey.slot, store: store(for: d), prefix: hotkey.prefix,
                    fallback: hotkey.fallback,
                    isLive: { [weak self] in self?.live[id] != nil },
                    action: { [weak self] in
                        guard let running = self?.live[id] else {
                            HelmLog.shared.info("hotkey", "pressed \(hotkey.slot): module not running")
                            return
                        }
                        HelmLog.shared.info("hotkey", "pressed \(hotkey.slot)")
                        running.hotkeyPressed(hotkey)
                    })
            }
        }
    }

    private func disable(_ d: any ModuleDescriptor) {
        let key = type(of: d).id.rawValue
        HelmLog.shared.info("host", "disable \(key)")
        let before = MemoryFootprint.current()
        // Before the teardown: this is the person's own switch, so it is the
        // last moment an engine may ask them something; `handBackSystemState`
        // is the one other caller.
        // `shutdown()` — quitting — deliberately does not call it
        // (`ModuleEngine.willDisable` has the story).
        live[key]?.engine.willDisable()
        live[key]?.stop()
        live[key]?.engine.deactivate()
        // The module's own menu-bar item goes with the module. Nothing used to
        // take Keyboard's indicator away here at all: it sat in the menu bar
        // until somebody switched the module back on, which is what rebuilt it.
        d.detachMenuBarPresence()
        live[key] = nil
        // A scan task can outlive the engine that started it, and an interval
        // nobody closes would name a module that is no longer there.
        HelmActivity.sweep(module: key)
        // Whoever listens for the module's end lets go (the hotkeys).
        NotificationCenter.default.post(name: .helmModuleDisabled, object: key)
        // The reading comes last, so it covers the whole teardown.
        if let before, let after = MemoryFootprint.current() {
            HelmLog.shared.memory("module.\(key).disable", grewBy: after - before)
        }
    }

    /// Every live engine asked for what it holds **outside** Helm's own folders,
    /// with the person still at the screen.
    ///
    /// The second caller of `willDisable()`, and the only one that is not a
    /// module being switched off: «Reset all settings» promises the machine is
    /// as it was just after installing, and one of the things Helm changes
    /// beyond its two directories is the passwordless `pmset` rule Keep Awake's
    /// lid option installs. A reset that reached for `/etc/sudoers.d` itself
    /// would be the rule in the wrong place: the file is root's, and what takes
    /// it out, `sudo -n` or, where the rule cannot withdraw itself, an
    /// administrator dialog, is Keep Awake's port. So the
    /// module that installed it is asked to give it back, which is exactly what
    /// `willDisable` means (`ModuleEngine.willDisable`).
    ///
    /// **Asking is not being given.** The dialog, when it is needed, can be
    /// declined, and what that leaves behind is the rule; nothing here can wait for the answer, because
    /// `willDisable` returns before the prompt is even on screen. What this
    /// guarantees is that the ask happens, first, and with the person there —
    /// not that the machine is clean afterwards.
    ///
    /// No store write, no `.helmModuleDisabled`, no teardown: the reset ends in
    /// a relaunch, and `applicationWillTerminate` runs `shutdown()` on the way
    /// out as it does for every quit.
    func handBackSystemState() {
        for key in live.keys.sorted() { live[key]?.engine.willDisable() }
    }

    func liveModule(_ id: String) -> Live? { live[id] }

    /// `live` entries in the arrangement the person composed.
    var enabledModules: [Live] { orderedModuleIDs.compactMap { live[$0] } }

    /// Every module id in the arrangement, which `enabledModules` reads. The icon
    /// takes its module from them in this order, and the panel hands them to
    /// `PanelLayoutStore.read` in it, where they order a first layout and the
    /// arrivals; stored tiles keep the order of `panelWidgets`. The sidebar and
    /// the icon menu read `SidebarLayoutStore` themselves.
    ///
    /// It used to be `AppSettings.moduleOrder`, and that key stopped being
    /// written when the «Module order» section was deleted: nothing in the tree
    /// assigned it, so the panel had been frozen in registry order for everyone
    /// while the composer quietly rearranged the settings sidebar alone. The
    /// person who wanted VPN above Keep Awake in the panel — the surface they
    /// open twenty times a day — had no control at all.
    ///
    /// `reconciled` runs on every read, so a module that arrived with this
    /// build is in the list without anything being rearranged first.
    var orderedModuleIDs: [String] {
        SidebarLayoutStore.read(from: AppSettings.store,
                                registry: SidebarLayoutStore.registry())
            .flattened.compactMap { row in
                if case .module(let id, _) = row { return id }
                return nil
            }
    }
}
