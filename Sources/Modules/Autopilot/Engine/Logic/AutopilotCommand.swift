import Foundation

/// Everything the autopilot module's engine answers to.
///
/// Exhaustive at the switch that handles it, so a case added here without an arm
/// is a build error rather than a command that silently answers nothing. A
/// string this enum cannot parse is a command the engine does not know, refused
/// once at the door instead of falling through a `default` nobody re-reads.
public enum AutopilotCommand: String, CaseIterable, Sendable {
    case folders
    case setFolders
    /// The preview of a folder being **written**, which is the only preview
    /// anybody asks for.
    ///
    /// A `preview` case sat beside this, taking a folder by id and reading the
    /// saved version. Nothing sent it — not the page, not a test, not the host
    /// — and the comment on its handler explained why: a rule being written has
    /// not been saved, so a preview of the stored copy answers a question
    /// nobody asked. It was the superseded half of a pair, kept whole with a
    /// working handler behind it.
    case previewDraft
    case runNow
    case history
    case clearHistory
    /// What the folder list cannot say: whether it is empty because there are no
    /// rules, or because the ones on disk are not Helm's to run.
    case status
    /// Throw away a rule set that was refused. The one gesture a refused page is
    /// allowed to make, and the only way past the guard in `AutopilotEngine.save`.
    case discardRefusedRules
    /// Put one action back, by the record's own id.
    case undo
    /// Put a whole pass back, by its run id — every action of one sweep or one
    /// batch of filesystem events.
    case undoRun
}

/// What the engine announces without being asked.
///
/// One event: the history has a new pass in it. The engine acts on a timer and
/// on files arriving, with the page open and nobody pressing anything — and
/// until this existed the open page read the history once and then showed an
/// hour of work as nothing. The payload is empty on purpose: the page re-asks
/// through `AutopilotCommand.history`, so the read that fills the screen stays
/// the one that judges the seal and the thirty-day window.
public enum AutopilotEvent: String, Sendable {
    case history
}

/// Which return the page is asking for.
///
/// One wire type rather than two near-identical ones: the command says whether
/// the id names a record or a pass, and a second struct differing only in the
/// name of its single field is the shape that drifts.
public struct UndoRequest: Codable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}

/// Which watched folder a command is about.
///
/// It crossed the transport as a `private struct FolderPayload` in the engine —
/// read by two of the commands — and a `struct FolderID` declared **inside**
/// `runNow` in the view model. The fifth module found with that pair, after
/// Homebrew, Keep Awake, VPN and the uninstaller, where one of the three copies
/// had already stopped matching the other. The failure never announces itself:
/// the decode returns nil, the handler answers `Data()`, and a preview simply
/// comes back empty.
public struct WatchedFolderRef: Codable, Sendable {
    public let id: String
    public init(id: String) { self.id = id }
}
