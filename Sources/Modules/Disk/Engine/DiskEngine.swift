import Foundation
import HelmContract
import HelmRuntime

/// Scans volumes and folders, and trashes what the user baskets. Long work
/// goes through `blocking` so the concurrency pool is never parked.
public final class DiskEngine: ModuleEngine, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    /// Guards the in-flight scanner. A plain NSLock cannot be taken from an
    /// async context, so the box confines it to a serial queue.
    private let scannerBox = ScannerBox()
    private let duplicateBox = DuplicateBox()

    public init(transport: LocalTransport = LocalTransport()) {
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {
        cancel()
        duplicateBox.current?.cancel()
    }

    public func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable == true,
                  let total = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacity else { return nil }
            return VolumeInfo(name: values.volumeName ?? url.lastPathComponent,
                              path: url.path, totalBytes: total, freeBytes: free)
        }
    }

    public func scan(path: String) async -> ScanResult? {
        let scanner = DiskScanner()
        scannerBox.set(scanner)
        let started = Date()

        let counter = FileCounter()
        let freeNow = freeBytes(forPathOn: path)
        let result: ScanResult? = await blocking {
            guard let tree = scanner.scan(root: path, onProgress: { progress in
                counter.value = progress.filesSeen
                // Progress is broadcast so the UI can show it without polling.
                if let data = try? JSONEncoder().encode(
                    ScanTick(files: progress.filesSeen, bytes: progress.bytesSeen,
                             path: progress.currentPath)) {
                    self.localTransport.emit(EngineEvent(name: "progress", payload: data))
                }
            }, onPartial: { partialTree in
                // A shallow snapshot every ~0.35s: the ring grows while the
                // walk is still running.
                let snapshot = ScanResult(root: DiskEntry(partialTree, depth: 4),
                                          freeBytes: freeNow,
                                          filesScanned: counter.value, seconds: 0)
                if let data = try? JSONEncoder().encode(snapshot) {
                    self.localTransport.emit(EngineEvent(name: "partial", payload: data))
                }
            }) else { return nil }
            let free = self.freeBytes(forPathOn: path)
            return ScanResult(root: DiskEntry(tree, depth: 6), freeBytes: free,
                              filesScanned: counter.value,
                              seconds: Date().timeIntervalSince(started),
                              advice: DiskAdvisor.advise(root: tree,
                                                         home: NSHomeDirectory()))
        }
        scannerBox.set(nil)
        if let result {
            HelmLog.shared.info("disk", "scanned \(Redact.path(path)): \(result.filesScanned) files in "
                                + String(format: "%.1fs", result.seconds))
        }
        return result
    }

    public func cancel() { scannerBox.current?.cancel() }

    /// Free space of the volume a path lives on — the ring's dim sector.
    private func freeBytes(forPathOn path: String) -> Int {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity ?? 0
    }

    public func trash(_ paths: [String]) async -> DiskRemoval {
        await blocking {
            var removed: [String] = [], failed: [String] = []
            var freed = 0
            // Refused, not dropped. Filtering the loop meant a path the gate
            // rejected reached neither list, and the page then announced
            // "Removed — N freed" over a file still sitting there. Leftovers and
            // Uninstaller already report their refusals; this was the last one.
            let unique = Set(paths)
            let allowed = unique.filter { DiskSafety.isRemovable($0) }
            let refused = unique.subtracting(allowed)
            failed.append(contentsOf: refused)
            for path in refused {
                HelmLog.shared.warn("disk", "refused out-of-scope path: \(Redact.path(path))")
            }
            for path in allowed {
                let url = URL(fileURLWithPath: path)
                let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    removed.append(path); freed += size
                } catch {
                    failed.append(path)
                    HelmLog.shared.failure("disk", "trash refused \(Redact.path(path))", error)
                }
            }
            HelmLog.shared.info("disk", "trashed \(removed.count), failed \(failed.count)")
            return DiskRemoval(removed: removed, failed: failed, freedBytes: freed)
        }
    }

    private func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    /// The second look: identical files under one folder. Serialized through
    /// the same box discipline as the scanner so "cancel" reaches it.
    public func duplicates(under path: String) async -> [DuplicateGroup]? {
        // A new search supersedes any still running: the engine does not rely
        // on the view model's guard for that.
        duplicateBox.current?.cancel()
        let finder = DuplicateScanner()
        duplicateBox.set(finder)
        let groups: [DuplicateGroup]? = await blocking {
            finder.find(under: path, onProgress: { progress in
                if let data = try? JSONEncoder().encode(progress) {
                    self.localTransport.emit(EngineEvent(name: "dupProgress", payload: data))
                }
            })
        }
        duplicateBox.set(nil)
        return groups
    }

    private struct PathPayload: Codable { let path: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "volumes":
                return (try? JSONEncoder().encode(self.volumes())) ?? Data()
            case "scan":
                guard let payload = try? JSONDecoder().decode(PathPayload.self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.scan(path: payload.path))) ?? Data()
            case "cancel":
                self.cancel()
                return Data()
            case "duplicates":
                guard let payload = try? JSONDecoder().decode(PathPayload.self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.duplicates(under: payload.path))) ?? Data()
            case "cancelDuplicates":
                self.duplicateBox.current?.cancel()
                return Data()
            case "trash":
                guard let paths = try? JSONDecoder().decode([String].self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.trash(paths))) ?? Data()
            default:
                return Data()
            }
        }
    }
}

/// Progress arrives from worker threads; the count needs a home that is safe
/// to write from any of them.
private final class FileCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Serial box around the in-flight duplicate search.
private final class DuplicateBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "helm.disk.duplicates")
    private var finder: DuplicateScanner?

    var current: DuplicateScanner? { queue.sync { finder } }
    func set(_ value: DuplicateScanner?) { queue.sync { finder = value } }
}

/// Serial box around the in-flight scanner.
private final class ScannerBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "helm.disk.scanner")
    private var scanner: DiskScanner?

    var current: DiskScanner? { queue.sync { scanner } }
    func set(_ value: DiskScanner?) { queue.sync { scanner = value } }
}

public struct ScanTick: Codable, Equatable, Sendable {
    public let files: Int
    public let bytes: Int
    public let path: String
}

public struct DiskRemoval: Codable, Equatable, Sendable {
    public let removed: [String]
    public let failed: [String]
    public let freedBytes: Int
}
