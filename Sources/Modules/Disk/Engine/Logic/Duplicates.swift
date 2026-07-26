import Foundation

/// One file, as the duplicate search needs it.
public struct FileFacts: Hashable, Sendable {
    public let path: String
    public let bytes: Int
    /// The inode. Two paths sharing one are one file wearing two names — a
    /// hard link — and deleting either frees nothing, so the pair must never
    /// be offered as a duplicate.
    public let fileID: UInt64

    public init(path: String, bytes: Int, fileID: UInt64) {
        self.path = path
        self.bytes = bytes
        self.fileID = fileID
    }
}

/// Files with identical content, and what keeping only one would free.
public struct DuplicateGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String { paths.first ?? "" }
    /// The size of one copy.
    public let bytes: Int
    /// Every path holding this content, sorted for stable display.
    public let paths: [String]
    /// What deleting all but one copy frees.
    public var wasted: Int { bytes * max(paths.count - 1, 0) }

    public init(bytes: Int, paths: [String]) {
        self.bytes = bytes
        self.paths = paths
    }
}

/// The second look inside the disk: files that are the same file twice.
///
/// Size nominates, content decides. Equal size is coincidence often enough
/// that it only earns a file a place in the running; membership in a group
/// takes matching content, checked cheaply first (a prefix hash) and fully
/// where the cheap check agrees. A file that cannot be read cannot be judged
/// and leaves the running — reporting it "identical" unread would be a guess
/// wearing a fact's clothing.
public enum Duplicates {

    /// Groups worth hashing: same size, above the floor, more than one file —
    /// with hard-linked twins collapsed to one representative first.
    public static func sizeGroups(_ files: [FileFacts], minBytes: Int) -> [[FileFacts]] {
        var byID: [UInt64: FileFacts] = [:]
        // fileID 0 means the inode could not be read. Unknown is not "the
        // same": collapsing all unknowns into one representative would hide
        // real duplicates behind a stat failure.
        var unknowable: [FileFacts] = []
        for file in files where file.bytes >= minBytes {
            if file.fileID == 0 {
                unknowable.append(file)
            } else if byID[file.fileID] == nil {
                // One entry per inode: the first path stands for the file.
                byID[file.fileID] = file
            }
        }
        var bySize: [Int: [FileFacts]] = [:]
        for file in byID.values + unknowable {
            bySize[file.bytes, default: []].append(file)
        }
        return bySize.values.filter { $0.count > 1 }
            .map { $0.sorted { $0.path < $1.path } }
            .sorted { ($0.first?.bytes ?? 0) > ($1.first?.bytes ?? 0) }
    }

    /// Splits one candidate group by a digest. Files whose digest cannot be
    /// taken are dropped; sub-groups of one stop being candidates.
    public static func refine(_ group: [FileFacts],
                              by digest: (FileFacts) -> String?) -> [[FileFacts]] {
        var byDigest: [String: [FileFacts]] = [:]
        for file in group {
            guard let d = digest(file) else { continue }
            byDigest[d, default: []].append(file)
        }
        return byDigest.values.filter { $0.count > 1 }.map { $0 }
    }

    /// The whole pipeline: size → prefix hash → full hash → groups, largest
    /// waste first. `partial` and `full` are injected so the pipeline can be
    /// tested without a disk and driven with real hashing in production.
    public static func groups(files: [FileFacts], minBytes: Int,
                              partial: (FileFacts) -> String?,
                              full: (FileFacts) -> String?) -> [DuplicateGroup] {
        var result: [DuplicateGroup] = []
        for candidates in sizeGroups(files, minBytes: minBytes) {
            for byPrefix in refine(candidates, by: partial) {
                for identical in refine(byPrefix, by: full) {
                    result.append(DuplicateGroup(
                        bytes: identical.first?.bytes ?? 0,
                        paths: identical.map(\.path).sorted()))
                }
            }
        }
        return result.sorted { $0.wasted > $1.wasted }
    }
}
