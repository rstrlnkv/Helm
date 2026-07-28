import Foundation

/// Dropping a module's cached UI state when the module is switched off.
///
/// Several modules keep their view model alive across page teardown on purpose:
/// Settings rebuilds a page on every sidebar visit, and losing a minute-long
/// scan — or paying four seconds to measure 39 bundles again — to a sidebar
/// click is hostile. That cache is keyed to the module's view model and nothing
/// clears it, which is right while the module is on and wrong the moment it is
/// off: a scan tree is hundreds of megabytes that nobody can reach any more and
/// nobody asked to keep.
///
/// One observer per module id, registered the first time that module caches
/// anything. Written once here rather than four times in four view models,
/// which is the duplication the house rules exist to stop.
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
