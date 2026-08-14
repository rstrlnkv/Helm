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
