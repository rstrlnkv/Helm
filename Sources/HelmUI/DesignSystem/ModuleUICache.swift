import Foundation

/// Dropping a module's cached UI state when the module is switched off.
///
/// A module on the default `makeModule` may keep page state alive across page
/// teardown, in a static of its own: Settings rebuilds a page on every sidebar
/// visit. That cache is keyed to the host's view model, and nothing else clears
/// it, which is right while the module is on and wrong the moment it is off: what it holds
/// was built for an engine that is gone.
///
/// One observer per module id, registered the first time that module caches
/// anything. Written once here rather than in each view model.
@MainActor
public enum ModuleUICache {
    private static var observers: [String: NSObjectProtocol] = [:]

    /// Runs `drop` when this module is switched off. Registering twice for the
    /// same id is a no-op, so callers can put this beside the cache assignment
    /// without tracking whether they have done it already.
    public static func dropWhenDisabled(_ moduleID: String, _ drop: @escaping @MainActor () -> Void) {
        guard observers[moduleID] == nil else { return }
        observers[moduleID] = NotificationCenter.default.addObserver(
            forName: .helmModuleDisabled, object: nil, queue: .main
        ) { note in
            guard note.object as? String == moduleID else { return }
            MainActor.assumeIsolated { drop() }
        }
    }
}
