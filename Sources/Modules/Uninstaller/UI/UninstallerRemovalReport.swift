import HelmUI
import Module_Uninstaller_Engine

extension HelmRemovalOutcome {

    /// The line both of this module's removal screens end with.
    ///
    /// The Leftovers tab and the unprompted Trash window report the same four
    /// states — nothing yet, it worked, macOS refused some of it, nobody
    /// answered — and each spelled the mapping out for itself: the reasons
    /// through `UnStr.failureReason`, the Full Disk Access flag as a second
    /// search of the same list. Two screens doing one thing must not describe it
    /// in two ways, and the half a caller forgets is `needsFullDiskAccess`,
    /// which is the one button on that sheet a person can act on.
    ///
    /// The silence comes first and carries no numbers: a lost reply is not a
    /// removal that moved nothing, and `.unanswered` is `HelmRemovalOutcome`'s
    /// own entry point for it precisely so «nothing came back, and five moved»
    /// cannot be written down. `nil` is the fourth state — neither page draws a
    /// bar before its first removal.
    static func uninstaller(_ succeeded: String?, removed: Int,
                            failures: [TrashFailureInfo],
                            replyLost: Bool) -> HelmRemovalOutcome? {
        // Ahead of the sentence, which does not exist in this state.
        if replyLost { return .unanswered }
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
