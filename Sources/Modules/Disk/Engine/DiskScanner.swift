import Foundation
import HelmRuntime

struct ScanProgress: Sendable {
    let filesSeen: Int
    let bytesSeen: Int
    let currentPath: String
}

/// Walks a directory tree with `getattrlistbulk` — one syscall returns a
/// batch of entries WITH their attributes, which is why MacDirStat-style
/// scanners outrun FileManager by an order of magnitude. Techniques
/// referenced, code our own.
final class DiskScanner: @unchecked Sendable {
    private let foldThreshold: Int
    private var cancelled = false
    private let lock = NSLock()

    /// `skip` is injected only by tests; production reads the live firmlink
    /// table for the scan root.
    private let injectedSkip: Set<String>?

    /// Stop at an application's own database rather than walking into it.
    ///
    /// Off for a scan a person asked for and is watching: this screen's whole
    /// job is where the space went, and a photo library is often the largest
    /// thing on the volume — refusing to measure it would be a lie of omission
    /// in the one place that must not tell one. On for a scan nobody is
    /// watching, where the cost of walking in is a consent dialog at an empty
    /// chair (`ScanRoot.refusesDescent`).
    private let unattended: Bool

    init(foldThreshold: Int = 32 * 1024, skip: Set<String>? = nil,
         unattended: Bool = false) {
        self.foldThreshold = foldThreshold
        self.injectedSkip = skip
        self.unattended = unattended
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Synchronous; run it via the module's `blocking` bridge.
    ///
    /// Directories are walked by a small pool of threads (a single-threaded
    /// walk measured 4.7k files/s — 63 s on a real home directory). Tree
    /// building stays on THIS thread, consuming worker batches as they land,
    /// so TreeBuilder needs no locking — and because the tree exists while the
    /// walk runs, `onPartial` can hand the UI snapshots for a ring that grows
    /// live instead of a spinner.
    func scan(root: String,
              onProgress: (@Sendable (ScanProgress) -> Void)? = nil,
              onPartial: (@Sendable (DiskNode) -> Void)? = nil) -> DiskNode? {
        let builder = TreeBuilder(root: root, foldThreshold: foldThreshold)
        let rootDev = deviceID(of: root)
        // The Data volume is reachable both directly and through the firmlinks
        // that make up `/`; its duplicate side is skipped so bytes land where
        // the user expects them (FirmlinkMap has the why).
        let skip = injectedSkip ?? FirmlinkMap.skipSet(scanRoot: root)
        var filesSeen = 0
        var bytesSeen = 0
        var lastPath = root

        let queue = WorkQueue(initial: [root])
        let workerCount = ProcessInfo.processInfo.activeProcessorCount.clamped(to: 1...8)
        let channel = BatchChannel()

        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            DispatchQueue.concurrentPerform(iterations: workerCount) { _ in
                while let dir = queue.next() {
                    if self.isCancelled { queue.finish(); return }
                    // One pool per directory. `readDirectory` goes through
                    // Foundation, which hands back autoreleased objects, and
                    // `concurrentPerform` drains no pool per iteration — over a
                    // million and a half entries that is the difference between
                    // a scan that costs its tree and one that costs everything
                    // it ever looked at. Same defect as the duplicate finder's
                    // read loop, one framework call further out.
                    autoreleasepool {
                    var files: [Entry] = []
                    var directories: [String] = []
                    var denied: [String] = []

                    switch self.readDirectory(dir) {
                    case .denied:
                        denied.append(dir)
                    case .entries(let entries):
                        for entry in entries {
                            if entry.isDirectory {
                                // Before the device check, because that one
                                // stats the path and the point is to touch an
                                // application's database as little as reading
                                // its parent already did.
                                if self.unattended,
                                   ScanRoot.refusesDescent(into: entry.path) {
                                    continue
                                }
                                if !skip.contains(entry.path),
                                   self.deviceID(of: entry.path).matches(rootDev) {
                                    directories.append(entry.path)
                                }
                            } else {
                                files.append(entry)
                            }
                        }
                    }
                    queue.add(directories)
                    channel.push(files: files, denied: denied)
                    queue.completed()
                    }
                }
            }
            channel.close()
        }

        var lastEmit = Date()
        while let batch = channel.pop() {
            // One pool per batch, and the second of the two this walk needs.
            // The workers' pool covers what `readDirectory` asks Foundation
            // for; *this* is where the path strings are made — `TreeBuilder`
            // bridges through `NSString` twice per file and once more per
            // ancestor level, all of it autoreleased. This loop runs on the
            // caller's thread inside `offTheCooperativePool`, so without a pool
            // here the only one that ever drains is the one closing when the
            // whole scan returns: measured at 524 bytes a file over a fixture
            // 16 levels deep, against 4 with this (`ScanFootprintTests`).
            autoreleasepool {
                for path in batch.denied { builder.markNoAccess(path: path) }
                for entry in batch.files {
                    builder.addFile(path: entry.path, bytes: entry.allocatedBytes,
                                    fileID: entry.fileID, modified: entry.modified)
                    filesSeen += 1
                    bytesSeen += entry.allocatedBytes
                    lastPath = entry.path
                }
                let now = Date()
                if now.timeIntervalSince(lastEmit) > 0.35 {
                    lastEmit = now
                    onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen,
                                             currentPath: lastPath))
                    // The builder thread owns the tree, so snapshotting here
                    // races with nothing.
                    onPartial?(builder.build())
                }
            }
        }
        group.wait()

        if isCancelled { return nil }
        onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen, currentPath: root))
        return builder.build()
    }

    /// Producer–consumer hand-off between walk workers and the builder thread.
    private final class BatchChannel: @unchecked Sendable {
        struct Batch { let files: [Entry]; let denied: [String] }

        private let condition = NSCondition()
        private var batches: [Batch] = []
        private var closed = false

        func push(files: [Entry], denied: [String]) {
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

    /// Shared directory queue. Workers block while others still have work, so
    /// a deep-but-narrow tree keeps every thread fed instead of exiting early.
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

    // MARK: - getattrlistbulk

    /// A device identifier that never traps: no unsigned conversion, and an
    /// explicit "unknown" for paths that cannot be stat'ed.
    struct DeviceID: Equatable {
        let raw: dev_t
        let known: Bool

        init(raw: dev_t) { self.raw = raw; self.known = true }
        private init() { self.raw = 0; self.known = false }
        static let unknown = DeviceID()

        /// An unknown device is never assumed to match: better to skip a
        /// directory than to wander onto another filesystem.
        func matches(_ other: DeviceID) -> Bool { known && other.known && raw == other.raw }
    }

    private struct Entry {
        let path: String
        let isDirectory: Bool
        let allocatedBytes: Int
        let fileID: UInt64
        let modified: TimeInterval
    }

    private enum ReadOutcome {
        case entries([Entry])
        case denied
    }

    /// `dev_t` is SIGNED, and synthetic volumes (Preboot, VM, network mounts)
    /// report negative ids. Converting one to an unsigned type traps at
    /// runtime — that is what crashed a whole-disk scan while a home-directory
    /// scan, whose ids happen to be positive, passed. No conversion: compare
    /// the value the kernel gave us.
    private func deviceID(of path: String) -> DeviceID {
        var st = stat()
        guard stat(path, &st) == 0 else { return .unknown }
        return DeviceID(raw: st.st_dev)
    }

    private func readDirectory(_ path: String) -> ReadOutcome {
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else {
            // **A directory that would not open is never an empty one.** This
            // used to answer `.entries([])` for everything but `EACCES` and
            // `EPERM` — the right side of that line carries every TCC refusal
            // (measured: `~/Library/Mail`, `~/Library/Messages`, `~/Library/Safari`
            // and a Photos library all answer `EPERM`), and the wrong side
            // carried a disk that is failing or has been unplugged (`EIO`,
            // `ETIMEDOUT`) and a directory replaced under the walk (`ENOTDIR`,
            // errno 20). Each of those was drawn as a genuine zero on a map
            // whose whole job is where the space went.
            //
            // `noAccess` is the only signal the tree has, and it is the honest
            // half of all of them: the walk did not get in, so nothing below is
            // counted. The row's word is «No access», which for a vanished
            // folder is imprecise and for none of them is a lie about size.
            return .denied
        }
        defer { close(fd) }

        // getattrlistbulk packs fields back to back with no padding, so every
        // read must be unaligned — an aligned load traps on the first UInt64
        // that lands on an odd offset.
        // Fields come back in ATTRIBUTE BIT ORDER, not in the order they are
        // requested — reading them in request order silently misparses every
        // entry. Kept to the minimum set for that reason:
        //   RETURNED_ATTRS (always first), NAME (0x1), OBJTYPE (0x8),
        //   MODTIME (0x400, a timespec), FILEID (0x2000000), then fileattr
        //   ALLOCSIZE.
        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME)
            | attrgroup_t(ATTR_CMN_FILEID)
        attrList.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)

        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var out: [Entry] = []
        while true {
            let count = getattrlistbulk(fd, &attrList, buffer, bufferSize, 0)
            if count <= 0 { break }

            var cursor = buffer
            for _ in 0..<count {
                let entryStart = cursor
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                var field = cursor.advanced(by: MemoryLayout<UInt32>.size)

                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size

                var name = ""
                if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                    let ref = field.loadUnaligned(as: attrreference_t.self)
                    let nameStart = field.advanced(by: Int(ref.attr_dataoffset))
                    name = String(cString: nameStart.assumingMemoryBound(to: CChar.self))
                    field += MemoryLayout<attrreference_t>.size
                }

                var isDirectory = false
                if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                    let type = field.loadUnaligned(as: fsobj_type_t.self)
                    isDirectory = type == UInt32(VDIR.rawValue)
                    // Symlinks (VLNK) are neither descended nor sized: their
                    // targets belong to whoever owns them.
                    if type == UInt32(VLNK.rawValue) {
                        cursor = entryStart.advanced(by: length)
                        continue
                    }
                    field += MemoryLayout<fsobj_type_t>.size
                }

                var modified: TimeInterval = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                    let ts = field.loadUnaligned(as: timespec.self)
                    modified = TimeInterval(ts.tv_sec)
                    field += MemoryLayout<timespec>.size
                }

                var fileID: UInt64 = 0
                if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self)
                    field += MemoryLayout<UInt64>.size
                }

                var allocated = 0
                if !isDirectory, returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                    allocated = Int(field.loadUnaligned(as: off_t.self))
                }

                if !name.isEmpty {
                    out.append(Entry(path: ScanPath.child(of: path, name: name),
                                     isDirectory: isDirectory,
                                     allocatedBytes: allocated, fileID: fileID,
                                     modified: modified))
                }
                cursor = entryStart.advanced(by: length)
            }
        }
        return .entries(out)
    }
}
