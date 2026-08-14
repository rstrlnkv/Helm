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
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey,
                                      .isPackageKey, .fileResourceIdentifierKey,
                                      .isRegularFileKey, .linkCountKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        // A package is a directory wearing one icon. It has to be walked for the
        // same reason and reports the same zero if it is not.
        let holdsThings = (values.isDirectory ?? false) || (values.isPackage ?? false)
        guard holdsThings else { return once(url, values, &ledger) }

        var total = 0
        // Hidden files are not skipped: they are freed along with the folder and
        // belong in the figure.
        let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let item = items?.nextObject() as? URL {
            guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            total += once(item, v, &ledger)
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
    private static func once(_ url: URL, _ values: URLResourceValues,
                             _ ledger: inout Ledger) -> Int {
        let bytes = values.totalFileAllocatedSize ?? 0
        if (values.linkCount ?? 1) > 1 {
            var status = stat()
            if lstat(url.path, &status) == 0,
               !ledger.inodes.insert(UInt64(status.st_ino)).inserted { return 0 }
        }
        guard ledger.asksAboutClones, values.isRegularFile ?? false,
              let family = CloneShare.familyID(ofFileAt: url.path) else { return bytes }
        return ledger.families.insert(family).inserted ? bytes : 0
    }
}
