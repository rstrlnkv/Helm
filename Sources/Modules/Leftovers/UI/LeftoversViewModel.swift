import Foundation
import HelmUI
import Module_Leftovers_Engine

@MainActor public final class LeftoversViewModel: ObservableObject {
    @Published public private(set) var items: [StaleItem] = []
    @Published public private(set) var scanning = false
    @Published public private(set) var scanned = false
    @Published public var selected: Set<String> = []
    @Published public private(set) var banner: String?
    @Published public private(set) var failures: [TrashFailureDetail] = []

    private let client: TransportClient

    public init(vm: ModuleViewModel) { client = TransportClient(vm.transport) }

    public func scan() async {
        scanning = true
        defer { scanning = false }
        items = await client.request("scan") ?? []
        // Nothing is ticked by default: these files are load-bearing, so the
        // user chooses each one.
        selected = []
        scanned = true
    }

    public func removeSelected() async {
        let paths = items.map(\.path).filter { selected.contains($0) }
        guard !paths.isEmpty else { return }
        let result: LeftoversRemoval? = await client.request("trash", encoding: paths)
        failures = result?.failed ?? []
        banner = LfStr.removedFreed(ByteCountFormatter.string(
            fromByteCount: Int64(result?.freedBytes ?? 0), countStyle: .file))
        await scan()
    }
}
