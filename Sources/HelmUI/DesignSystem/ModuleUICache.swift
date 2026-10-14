import Foundation

/// A module's cached UI state, and letting go of it when the module is switched off.
///
/// Several modules keep their view model alive across page teardown on purpose:
/// Settings rebuilds a page on every sidebar visit, and losing a minute-long
/// scan — or paying four seconds to measure 39 bundles again — to a sidebar
/// click is hostile. That cache is keyed to the module's view model and nothing
/// clears it, which is right while the module is on and wrong the moment it is
/// off: a scan tree is hundreds of megabytes that nobody can reach any more and
/// nobody asked to keep.
///
/// **Two doors, one table.** `shared` builds, keys and drops the model;
/// `dropWhenDisabled` runs a closure of the caller's own. Both land in the same
/// table under the module id, one observer of `.helmModuleDisabled` serves every
/// id, and a module that caches in more than one place — a page model in one file
/// and a capture controller in another — has every one of them dropped.
@MainActor
public enum ModuleUICache {
    /// What one module id holds: the models `shared` built, one per type, and the
    /// closures `dropWhenDisabled` was handed.
    private struct Holdings {
        var models: [ObjectIdentifier: Entry] = [:]
        var drops: [@MainActor () -> Void] = []
    }

    /// A model and the view model it was built against. The view model is weak
    /// because the entry needs it only to tell who is asking: a model that keeps
    /// its view model keeps it alive for as long as the entry stands, and the
    /// entry stands until its module is switched off or another view model asks.
    private struct Entry {
        weak var vm: ModuleViewModel?
        let model: AnyObject
        let release: @MainActor () -> Void
    }

    private static var holdings: [String: Holdings] = [:]
    private static var observer: NSObjectProtocol?

    /// The model of type `Model` for this module and this view model, built by
    /// `make` the first time it is asked for.
    ///
    /// **Keyed to the module id, the type and the view model.** The host builds
    /// a new view model every time a module is switched on, so a model cached
    /// for the previous one talks to an engine that is gone, and its transport
    /// answers every command with empty `Data`. Asked with another view model,
    /// this releases the old model and builds a new one. Two types under one id
    /// are two entries.
    ///
    /// **Releasing a model is its subscription cancelled, then `teardown`.**
    /// `events` is asked for the model's `EventSubscription` at that moment and
    /// not when the model is built, so the one cancelled is the one the model
    /// holds then. A model asked for without `events` is only let go: it ends its
    /// loop in `deinit`, when the last reference goes, and a page still holding it
    /// keeps the subscriber on the transport for as long. `teardown` is whatever
    /// else the model must end itself — a timer, a window, a file watch. A
    /// switch-off takes the entry out of the table before either runs; a
    /// replacement writes the new entry over it after `make` returns. A later
    /// call after the switch-off builds a new model.
    public static func shared<Model: AnyObject>(
        vm: ModuleViewModel, id: String,
        events: @escaping (Model) -> EventSubscription? = { _ in nil },
        teardown: @escaping @MainActor (Model) -> Void = { _ in },
        make: () -> Model
    ) -> Model {
        let key = ObjectIdentifier(Model.self)
        if let held = holdings[id]?.models[key], held.vm === vm, let model = held.model as? Model {
            return model
        }
        holdings[id]?.models[key]?.release()
        let model = make()
        holdings[id, default: Holdings()].models[key] = Entry(vm: vm, model: model) {
            events(model)?.cancel()
            teardown(model)
        }
        observeDisabled()
        return model
    }

    /// Runs `drop` when this module is switched off, once. Every registration
    /// under an id runs, in the order they were made, and a caller that puts
    /// this beside its cache assignment each time it builds a model leaves one
    /// closure per build until the next switch-off, which runs them and empties
    /// the list.
    public static func dropWhenDisabled(_ moduleID: String, _ drop: @escaping @MainActor () -> Void) {
        holdings[moduleID, default: Holdings()].drops.append(drop)
        observeDisabled()
    }

    private static func observeDisabled() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main
        ) { note in
            guard let moduleID = note.object as? String else { return }
            MainActor.assumeIsolated { release(moduleID) }
        }
    }

    /// Takes the id out of the table before anything runs, so a closure that
    /// registers again, or asks for a model, finds the table as it will stay.
    private static func release(_ moduleID: String) {
        guard let held = holdings.removeValue(forKey: moduleID) else { return }
        for entry in held.models.values { entry.release() }
        for drop in held.drops { drop() }
    }
}
