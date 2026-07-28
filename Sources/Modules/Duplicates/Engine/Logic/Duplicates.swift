import Foundation

/// One file, as the duplicate search needs it.
public struct FileFacts: Hashable, Sendable {
    public let path: String
    public let bytes: Int
    /// The inode. Two paths sharing one are one file wearing two names — a
    /// hard link — and deleting either frees nothing, so the pair must never
    /// be offered as a duplicate.
    public let fileID: UInt64
    /// What it occupies, as opposed to how long it is.
    ///
    /// The two are separate on purpose. Grouping by size is a *content*
    /// pre-filter and keeps the logical length: two identical files always
    /// agree on that and need not agree on blocks, so grouping by what they
    /// occupy would lose duplicates — a worse failure than an imprecise total.
    /// The arithmetic the screen shows is about space, so it uses this.
    public let allocated: Int
    /// When the file arrived in its folder — the Finder's "Date Added", and
    /// what decides which copy stays. Not the creation date: a file carries
    /// that with it when it is copied, so it would call the copy exactly as old
    /// as the original. nil on a volume that does not record it.
    public let added: Date?

    public init(path: String, bytes: Int, fileID: UInt64, added: Date? = nil,
                allocated: Int? = nil) {
        self.path = path
        self.bytes = bytes
        self.fileID = fileID
        self.added = added
        self.allocated = allocated ?? bytes
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
            } else if let standing = byID[file.fileID] {
                // One entry per inode, and *which* name stands for it decides
                // what the screen offers: the representative carries its own
                // date added, and two names for one file report dates seconds
                // apart. Reached-first is the walk order, which is not a fact
                // about the files. The one that would survive among its own
                // names stands for them all.
                let keeper = SurvivingCopy.order([standing, file]).first
                byID[file.fileID] = keeper == standing.path ? standing : file
            } else {
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
        // Sorted, not `Dictionary.values`: that order comes from a hash seeded
        // per process, so the same folder listed its groups differently on
        // every launch. `SurvivingCopy` goes to the trouble of a third tiebreak
        // so a row does not move between scans; between groups nothing did.
        return byDigest.keys.sorted().compactMap { key in
            let group = byDigest[key]!
            return group.count > 1 ? group : nil
        }
    }

    /// One group, assembled the one way.
    ///
    /// There are two pipelines over the same three passes: this file's
    /// `groups`, which the unit tests drive, and `DuplicateScanner.find`, which
    /// the engine drives concurrently. When `SurvivingCopy` replaced the
    /// alphabetical rule it was wired into the first and not the second, so the
    /// page explained one rule in its tooltip while the app followed another.
    /// Both call this now, and a change to which copy survives cannot land in
    /// one line and miss the other.
    public static func group(_ identical: [FileFacts]) -> DuplicateGroup {
        // What one copy occupies, because `wasted` promises what removing the
        // extras frees and the removal reports the same measure.
        DuplicateGroup(bytes: identical.first?.allocated ?? 0,
                       paths: SurvivingCopy.order(identical))
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
                    result.append(group(identical))
                }
            }
        }
        return result.sorted { $0.wasted > $1.wasted }
    }
}
