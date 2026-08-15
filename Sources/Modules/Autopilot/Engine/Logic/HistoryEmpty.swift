import Foundation

/// Why the record of what Autopilot did is empty — or nothing, when it is not.
///
/// **«Autopilot has not done anything yet» was three sentences wearing one.** A
/// Mac with no watched folder is not idle, it is unconfigured. A rule set whose
/// every rule is switched off is not idle either, and the person did that and
/// may not remember doing it. Only the third — folders watched, rules running,
/// nothing matched — is the state the sentence described, and it is the one that
/// earns the explanation about files arriving and the sweep coming round.
///
/// Here rather than in the view, and over the counts rather than over the rows,
/// for the reason `DuplicatesEmpty` gives one module over: it is the module's
/// rule about what its own empty screen means, and a view that worked it out
/// would be the second place it lives.
public enum HistoryEmpty {

    /// Exhaustive on purpose, like `DuplicatesEmpty.Reason`: a `default` at the
    /// caller is how a fourth state would come to be drawn as one of these
    /// three, which is the defect this type exists for.
    public enum Reason: Equatable, Sendable {
        /// Nothing is watched. The screen has somewhere else to send the reader
        /// — a folder to add, or a preset to look at — so this is not a
        /// statement about the module at all.
        case noFolders
        /// Folders are watched and not one rule in them could run: every rule
        /// switched off, every folder switched off, or no rules written yet.
        /// One sentence for all three, because for a reader they are one fact —
        /// nothing will ever appear here until something is switched on.
        case everyRuleOff
        /// Set up, running, and nothing has matched. The only case where «a file
        /// arriving is checked, and every folder is swept once an hour» is an
        /// answer rather than a distraction.
        case nothingYet
    }

    /// - Parameters:
    ///   - folders: the rule set as stored, switches and all.
    ///   - runs: the passes the section draws — **not** the raw records. The
    ///     grouping drops everything past thirty days, so a Mac tidied two
    ///     months ago and not since has records in its store and nothing on its
    ///     screen; a reason computed from the records would leave that card
    ///     blank with no sentence in it.
    public static func reason(folders: [WatchedFolder], runs: [ActionRun]) -> Reason? {
        guard runs.isEmpty else { return nil }
        guard !folders.isEmpty else { return .noFolders }
        // `activeRules` is empty for a folder whose own switch is off, which is
        // the one place the two switches are already reconciled.
        let running = folders.flatMap(\.activeRules).contains { $0.enabled }
        return running ? .nothingYet : .everyRuleOff
    }
}
