import Foundation

public struct ScanProgress: Sendable {
    public let filesSeen: Int
    public let bytesSeen: Int
    public let currentPath: String
}

/// Walks a directory tree with `getattrlistbulk` — one syscall returns a
/// batch of entries WITH their attributes, which is why MacDirStat-style
/// scanners outrun FileManager by an order of magnitude. Techniques
/// referenced, code our own.
public final class DiskScanner: @unchecked Sendable {
    private let foldThreshold: Int
    private var cancelled = false
    private let lock = NSLock()

    public init(foldThreshold: Int = 32 * 1024) {
        self.foldThreshold = foldThreshold
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Synchronous; run it via the module's `blocking` bridge.
    ///
    /// Directories are walked by a small pool of threads: a single-threaded
    /// walk measured 4.7k files/s on a real home directory (63 s for 296k
    /// files), which is not a usable wait. The work is syscall-bound, so
    /// parallel readers scale nearly linearly. Tree building stays on this
    /// thread — workers hand back batches, so TreeBuilder needs no locking.
    public func scan(root: String,
                     onProgress: (@Sendable (ScanProgress) -> Void)? = nil) -> DiskNode? {
        let builder = TreeBuilder(root: root, foldThreshold: foldThreshold)
        let rootDev = deviceID(of: root)
        var filesSeen = 0
        var bytesSeen = 0

        let queue = WorkQueue(initial: [root])
        let workerCount = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let results = ResultBox()

        DispatchQueue.concurrentPerform(iterations: workerCount) { _ in
            while let dir = queue.next() {
                if self.isCancelled { queue.finish(); return }
                var files: [Entry] = []
                var directories: [String] = []
                var denied: [String] = []

                switch self.readDirectory(dir) {
                case .denied:
                    denied.append(dir)
                case .entries(let entries):
                    for entry in entries {
                        if entry.isDirectory {
                            if self.deviceID(of: entry.path) == rootDev {
                                directories.append(entry.path)
                            }
                        } else {
                            files.append(entry)
                        }
                    }
                }
                queue.add(directories)
                results.append(files: files, denied: denied)
                queue.completed()
            }
        }

        if isCancelled { return nil }

        for path in results.denied { builder.markNoAccess(path: path) }
        for entry in results.files {
            builder.addFile(path: entry.path, bytes: entry.allocatedBytes, fileID: entry.fileID)
            filesSeen += 1
            bytesSeen += entry.allocatedBytes
            if filesSeen % 8192 == 0 {
                onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen,
                                         currentPath: entry.path))
            }
        }
        onProgress?(ScanProgress(filesSeen: filesSeen, bytesSeen: bytesSeen, currentPath: root))
        return builder.build()
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

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var files: [Entry] = []
        private(set) var denied: [String] = []

        func append(files newFiles: [Entry], denied newDenied: [String]) {
            guard !newFiles.isEmpty || !newDenied.isEmpty else { return }
            lock.lock()
            files.append(contentsOf: newFiles)
            denied.append(contentsOf: newDenied)
            lock.unlock()
        }
    }

    // MARK: - getattrlistbulk

    private struct Entry {
        let path: String
        let isDirectory: Bool
        let allocatedBytes: Int
        let fileID: UInt64
    }

    private enum ReadOutcome {
        case entries([Entry])
        case denied
    }

    private func deviceID(of path: String) -> UInt64 {
        var st = stat()
        guard stat(path, &st) == 0 else { return 0 }
        return UInt64(st.st_dev)
    }

    private func readDirectory(_ path: String) -> ReadOutcome {
        let fd = open(path, O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else {
            return errno == EACCES || errno == EPERM ? .denied : .entries([])
        }
        defer { close(fd) }

        // getattrlistbulk packs fields back to back with no padding, so every
        // read must be unaligned — an aligned load traps on the first UInt64
        // that lands on an odd offset.
        // Fields come back in ATTRIBUTE BIT ORDER, not in the order they are
        // requested — reading them in request order silently misparses every
        // entry. Kept to the minimum set for that reason:
        //   RETURNED_ATTRS (always first), NAME (0x1), OBJTYPE (0x8),
        //   FILEID (0x2000000), then fileattr ALLOCSIZE.
        var attrList = attrlist()
        attrList.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
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
                    out.append(Entry(path: path + "/" + name, isDirectory: isDirectory,
                                     allocatedBytes: allocated, fileID: fileID))
                }
                cursor = entryStart.advanced(by: length)
            }
        }
        return .entries(out)
    }
}
