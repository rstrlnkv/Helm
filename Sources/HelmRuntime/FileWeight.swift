import Foundation

/// What a path occupies on disk.
///
/// Three places asked this and each answered differently, and two of the three
/// answers were zero for the case that matters most.
///
/// `totalFileAllocatedSize` on a directory reports the directory entry, and on
/// APFS that is **zero**. So a folder trashed by Disk freed nothing, and an
/// application bundle — which `URLResourceValues` calls a package, not a
/// directory — reported itself to Autopilot's rules as a file of no size at
/// all. A rule reading "smaller than 1 MB, move to Trash" therefore matched
/// every application in the watched folder, on a timer, with nobody looking.
///
/// The walk is the only honest answer for anything that contains things. It is
/// bounded by the path it is given and paid once per file.
public enum FileWeight {

    /// Bytes allocated to `url`, walking it when it holds other things.
    ///
    /// Allocated rather than logical: it is what deleting gives back, which is
    /// the question every caller is actually asking.
    public static func allocated(of url: URL) -> Int {
        var seen: Set<UInt64> = []
        return allocated(of: url, countingOnce: &seen)
    }

    /// `countingOnce` carries the file ids already counted, so a batch answers
    /// what the batch frees.
    ///
    /// A hard link is one allocation wearing several names, and deleting the
    /// second name frees nothing. `DiskScanner` has always known that — its
    /// tree counts an inode once — while the removal that follows counted each
    /// name, so the ring said 400 KB and the banner underneath said 800 KB
    /// about the same removal.
    public static func allocated(of url: URL, countingOnce seen: inout Set<UInt64>) -> Int {
        var ledger = Ledger(inodes: seen, asksAboutClones: false)
        defer { seen = ledger.inodes }
        return weigh(url, &ledger)
    }

    /// The books one removal keeps: an allocation is charged once however many
    /// names it wears, and a **clone family** once however many of its members
    /// the batch takes.
    ///
    /// Its own type rather than a second `Set` parameter, because the two rules
    /// are one question — "what does this batch give the disk back" — and a
    /// caller that carried one set and forgot the other would answer it half
    /// right, which is exactly how the clone half came to be missing.
    public struct Ledger {
        fileprivate var inodes: Set<UInt64> = []
        fileprivate var families: Set<UInt64> = []
        /// False where the caller is asking what a path *occupies* rather than
        /// what removing it returns — the clone question costs a `getattrlist`
        /// per file and is only worth asking on the removal path.
        fileprivate let asksAboutClones: Bool

        public init() { asksAboutClones = true }

        /// The books of a batch that leaves some files behind.
        ///
        /// `sharedWith` names paths that **stay**, and their clone families are
        /// entered as already counted — so a member of one that the batch does
        /// take gives nothing back, which is what the disk does. Without it the
        /// ledger can only see families whose members are all inside the batch,
        /// and in Duplicates that is none of them: the copy that stays is by
        /// construction excluded from the plan. Measured on a `clonefile` pair,
        /// the batch reported 8 003 584 bytes freed where the disk gains
        /// 4 001 792.
        public init(sharedWith paths: [String]) {
            asksAboutClones = true
            families = Set(paths.compactMap(CloneShare.familyID(ofFileAt:)))
        }

        fileprivate init(inodes: Set<UInt64>, asksAboutClones: Bool) {
            self.inodes = inodes
            self.asksAboutClones = asksAboutClones
        }
    }

    /// Bytes the disk gets back when `url` goes, charged against a batch's books.
    ///
    /// **A clone shares its blocks with the file it was made from, and Finder's
    /// Duplicate command makes clones**, so this is the ordinary case rather than
    /// an exotic one (ARCHITECTURE.md § What a copy actually costs). Weighed a
    /// name at a time, a folder of three duplicates reported three times the
    /// blocks it holds, and the banner promised space the disk cannot give back.
    ///
    /// What this can*not* see is a member of the family that is **not** in the
    /// batch: there is no reverse lookup from a family to its members, so a lone
    /// clone whose twin lives on elsewhere is still charged in full. That is the
    /// direction `CloneShare` chose deliberately — under-reporting space somebody
    /// really gets back is the worse error of the two.
    public static func reclaimed(of url: URL, charging ledger: inout Ledger) -> Int {
        weigh(url, &ledger)
    }

    private static func weigh(_ url: URL, _ ledger: inout Ledger) -> Int {
        // **The walk, not `resourceValues`.** The same tree, measured on this
        // Mac warm and compiled `-O`: the forty bundles in `/Applications` cost
        // 3,50–3,63 s enumerated and 1,1–1,2 s walked, which is the four seconds
        // of «Counting apps…» the Uninstaller opened with.
        //
        // `BulkWalk.entry` rather than `isDirectory`: a resource value follows a
        // symlink, so a link to a folder would be charged the folder — and this
        // is also what makes the package case ordinary rather than special. A
        // package is a directory wearing one icon; `st_mode` has always said so,
        // and it was `URLResourceValues` calling it a file that reported an
        // application bundle as weighing nothing at all.
        guard let root = BulkWalk.entry(at: url.path) else { return 0 }
        guard root.isDirectory else { return once(root, &ledger) }

        var total = 0
        // Hidden files are not skipped: they are freed along with the folder and
        // belong in the figure.
        BulkWalk.walk(root: url.path) { batch in
            for file in batch.files { total += once(file, &ledger) }
        }
        return total
    }

    /// The entry's bytes, unless another name for the same allocation already
    /// contributed them — a second hard link to it, or a clone of it earlier in
    /// the same batch.
    ///
    /// Only a file with more than one link can collide by inode, so the common
    /// case costs one comparison; the clone question is asked of regular files
    /// only, and only on the removal path (`Ledger.asksAboutClones`).
    ///
    /// The link count and the file id both come out of the walk now. They used
    /// to cost a `resourceValues` and, for anything with a second name, an
    /// `lstat` on top of it.
    private static func once(_ entry: BulkEntry, _ ledger: inout Ledger) -> Int {
        let bytes = entry.allocatedBytes
        if entry.linkCount > 1, !ledger.inodes.insert(entry.fileID).inserted { return 0 }
        guard ledger.asksAboutClones, entry.isRegularFile,
              let family = CloneShare.familyID(ofFileAt: entry.path) else { return bytes }
        return ledger.families.insert(family).inserted ? bytes : 0
    }
}
