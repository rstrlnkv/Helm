import Foundation

/// A folder Helm watches, and the rules it watches it with.
///
/// The rules belong to the folder rather than to the module because their order
/// is the setting: two folders each read their own list top to bottom, and a
/// single global list would make the order of one folder's rules depend on
/// another folder's.
public struct WatchedFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var path: String
    public var enabled: Bool
    /// Order matters: first match wins.
    public var rules: [Rule]
    /// 1 is the folder's own contents. Recursion is a property of the folder,
    /// not of a rule — a rule that reaches into subfolders on its own is how a
    /// tidy Downloads folder becomes a rearranged project tree.
    public var depth: Int

    public init(id: String = UUID().uuidString, path: String, enabled: Bool = true,
                rules: [Rule] = [], depth: Int = 1) {
        self.id = id
        self.path = path
        self.enabled = enabled
        self.rules = rules
        self.depth = depth
    }

    /// The rules that would actually run: a folder switched off runs none of
    /// them, whatever each rule's own switch says.
    public var activeRules: [Rule] { enabled ? rules : [] }

    /// This folder as a dry run of one rule has to see it: the whole list, in
    /// the order it is read, with the rule being written in its own place and
    /// switched on.
    ///
    /// **A dry run of one rule alone answers a question nobody asked.** The
    /// editor used to send a folder holding a single rule, with a comment saying
    /// a rule above it would otherwise take the files — which is true, and is
    /// the answer rather than the problem: first match wins, so a narrow rule
    /// written below a broad one is offered files it will never get, lights up
    /// with matches, and does nothing for ever after.
    ///
    /// The rule is switched on because the dry run is what the switch is decided
    /// from; every other rule keeps the switch the person gave it, because a rule
    /// they turned off does not take files in a folder where it will not take
    /// them. A rule the list has never seen — one the editor has only just made —
    /// goes last, which is where a new rule is.
    public func previewing(_ rule: Rule) -> WatchedFolder {
        var copy = self
        var draft = rule
        draft.enabled = true
        if let index = copy.rules.firstIndex(where: { $0.id == rule.id }) {
            copy.rules[index] = draft
        } else {
            copy.rules.append(draft)
        }
        return copy
    }
}

/// What a sweep did, per folder.
public struct SweepReport: Codable, Equatable, Sendable {
    public let folderID: String
    public let examined: Int
    public let acted: Int
    public let refused: Int
    public let failed: Int
    /// Whether there was anything to examine at all. «Examined 0» is a folder
    /// with nothing to do, a folder that is gone and a folder behind a
    /// permission, and the person is owed which.
    public let folder: FolderState

    public init(folderID: String, examined: Int, acted: Int, refused: Int, failed: Int,
                folder: FolderState = .read) {
        self.folderID = folderID
        self.examined = examined
        self.acted = acted
        self.refused = refused
        self.failed = failed
        self.folder = folder
    }
}
