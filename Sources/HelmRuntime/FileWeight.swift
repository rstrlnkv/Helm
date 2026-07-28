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
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey,
                                      .isPackageKey, .fileResourceIdentifierKey,
                                      .isRegularFileKey, .linkCountKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        // A package is a directory wearing one icon. It has to be walked for the
        // same reason and reports the same zero if it is not.
        let holdsThings = (values.isDirectory ?? false) || (values.isPackage ?? false)
        guard holdsThings else { return once(url, values, &seen) }

        var total = 0
        // Hidden files are not skipped: they are freed along with the folder and
        // belong in the figure.
        let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let item = items?.nextObject() as? URL {
            guard let v = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            total += once(item, v, &seen)
        }
        return total
    }

    /// The entry's bytes, unless another name for the same file already
    /// contributed them. Only a file with more than one link can collide, so
    /// the common case costs one comparison.
    private static func once(_ url: URL, _ values: URLResourceValues,
                             _ seen: inout Set<UInt64>) -> Int {
        let bytes = values.totalFileAllocatedSize ?? 0
        guard (values.linkCount ?? 1) > 1 else { return bytes }
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return bytes }
        return seen.insert(UInt64(status.st_ino)).inserted ? bytes : 0
    }
}
