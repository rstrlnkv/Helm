import Foundation
import HelmRuntime

/// One file, as the duplicate search needs it.
struct FileFacts: Hashable, Sendable {
    let path: String
    let bytes: Int
    /// The inode. Two paths sharing one are one file wearing two names — a
    /// hard link — and deleting either frees nothing, so the pair must never
    /// be offered as a duplicate.
    let fileID: UInt64
    /// What it occupies, as opposed to how long it is.
    ///
    /// The two are separate on purpose. Grouping by size is a *content*
    /// pre-filter and keeps the logical length: two identical files always
    /// agree on that and need not agree on blocks, so grouping by what they
    /// occupy would lose duplicates — a worse failure than an imprecise total.
    /// The arithmetic the screen shows is about space, so it uses this.
    let allocated: Int
    /// When the file arrived in its folder — the Finder's "Date Added", and
    /// what decides which copy stays. Not the creation date: a file carries
    /// that with it when it is copied, so it would call the copy exactly as old
    /// as the original. nil on a volume that does not record it.
    let added: Date?
    /// The APFS clone family, when the volume has one. Files sharing it share
    /// their blocks, so removing one of them frees nothing — the same reasoning
    /// as `fileID` above, one level up: a hard link is one file with two names,
    /// a clone is two files with one set of blocks.
    let cloneFamily: UInt64?
    /// When the contents last changed, to the resolution `lstat` reports.
    ///
    /// Part of what identifies a file to `HashCache`, together with the inode
    /// and the size: a digest may only be reused while all three still hold.
    /// Free to collect — the walk already calls `lstat` on every candidate for
    /// the inode and the device.
    let modified: TimeInterval?

    init(path: String, bytes: Int, fileID: UInt64, added: Date? = nil,
         allocated: Int? = nil, cloneFamily: UInt64? = nil,
         modified: TimeInterval? = nil) {
        self.path = path
        self.bytes = bytes
        self.fileID = fileID
        self.added = added
        self.allocated = allocated ?? bytes
        self.cloneFamily = cloneFamily
        self.modified = modified
    }
}

/// Files with identical content, and what keeping only one would free.
public struct DuplicateGroup: Codable, Equatable, Sendable, Identifiable {

    /// One copy, with what it occupies.
    ///
    /// Each copy carries its own figure because content-identical files need
    /// not agree on one: an APFS clone or an HFS-compressed copy occupies far
    /// less than its logical length. The group used to hold a single size and
    /// multiply it, which made the answer depend on which copy the walk reached
    /// first.
    public struct Copy: Codable, Equatable, Sendable {
        public let path: String
        public let bytes: Int
        /// The APFS clone family this copy belongs to, when the volume has one.
        ///
        /// Two copies with the same id share their blocks, so removing one of
        /// them returns nothing — and Finder's Duplicate command makes exactly
        /// that. `nil` means no family, or a read that failed, and counts as a
        /// file of its own: under-reporting space somebody really gets back is
        /// the worse of the two errors.
        public let cloneFamily: UInt64?

        public init(path: String, bytes: Int, cloneFamily: UInt64? = nil) {
            self.path = path
            self.bytes = bytes
            self.cloneFamily = cloneFamily
        }
    }

    /// The copies, the one that stays first — `SurvivingCopy`'s order.
    public let copies: [Copy]

    public var id: String { copies.first?.path ?? "" }
    /// Every path holding this content, in the same order.
    public var paths: [String] { copies.map(\.path) }
    /// The size of one copy: the one that stays.
    public var bytes: Int { copies.first?.bytes ?? 0 }
    /// What deleting all but the first actually returns to the disk.
    ///
    /// Not the sum of their sizes. On APFS a clone shares its blocks with the
    /// copy it was made from, so removing it frees nothing — measured here, a
    /// 20 MB file cloned with `cp -c` cost 0 bytes of free space while a real
    /// copy cost 20 MB, and `stat` reported the same allocated size for both.
    /// Adding the sizes up promised space the disk would not give back, and the
    /// promise was exactly double for a folder of Finder duplicates.
    public var wasted: Int {
        CloneShare.reclaimable(
            removing: copies.dropFirst().map { (id: $0.cloneFamily, bytes: $0.bytes) },
            keeping: copies.first.map { [$0.cloneFamily] } ?? [])
    }

    public init(copies: [Copy]) {
        self.copies = copies
    }

    /// Where every copy is known to occupy the same amount — a fixture, or a
    /// group being rebuilt from paths alone.
    public init(bytes: Int, paths: [String]) {
        self.copies = paths.map { Copy(path: $0, bytes: bytes) }
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
enum Duplicates {

    /// Groups worth hashing: same size, above the floor, more than one file —
    /// with hard-linked twins collapsed to one representative first.
    static func sizeGroups(_ files: [FileFacts], minBytes: Int) -> [[FileFacts]] {
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
    static func refine(_ group: [FileFacts],
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
    static func group(_ identical: [FileFacts]) -> DuplicateGroup {
        // Each copy with what it occupies, because `wasted` promises what
        // removing the extras frees and the removal reports the same measure.
        // One size for the group took it from the walk order while the paths
        // came from the survivor rule — two orderings of one array — so a clone
        // beside its original reported nothing wasted or everything wasted
        // depending on which was reached first.
        let occupied = Dictionary(identical.map { ($0.path, $0.allocated) },
                                  uniquingKeysWith: { first, _ in first })
        let families = Dictionary(identical.map { ($0.path, $0.cloneFamily) },
                                  uniquingKeysWith: { first, _ in first })
        return DuplicateGroup(copies: SurvivingCopy.order(identical).map {
            DuplicateGroup.Copy(path: $0, bytes: occupied[$0] ?? 0,
                                cloneFamily: families[$0] ?? nil)
        })
    }

    /// The whole pipeline: size → prefix hash → full hash → groups, largest
    /// waste first. `partial` and `full` are injected so the pipeline can be
    /// tested without a disk and driven with real hashing in production.
    static func groups(files: [FileFacts], minBytes: Int,
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
