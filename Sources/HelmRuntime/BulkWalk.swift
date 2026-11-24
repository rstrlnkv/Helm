import Foundation

/// One entry a walk found, with everything the three callers need about it.
///
/// The fields are what `getattrlistbulk` hands back in one syscall per batch;
/// asking Foundation for the same facts costs a `resourceValues` per entry.
public struct BulkEntry: Sendable {
    public let path: String
    let isDirectory: Bool
    /// A plain file, as opposed to a socket, a fifo or a device node. The clone
    /// question is asked of regular files only, so the answer has to come out of
    /// the walk rather than be inferred from "not a directory".
    public let isRegularFile: Bool
    /// What the file occupies, which is what deleting it gives back. Agrees to
    /// the byte with `totalFileAllocatedSize`, compressed binaries included.
    public let allocatedBytes: Int
    /// What the file says it is — `st_size`, the figure the duplicate finder's
    /// size floor and its size groups are built on.
    public let logicalBytes: Int
    public let fileID: UInt64
    /// How many names this allocation wears. `FileWeight`'s ledger charges it
    /// once however many that is.
    let linkCount: Int
    public let modified: TimeInterval
    /// Finder's «Date Added» — the date the copy arrived in this directory,
    /// which is not the date it was made and is not carried along when a file is
    /// copied. `SurvivingCopy` decides which copy stays by it. Nil on a volume
    /// that does not keep one.
    public let added: Date?
}

/// The fast tree walk, in the one place every module can reach it.
///
/// `getattrlistbulk` returns a batch of entries **with their attributes** in one
/// syscall, and a small pool of threads keeps the disk busy while the caller
/// consumes what they find: several times faster than `FileManager.enumerator`
/// plus a `resourceValues` per entry. Architecture/ModulePattern.md § Bulk reads.
///
/// It decides nothing. Which directories are descended into is the caller's
/// predicate (the firmlink twin, the volume boundary, an application's
/// database, `~/Library` on the timer's path), so each gate stays with the
/// module that owns its reasons and keeps its own tests.
public enum BulkWalk {
    /// The gap between two progress or snapshot ticks of a scan. About three a
    /// second is what a person can read, and a publish per event would flood
    /// the main actor.
    public static let progressInterval: TimeInterval = 0.35

    /// One directory's files and the directories that would not open.
    ///
    /// Two lists rather than a result per entry, because the caller's loop runs
    /// once per batch and a per-entry callback would put the throttling, the
    /// progress and the pool back in every caller.
    public struct Batch: Sendable {
        public let files: [BulkEntry]
        /// **A directory that would not open is never an empty one.** Every TCC
        /// refusal arrives this way, and reporting nothing draws a genuine zero
        /// on a map whose whole job is where the space went.
        public let denied: [String]
    }

    /// A single-threaded walk takes a minute over a real home directory; eight
    /// threads is where the gain flattens.
    public static var defaultThreads: Int {
        ProcessInfo.processInfo.activeProcessorCount.clamped(to: 1...8)
    }

    // MARK: - Which volume a path is on

    /// A device identifier that never traps: no unsigned conversion, and an
    /// explicit "unknown" for paths that cannot be stat'ed.
    ///
    /// `dev_t` is **signed**, and synthetic volumes (Preboot, VM, network
    /// mounts) report negative ids. Converting one to an unsigned type traps at
    /// runtime, on a whole-disk scan and never on a home-directory one.
    public struct DeviceID: Equatable, Sendable {
        let raw: dev_t
        let known: Bool

        init(raw: dev_t) { self.raw = raw; self.known = true }
        private init() { self.raw = 0; self.known = false }
        static let unknown = DeviceID()

        /// An unknown device is never assumed to match: better to skip a
        /// directory than to wander onto another filesystem.
        public func matches(_ other: DeviceID) -> Bool {
            known && other.known && raw == other.raw
        }
    }

    /// The volume a path actually leads onto, mount points included.
    ///
    /// **A `stat`, and it has to be**: `ATTR_CMN_DEVID` from a bulk read
    /// describes a directory as its *parent's* filesystem holds it, so a mount
    /// point under `/Volumes` reads as the boot volume. A descent gate built on
    /// that would walk every mounted backup drive.
    public static func deviceID(of path: String) -> DeviceID {
        var status = stat()
        guard stat(path, &status) == 0 else { return .unknown }
        return DeviceID(raw: status.st_dev)
    }

    // MARK: - One directory

    /// Everything in one directory, or nil when it would not open.
    ///
    /// Nil rather than an empty list, and the distinction is the whole of
    /// `Batch.denied`: `EACCES` and `EPERM` carry every TCC refusal, and `EIO`,
    /// `ETIMEDOUT` and `ENOTDIR` carry a disk that is failing, has been
    /// unplugged, or was replaced under the walk.
    ///
    /// Symlinks are not yielded: they are neither descended nor sized, because
    /// the target belongs to whoever owns it. `FileManager` yields them at 0
    /// allocated bytes, so totals agree either way.
    static func children(of directory: String) -> [BulkEntry]? {
        let fd = open(directory, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var request = attributeRequest()
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var out: [BulkEntry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count <= 0 { break }
            var cursor = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                let parsed = fields(at: cursor.advanced(by: MemoryLayout<UInt32>.size))
                if let name = parsed.name, !name.isEmpty, !parsed.isSymlink {
                    out.append(parsed.entry(at: ScanPath.child(of: directory, name: name)))
                }
                cursor = cursor.advanced(by: length)
            }
        }
        return out
    }

