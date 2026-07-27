import Foundation

/// Everything a rule is allowed to know about a file.
///
/// The list is deliberately closed. A condition can only ask about what is in
/// here, so "would this rule fire" is a question about a struct rather than
/// about a disk — which is what lets the ordering, the boundaries and the
/// empty-rule case all be unit tests instead of a folder full of fixtures.
///
/// `now` travels with the facts for the same reason: a rule that says "older
/// than 30 days" is a comparison between two dates, and a comparison against
/// `Date()` inside the matcher is a test that passes today.
public struct FileFacts: Equatable, Sendable {
    public let name: String
    /// Where the file is. A rule is *decided* from the facts and *performed* on
    /// this: without it the runner rebuilt the path as folder + name, which
    /// names a different file for anything below the top level. At depth 2 a
    /// plan about `sub/big.bin` was executed against `big.bin` — and where no
    /// such twin existed, nothing below the top level ran at all while the dry
    /// run promised it would.
    public let path: String
    public let kind: FileKind
    public let bytes: Int
    public let added: Date
    public let modified: Date
    /// From `kMDItemWhereFroms` — nil for a file that arrived any other way.
    public let downloadedFrom: String?
    public let tags: [String]
    public let isDirectory: Bool
    public let now: Date

    public init(name: String, path: String = "", kind: FileKind, bytes: Int,
                added: Date, modified: Date,
                downloadedFrom: String? = nil, tags: [String] = [],
                isDirectory: Bool = false, now: Date = Date()) {
        self.name = name
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.added = added
        self.modified = modified
        self.downloadedFrom = downloadedFrom
        self.tags = tags
        self.isDirectory = isDirectory
        self.now = now
    }

    /// Lowercased, without the dot. Empty for a file that has none.
    public var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

/// The coarse buckets a person sorts by. Resolved from UTType at the point the
/// facts are gathered, not from a list of extensions here: the system already
/// knows that a `.heic` is an image and an `.xip` is an archive, and a table of
/// our own would be a second, worse answer that drifts.
public enum FileKind: String, Codable, CaseIterable, Sendable {
    case image, document, archive, video, audio, folder, other
}
