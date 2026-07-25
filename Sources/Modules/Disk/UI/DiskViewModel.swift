import Foundation
import HelmUI
import Module_Disk_Engine

@MainActor public final class DiskViewModel: ObservableObject {
    public enum Phase: Equatable { case start, scanning, result }

    @Published public private(set) var phase: Phase = .start
    @Published public private(set) var volumes: [VolumeInfo] = []
    @Published public private(set) var result: ScanResult?
    @Published public private(set) var tick: ScanTick?
    /// Path stack from the scan root to the folder the ring is showing.
    @Published public private(set) var focusPath: [DiskEntry] = []
    /// Laid-out arcs for the current focus. Cached deliberately: recomputing
    /// layout in the view's body meant a full O(n) relayout on every hover
    /// frame — hovering only changes colours, never geometry.
    @Published public private(set) var segments: [RingSegment] = []
    /// True while partial snapshots are still feeding the ring.
    @Published public private(set) var live = false
    /// Which way the last navigation went — the ring's transition mirrors it.
    public enum NavDirection { case down, up, none }
    @Published public private(set) var navDirection: NavDirection = .none
    /// The scan root's human name: "Macintosh HD", not "/".
    @Published public private(set) var rootTitle = ""
    @Published public var basket: [DiskEntry] = []
    @Published public private(set) var banner: String?

    private let client: TransportClient
    private let vm: ModuleViewModel
    private var eventsTask: Task<Void, Never>?
    /// When the current result landed; drives the cache lifetime.
    private var completedAt: Date?

    /// Scan state must outlive the settings page — switching modules recreates
    /// the page, and losing a minute-long scan to a sidebar click is hostile.
    /// One instance for the app's lifetime; the page observes it.
    private static var cached: DiskViewModel?
    public static func shared(vm: ModuleViewModel) -> DiskViewModel {
        if let cached { return cached }
        let created = DiskViewModel(vm: vm)
        cached = created
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        client = TransportClient(vm.transport)
        // The VM owns the event loop, not the page: partial snapshots keep
        // building the tree even while the user is on another module.
        eventsTask = Task { [weak self] in await self?.observeEvents() }
    }

    /// A day-old tree is a guess, not a measurement. Called on page appear.
    public static let cacheLifetime: TimeInterval = 86_400
    public func expireIfStale(now: Date = Date()) {
        guard phase == .result, !live, let completedAt,
              now.timeIntervalSince(completedAt) > Self.cacheLifetime else { return }
        newScan()
    }

    public var focus: DiskEntry? { focusPath.last }
    public var basketBytes: Int { basket.reduce(0) { $0 + $1.bytes } }

    public func loadVolumes() async {
        volumes = await client.request("volumes") ?? []
    }

    public func scan(path: String) async {
        // "/" is a path, not a name; the volume list knows what to call it.
        rootTitle = volumes.first { $0.path == path }?.name
            ?? ((path as NSString).lastPathComponent.isEmpty ? path
                : (path as NSString).lastPathComponent)
        navDirection = .none
        phase = .scanning
        live = true
        tick = nil
        banner = nil
        let scan: ScanResult? = await client.request("scan", encoding: ["path": path])
        live = false
        guard let scan else {                    // cancelled
            phase = .start
            return
        }
        result = scan
        completedAt = Date()
        // The user may have drilled into a partial tree; find the same spot in
        // the final one instead of yanking them back to the root.
        focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: scan.root)
        phase = .result
        recomputeSegments()
    }

    public func cancel() {
        Task { await client.send("cancel", encoding: [String]()) }
        live = false
        phase = .start
    }

    public func newScan() {
        if live { cancel() }
        phase = .start
        result = nil
        completedAt = nil
        focusPath = []
        segments = []
        basket = []
        banner = nil
        Task { await loadVolumes() }
    }

    /// Advice entries ready for the basket.
    public func entry(for advice: DiskAdvice) -> DiskEntry {
        DiskEntry(name: advice.name, path: advice.path, bytes: advice.bytes,
                  isDirectory: false, noAccess: false, children: [])
    }

    public func drill(into path: String) {
        guard let child = focus?.children.first(where: { $0.path == path }),
              child.isDirectory, !child.children.isEmpty else { return }
        navDirection = .down
        focusPath.append(child)
        recomputeSegments()
    }

    public func back() {
        guard focusPath.count > 1 else { return }
        navDirection = .up
        focusPath.removeLast()
        recomputeSegments()
    }

    public func jump(to index: Int) {
        guard focusPath.indices.contains(index), index < focusPath.count - 1 else { return }
        navDirection = .up
        focusPath = Array(focusPath.prefix(index + 1))
        recomputeSegments()
    }

    /// The name shown for an entry: the root carries the volume's name.
    public func displayName(for entry: DiskEntry) -> String {
        entry.path == focusPath.first?.path && !rootTitle.isEmpty ? rootTitle : entry.name
    }

    // MARK: - Basket

    public func toggleBasket(_ entry: DiskEntry) {
        if let index = basket.firstIndex(where: { $0.path == entry.path }) {
            basket.remove(at: index)
        } else if DiskSafety.isRemovable(entry.path) {
            basket.append(entry)
        }
    }

    public func isBasketed(_ entry: DiskEntry) -> Bool {
        basket.contains { $0.path == entry.path }
    }

    public func emptyBasket() async {
        let paths = basket.map(\.path)
        guard !paths.isEmpty else { return }
        let removal: DiskRemoval? = await client.request("trash", encoding: paths)
        banner = DkStr.removedFreed(ByteCountFormatter.string(
            fromByteCount: Int64(removal?.freedBytes ?? 0), countStyle: .file))
        basket = []
        // The tree is stale the moment anything is trashed; rescanning is
        // honest, and after a scan that took seconds it is cheap enough.
        if let root = focusPath.first?.path { await scan(path: root) }
    }

    // MARK: - Events

    private func observeEvents() async {
        for await event in vm.transport.events {
            switch event.name {
            case "progress":
                if let update = try? JSONDecoder().decode(ScanTick.self, from: event.payload) {
                    tick = update
                }
            case "partial":
                guard live,
                      let snapshot = try? JSONDecoder().decode(ScanResult.self, from: event.payload)
                else { continue }
                result = snapshot
                focusPath = DiskFocus.resolve(paths: focusPath.map(\.path), in: snapshot.root)
                phase = .result
                recomputeSegments()
            default:
                continue
            }
        }
    }

    // MARK: - Layout

    private func recomputeSegments() {
        guard let focus else { segments = []; return }
        let free = focusPath.count == 1 ? (result?.freeBytes ?? 0) : 0
        segments = RingLayout.layout(focus: Self.node(from: focus),
                                     depthLevels: 3, freeBytes: free)
    }

    /// RingLayout works on the engine's node type; the UI holds the
    /// transported snapshot, so the focused subtree is rebuilt for it.
    private static func node(from entry: DiskEntry) -> DiskNode {
        DiskNode(name: entry.name, path: entry.path, bytes: entry.bytes,
                 isDirectory: entry.isDirectory,
                 children: entry.children.map(node(from:)))
    }

}
