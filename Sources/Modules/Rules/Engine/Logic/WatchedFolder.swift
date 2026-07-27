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
}

/// What a sweep did, per folder.
public struct SweepReport: Codable, Equatable, Sendable {
    public let folderID: String
    public let examined: Int
    public let acted: Int
    public let refused: Int
    public let failed: Int

    public init(folderID: String, examined: Int, acted: Int, refused: Int, failed: Int) {
        self.folderID = folderID
        self.examined = examined
        self.acted = acted
        self.refused = refused
        self.failed = failed
    }
}
