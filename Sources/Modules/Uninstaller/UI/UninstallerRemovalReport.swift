import HelmUI
import Module_Uninstaller_Engine

extension HelmRemovalOutcome {

    /// The line both of this module's removal screens end with.
    ///
    /// The Leftovers tab and the Trash window report the same three states
    /// (nothing yet, it worked, macOS refused some), so the mapping is written
    /// once, `needsFullDiskAccess` included: the one button a person can act on.
    /// `nil` is the first state: no bar before the first removal.
    static func uninstaller(_ succeeded: String?, removed: Int,
                            failures: [TrashFailureInfo]) -> HelmRemovalOutcome? {
        guard let succeeded else { return nil }
        // A refusal never draws the green bar of success.
        return HelmRemovalOutcome(
            succeededText: succeeded, removed: removed,
            failures: failures.map { HelmRemovalFailure(path: $0.path,
                                                        reason: UnStr.failureReason($0.reason)) },
            needsFullDiskAccess: failures.contains { $0.reason == .needsFullDiskAccess })
    }
}
