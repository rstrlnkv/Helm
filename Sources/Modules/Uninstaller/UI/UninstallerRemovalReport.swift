import HelmUI
import Module_Uninstaller_Engine

extension HelmRemovalOutcome {

    /// The line both of this module's removal screens end with.
    ///
    /// The Leftovers tab and the unprompted Trash window report the same three
    /// states — nothing yet, it worked, macOS refused some of it — and each
    /// spelled the mapping out for itself: the reasons
    /// through `UnStr.failureReason`, the Full Disk Access flag as a second
    /// search of the same list. Two screens doing one thing must not describe it
    /// in two ways, and the half a caller forgets is `needsFullDiskAccess`,
    /// which is the one button on that sheet a person can act on.
    ///
    /// `nil` is the first state — neither page draws a bar before its first
    /// removal.
    static func uninstaller(_ succeeded: String?, removed: Int,
                            failures: [TrashFailureInfo]) -> HelmRemovalOutcome? {
        guard let succeeded else { return nil }
        // A green bar over a refusal is the app congratulating itself for work
        // macOS did not let it do, which is what the failures below prevent.
        return HelmRemovalOutcome(
            succeededText: succeeded, removed: removed,
            failures: failures.map { HelmRemovalFailure(path: $0.path,
                                                        reason: UnStr.failureReason($0.reason)) },
            needsFullDiskAccess: failures.contains { $0.reason == .needsFullDiskAccess })
    }
}
