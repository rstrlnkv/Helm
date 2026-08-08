import Foundation
import HelmContract
import HelmRuntime

/// Scans volumes and folders, and trashes what the user baskets. Long work
/// goes through `blocking` so the concurrency pool is never parked.
public final class DiskEngine: ModuleEngine, BackgroundScanning, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    /// Every scan in flight, not the last one started: drilling into a folder
    /// the walk never reached starts a second scan beside the first.
    private let scanners = ScanRegistry<DiskScanner>()

    public init(transport: LocalTransport = LocalTransport()) {
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {
        cancel()
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

    /// `scan` is the caller's name for this measurement, echoed on every event
    /// it produces. Two scans share one transport — the volume walk and the
    /// folder measurement a drill starts — and a snapshot that does not say
    /// which one it belongs to was drawn as though it belonged to the other.
    /// The boot volume, walked by the timer instead of by a person.
    ///
    /// **The finding is the advice, not the tree.** A disk scan answers "what
    /// occupies space", which is a picture rather than a list of things to
    /// remove — mapping every node of it into a report would promise a decision
    /// the module never made. `advice` is the part that already names specific
    /// paths worth reclaiming: caches past their threshold, big downloads
    /// nobody has touched in a month, huge files untouched for half a year.
    ///
    /// **No `ScanRoot` gate**, and not by omission. That gate guards a folder
    /// the person chose and Helm stored, where a rewritten plist would redirect
    /// an unattended reader. The root here is the boot volume, named in this
    /// line rather than read from anywhere.
    public func backgroundScan() async -> ScanReport? {
        guard let result = await scan(path: "/", unattended: true) else { return nil }
        let items = result.advice.map { ScanItem(path: $0.path, bytes: $0.bytes) }
        return ScanReport(bytes: items.reduce(0) { $0 + $1.bytes },
                          count: items.count, items: items)
    }

    /// - Parameter unattended: nobody is watching, so the walk stops at an
    ///   application's own database instead of asking macOS for permission to
    ///   read it at an empty chair. Defaults to false: a scan a person started
    ///   measures everything, because "where did the space go" must not quietly
    ///   omit the largest folder on the volume.
    public func scan(path: String, scan id: Int = 0,
                     unattended: Bool = false) async -> ScanResult? {
        let scanner = DiskScanner(unattended: unattended)
        let token = scanners.add(scanner)
        defer { scanners.remove(token) }
        // Registered for the whole scan, cancellation included. The pair is
        // `begin` + `defer` rather than `HelmActivity.phase`, because the phase
        // is this whole function body and wrapping it in a closure would put the
        // `await` below inside one; the `defer` is what makes it a scope, and
        // there must never be a `begin` without one.
        HelmActivity.begin("disk.scan")
        defer { HelmActivity.end("disk.scan") }
        let started = Date()

        let counter = FileCounter()
        let freeNow = freeBytes(forPathOn: path)
        let result: ScanResult? = await offTheCooperativePool {
            guard let tree = scanner.scan(root: path, onProgress: { progress in
                counter.value = progress.filesSeen
                // Progress is broadcast so the UI can show it without polling.
                self.localTransport.emit(DiskEvent.progress,
                                         encoding: ScanTick(scan: id, files: progress.filesSeen,
                                                            bytes: progress.bytesSeen,
                                                            path: progress.currentPath))
            }, onPartial: { partialTree in
                // A shallow snapshot every ~0.35s: the ring grows while the
                // walk is still running.
                let snapshot = ScanResult(root: DiskEntry(partialTree, depth: 4, path: path),
                                          freeBytes: freeNow,
                                          filesScanned: counter.value, seconds: 0)
                self.localTransport.emit(DiskEvent.partial,
                                         encoding: PartialScan(scan: id, result: snapshot))
            }) else { return nil }
            let free = self.freeBytes(forPathOn: path)
            return ScanResult(root: DiskEntry(tree, depth: 6, path: path), freeBytes: free,
                              filesScanned: counter.value,
                              seconds: Date().timeIntervalSince(started),
                              advice: DiskAdvisor.advise(root: tree, rootPath: path,
                                                         home: NSHomeDirectory()))
        }
        // The reclaim is owed whether the scan finished or was stopped — and Stop
        // is pressed when the footprint is at its highest, because that is why
        // the person pressed it. It used to sit inside `if let result`, so a
        // cancelled walk of a volume handed nothing back to macOS and wrote
        // nothing to the trail. Only the sentence about what was found belongs
        // on the success path.
        HelmLog.shared.memory("disk.scan")
        if let result {
            HelmLog.shared.info("disk", "scanned \(LogRoot.label(path)): \(result.filesScanned) files in "
                                + String(format: "%.1fs", result.seconds))
        }
        return result
    }

    /// Stops everything walking. A volume scan the user cannot stop is the
    /// worst of the two mistakes available here, so this asks every scan in
    /// flight rather than the one that started last.
    public func cancel() { scanners.inFlight.forEach { $0.cancel() } }

    /// Free space of the volume a path lives on — the ring's dim sector.
    private func freeBytes(forPathOn path: String) -> Int {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity ?? 0
    }

    public func trash(_ paths: [String]) async -> DiskRemoval {
        await offTheCooperativePool {
            // Refused, not dropped. Filtering the loop meant a path the gate
            // rejected reached neither list, and the page then announced
            // "Removed — N freed" over a file still sitting there.
            // `UserFileScope.partition` is written to the same *shape* as
            // `RemovableScope.partition` and answers a different question —
            // what belongs to the user, not what belongs to an application.
            // The two are not interchangeable and the earlier wording here
            // ("one question, two spellings") read as an invitation to merge
            // them: wiring a module to the wrong gate is a real mistake with a
            // misleading symptom, and the duplicate finder shipped one
            // (ARCHITECTURE.md § Removal scope).
            let (allowed, refused) = UserFileScope.partition(Array(Set(paths)))
            return HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "disk")
        }
    }



    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            guard let name = DiskCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .volumes:
                return EngineReply.encode(self.volumes(), for: command)
            case .scan:
                guard let payload = EngineReply.decode(ScanRequest.self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.scan(path: payload.path, scan: payload.scan),
                                          for: command)
            case .backgroundScan:
                return EngineReply.encode(await self.backgroundScan(), for: command)
            case .cancel:
                self.cancel()
                return Data()
            case .trash:
                guard let paths = EngineReply.decode([String].self, from: command)
                else { return Data() }
                return EngineReply.encode(await self.trash(paths), for: command)
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


/// What to measure, and under whose name. The name comes from the caller
/// because the caller is the one who has to recognise the answer: the view
/// model knows which scan the screen belongs to before the first snapshot of it
/// exists.
public struct ScanRequest: Codable, Equatable, Sendable {
    public let path: String
    public let scan: Int

    public init(path: String, scan: Int = 0) {
        self.path = path
        self.scan = scan
    }
}

public struct ScanTick: Codable, Equatable, Sendable {
    /// Which scan is counting. Two can be walking at once.
    public let scan: Int
    public let files: Int
    public let bytes: Int
    public let path: String

    public init(scan: Int = 0, files: Int, bytes: Int, path: String) {
        self.scan = scan
        self.files = files
        self.bytes = bytes
        self.path = path
    }
}

/// A snapshot of a tree still being walked, with the scan it belongs to.
///
/// Without the name, a partial from a folder measurement was drawn as the
/// volume it was started from: the focus collapsed, the title went on naming
/// the volume, and the volume's free space was drawn against a folder — the
/// flat grey disc `recomputeSegments` exists to prevent. The volume's own next
/// snapshot swapped it back, so the ring oscillated until the walk finished.
public struct PartialScan: Codable, Equatable, Sendable {
    public let scan: Int
    public let result: ScanResult

    public init(scan: Int, result: ScanResult) {
        self.scan = scan
        self.result = result
    }
}

/// What the trash command answers with.
///
/// This was a field-for-field copy of `HelmTrash.Result` — the same three
/// stored properties in the same order, the same `failed`, the same
/// conformances — which the engine built and then unwrapped and re-wrapped for
/// no gain. The wire is unchanged by the alias and `RemovalWireFormatTests`
/// says so; `refused` still carries the reason, which is the only part worth
/// reading when Full Disk Access is the cause.
public typealias DiskRemoval = HelmTrash.Result
