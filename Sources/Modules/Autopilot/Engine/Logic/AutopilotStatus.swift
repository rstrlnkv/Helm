import Foundation

/// What the page cannot learn by looking at the folder list.
///
/// The list is `[WatchedFolder]` and every one of the module's silences comes
/// out of it as the same value: a rule set something else wrote decodes to `[]`,
/// and so does a Mac that has never had a rule. This carries the facts that tell
/// those apart — one request, made where the folders are requested.
public struct AutopilotStatus: Codable, Equatable, Sendable {
    /// Why none of the stored rules are running, or `nil` when they are.
    public let refusal: RuleRefusal?
    /// What reading each watched folder came to, by folder id. A folder that is
    /// gone and a folder behind a permission are the two commonest ways this
    /// module quietly stops working, and the list of folders is the same value
    /// in both cases.
    public let folders: [String: FolderState]
    /// Whether a stream is running over the watched folders, or `nil` when
    /// nothing has asked for one yet — an engine that has not been activated
    /// knows nothing about this and must not be read as knowing "no".
    ///
    /// The reverse channel `FolderWatcher.watch(_:started:)` exists for, and the
    /// reason it exists: both engines used to log that they were watching a
    /// folder with no way to find out whether they were.
    public let watching: Bool?
    /// Whether the stored history is not Helm's. The history is still shown —
    /// a rewritten history is itself something that happened — and nothing in
    /// it may be put back, so the page draws the warning and its one way out
    /// instead of offering returns that would all refuse.
    public let historyRefused: Bool

    public init(refusal: RuleRefusal?, folders: [String: FolderState] = [:],
                watching: Bool? = nil, historyRefused: Bool = false) {
        self.refusal = refusal
        self.folders = folders
        self.watching = watching
        self.historyRefused = historyRefused
    }
}