    /// What one path is, without walking anything.
    ///
    /// The single-file twin of `children(of:)`, and the same parse — so "what
    /// does this file weigh" has one answer whether it was reached through a
    /// directory or named outright. `FSOPT_NOFOLLOW`, so a symlink answers about
    /// itself rather than about what it points at.
    static func entry(at path: String) -> BulkEntry? {
        var request = attributeRequest(named: false)
        var buffer = [UInt8](repeating: 0, count: 512)
        let status = buffer.withUnsafeMutableBytes { raw in
            getattrlist(path, &request, raw.baseAddress, raw.count, UInt32(FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { raw -> BulkEntry? in
            guard let base = raw.baseAddress else { return nil }
            // The leading `u_int32_t` is the length of what was returned, the
            // same as a bulk entry's.
            return fields(at: base.advanced(by: MemoryLayout<UInt32>.size)).entry(at: path)
        }
    }

    // MARK: - The walk

    /// Walks `root` on a pool of threads, handing each directory's entries to
    /// `consume` **on the calling thread**, one batch at a time.
    ///
    /// The consumer runs where it was called from and nowhere else, so whatever
    /// it builds needs no locking — that is what lets Disk build its tree while
    /// the walk is still going, and the reason the hand-off is a channel rather
    /// than a callback on a worker.
    ///
    /// - Parameter descends: asked of every directory found. False prunes the
    ///   subtree, not just the directory.
    /// - Returns: false when the walk was cancelled, so a caller that must not
    ///   report a partial answer can tell.
    @discardableResult
    public static func walk(root: String,
                            threads: Int = defaultThreads,
                            isCancelled: @escaping @Sendable () -> Bool = { false },
                            descends: @escaping @Sendable (BulkEntry) -> Bool = { _ in true },
                            consume: (Batch) -> Void) -> Bool {
        guard !isCancelled() else { return false }
        let queue = WorkQueue(initial: [root])
        let channel = BatchChannel()
        let group = DispatchGroup()

        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            DispatchQueue.concurrentPerform(iterations: threads.clamped(to: 1...64)) { _ in
                while let directory = queue.next() {
                    if isCancelled() { queue.finish(); return }
                    // **One pool per directory.** Reading one hands back
                    // autoreleased objects, and `concurrentPerform` drains no
                    // pool per iteration, so without it a walk costs everything
                    // it ever looked at rather than what it keeps.
                    autoreleasepool {
                        var files: [BulkEntry] = []
                        var directories: [String] = []
                        var denied: [String] = []
                        if let entries = children(of: directory) {
                            for entry in entries {
                                if !entry.isDirectory {
                                    files.append(entry)
                                } else if descends(entry) {
                                    directories.append(entry.path)
                                }
                            }
                        } else {
                            denied.append(directory)
                        }
                        queue.add(directories)
                        channel.push(files: files, denied: denied)
                        queue.completed()
                    }
                }
            }
            channel.close()
        }

        while let batch = channel.pop() {
            // And one pool per batch. The consumer runs on the caller's thread,
            // often inside `offTheCooperativePool`, where otherwise the only pool
            // that drains is the one closing when the whole scan returns.
            autoreleasepool { consume(batch) }
        }
        group.wait()
        return !isCancelled()
    }

    // MARK: - getattrlist

    /// The attributes every caller between them needs, requested once.
    ///
    /// Asking for fewer per caller would mean a second parse and a second field
    /// order to get wrong; the cost of a field nobody reads is bytes in a buffer
    /// that is allocated either way.
    private static func attributeRequest(named: Bool = true) -> attrlist {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | (named ? attrgroup_t(ATTR_CMN_NAME) : 0)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FILEID)
            | attrgroup_t(ATTR_CMN_ADDEDTIME)
        request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT)
            | attrgroup_t(ATTR_FILE_ALLOCSIZE)
            | attrgroup_t(ATTR_FILE_DATALENGTH)
        return request
    }

    /// One entry's fields, before it is given a path.
    private struct Fields {
        var name: String?
        var isDirectory = false
        var isSymlink = false
        var isRegularFile = false
        var modified: TimeInterval = 0
        var added: Date?
        var fileID: UInt64 = 0
        var linkCount = 1
        var allocated = 0
        var logical = 0

        func entry(at path: String) -> BulkEntry {
            BulkEntry(path: path, isDirectory: isDirectory, isRegularFile: isRegularFile,
                      allocatedBytes: allocated, logicalBytes: logical, fileID: fileID,
                      linkCount: linkCount, modified: modified, added: added)
        }
    }

