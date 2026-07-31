import Foundation

/// What removing a copy actually returns to the disk.
///
/// On APFS a *clone* shares its blocks with the file it was made from, and
/// Finder's Duplicate command makes clones — so this is the ordinary case. The
/// file's own size says nothing about it: measured on this machine, a 20 MB
/// file cloned with `cp -c` cost **0 bytes** of free space while a real copy
/// cost 20 MB, and `stat` reported 40 960 allocated blocks for both.
///
/// `ATTR_CMNEXT_CLONEID` is what separates them: every file in one clone family
/// reports the same id (measured: original and clone 93259253, a real copy
/// 93259305). The blocks come back only when the family's last member goes.
public enum CloneShare {

    /// The clone family a file belongs to, or `nil` when the volume has no such
    /// notion or the read failed — a file whose id cannot be read is counted as
    /// its own, because under-reporting space somebody really gets back is the
    /// worse error of the two.
    public static func familyID(ofFileAt path: String) -> UInt64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_CLONEID)
        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            getattrlist(path, &request, raw.baseAddress, raw.count,
                        UInt32(FSOPT_ATTR_CMN_EXTENDED))
        }
        guard status == 0 else { return nil }
        // The first four bytes are the returned length; the id follows it, and
        // it is not aligned for a direct load.
        var id: UInt64 = 0
        withUnsafeMutableBytes(of: &id) { destination in
            buffer.withUnsafeBytes { source in
                destination.copyBytes(from: UnsafeRawBufferPointer(rebasing: source[4..<12]))
            }
        }
        return id
    }

    /// Bytes the disk gains when `removing` goes and `keeping` stays.
    ///
    /// A family with a survivor gives back nothing, however many of its members
    /// are removed. A family with no survivor gives back its blocks once, not
    /// once per member.
    public static func reclaimable(removing: [(id: UInt64?, bytes: Int)],
                                   keeping: [UInt64?]) -> Int {
        let survivors = Set(keeping.compactMap { $0 })
        var countedFamilies: Set<UInt64> = []
        var total = 0
        for file in removing {
            guard let family = file.id else {
                // No clone family: nothing shares these blocks.
                total += file.bytes
                continue
            }
            guard !survivors.contains(family) else { continue }
            guard countedFamilies.insert(family).inserted else { continue }
            total += file.bytes
        }
        return total
    }
}
