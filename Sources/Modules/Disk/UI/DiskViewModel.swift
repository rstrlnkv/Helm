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
    @Published public var basket: [DiskEntry] = []
    @Published public private(set) var banner: String?

    private let client: TransportClient
    private let vm: ModuleViewModel

    public init(vm: ModuleViewModel) {
        self.vm = vm
        client = TransportClient(vm.transport)
    }

    public var focus: DiskEntry? { focusPath.last }
    public var basketBytes: Int { basket.reduce(0) { $0 + $1.bytes } }

    public func loadVolumes() async {
        volumes = await client.request("volumes") ?? []
    }

    public func scan(path: String) async {
        phase = .scanning
        tick = nil
        let scan: ScanResult? = await client.request("scan", encoding: ["path": path])
        guard let scan else {                    // cancelled
            phase = .start
            return
        }
        result = scan
        focusPath = [scan.root]
        phase = .result
    }

    public func cancel() {
        Task { await client.send("cancel", encoding: [String]()) }
        phase = .start
    }

    public func drill(into path: String) {
        guard let child = focus?.children.first(where: { $0.path == path }),
              child.isDirectory, !child.children.isEmpty else { return }
        focusPath.append(child)
    }

    public func back() {
        guard focusPath.count > 1 else { return }
        focusPath.removeLast()
    }

    public func jump(to index: Int) {
        guard focusPath.indices.contains(index) else { return }
        focusPath = Array(focusPath.prefix(index + 1))
    }

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

    public func observeProgress() async {
        for await event in vm.transport.events where event.name == "progress" {
            guard let update = try? JSONDecoder().decode(ScanTick.self, from: event.payload)
            else { continue }
            tick = update
        }
    }
}