    /// Reads the fields of one entry, starting just past its length word.
    ///
    /// **Every read is unaligned and every field is conditional.** The kernel
    /// packs the fields back to back with no padding, so an aligned load traps
    /// on the first `UInt64` at an odd offset. They arrive in **attribute bit
    /// order**, not request order: `ATTR_FILE_LINKCOUNT` (0x1) comes before
    /// `ATTR_FILE_ALLOCSIZE` (0x4), and reading them out of order yields garbage
    /// sizes that overflow the sum.
    private static func fields(at start: UnsafeRawPointer) -> Fields {
        var field = start
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size
        var fields = Fields()

        if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
            let reference = field.loadUnaligned(as: attrreference_t.self)
            fields.name = String(cString: field.advanced(by: Int(reference.attr_dataoffset))
                .assumingMemoryBound(to: CChar.self))
            field += MemoryLayout<attrreference_t>.size
        }
        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            let type = field.loadUnaligned(as: fsobj_type_t.self)
            fields.isDirectory = type == UInt32(VDIR.rawValue)
            fields.isSymlink = type == UInt32(VLNK.rawValue)
            fields.isRegularFile = type == UInt32(VREG.rawValue)
            field += MemoryLayout<fsobj_type_t>.size
        }
        if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
            let stamp = field.loadUnaligned(as: timespec.self)
            fields.modified = TimeInterval(stamp.tv_sec)
                + TimeInterval(stamp.tv_nsec) / 1_000_000_000
            field += MemoryLayout<timespec>.size
        }
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fields.fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        if returned.commonattr & attrgroup_t(ATTR_CMN_ADDEDTIME) != 0 {
            let stamp = field.loadUnaligned(as: timespec.self)
            // **Built through the reference date, not through 1970.** A `Date`
            // holds an interval since 2001, and subtracting the epoch after
            // composing loses the last bits, so the answer can differ from
            // `URLResourceValues.addedToDirectoryDate` by a fraction of a
            // microsecond. Subtracting from the whole seconds first matches
            // Foundation exactly; the date decides which duplicate survives, and
            // one file must not have two answers.
            fields.added = Date(timeIntervalSinceReferenceDate:
                                TimeInterval(stamp.tv_sec)
                                - Date.timeIntervalBetween1970AndReferenceDate
                                + TimeInterval(stamp.tv_nsec) / 1_000_000_000)
            field += MemoryLayout<timespec>.size
        }
        // The file group, and only what was returned: a directory is asked
        // these and answers none of them.
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            fields.linkCount = Int(field.loadUnaligned(as: UInt32.self))
            field += MemoryLayout<UInt32>.size
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            fields.allocated = Int(field.loadUnaligned(as: off_t.self))
            field += MemoryLayout<off_t>.size
        }
        if returned.fileattr & attrgroup_t(ATTR_FILE_DATALENGTH) != 0 {
            fields.logical = Int(field.loadUnaligned(as: off_t.self))
        }
        return fields
    }

    // MARK: - The pool

    /// Producer–consumer hand-off between walk workers and the caller.
    private final class BatchChannel: @unchecked Sendable {
        private let condition = NSCondition()
        private var batches: [Batch] = []
        private var closed = false

        func push(files: [BulkEntry], denied: [String]) {
            guard !files.isEmpty || !denied.isEmpty else { return }
            condition.lock()
            batches.append(Batch(files: files, denied: denied))
            condition.signal()
            condition.unlock()
        }

        func close() {
            condition.lock()
            closed = true
            condition.broadcast()
            condition.unlock()
        }

        /// nil once the walk is done and everything has been drained.
        func pop() -> Batch? {
            condition.lock()
            defer { condition.unlock() }
            while batches.isEmpty && !closed { condition.wait() }
            return batches.isEmpty ? nil : batches.removeFirst()
        }
    }

    /// Shared directory queue. Workers block while others still have work, so a
    /// deep-but-narrow tree keeps every thread fed instead of exiting early.
    private final class WorkQueue: @unchecked Sendable {
        private let condition = NSCondition()
        private var pending: [String]
        private var active = 0
        private var stopped = false

        init(initial: [String]) { pending = initial }

        func next() -> String? {
            condition.lock()
            defer { condition.unlock() }
            while true {
                if stopped { return nil }
                if let path = pending.popLast() {
                    active += 1
                    return path
                }
                if active == 0 { return nil }        // nobody can produce more
                condition.wait()
            }
        }

        func add(_ paths: [String]) {
            guard !paths.isEmpty else { return }
            condition.lock()
            pending.append(contentsOf: paths)
            condition.broadcast()
            condition.unlock()
        }

        func completed() {
            condition.lock()
            active -= 1
            if active == 0 && pending.isEmpty { condition.broadcast() }
            condition.unlock()
        }

        func finish() {
            condition.lock()
            stopped = true
            condition.broadcast()
            condition.unlock()
        }
    }
}
