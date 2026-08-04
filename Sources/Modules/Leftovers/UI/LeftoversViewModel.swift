import Foundation
import HelmUI
import Module_Leftovers_Engine

@MainActor public final class LeftoversViewModel: ObservableObject {
    @Published public private(set) var items: [StaleItem] = []
    @Published public private(set) var scanning = false
    @Published public private(set) var scanned = false
    @Published public var selected: Set<String> = []
    /// Leftovers only by default: the full list is context, not a to-do list.
    @Published public var showAll = false
    @Published public private(set) var banner: String?
    @Published public private(set) var failures: [TrashFailureDetail] = []
    /// How many actually moved — see `DiskViewModel.removedCount`.
    @Published public private(set) var removedCount = 0

    private let client: TransportClient
    let vm: ModuleViewModel

    /// The scan and every checkbox must outlive the page. Settings rebuilds the
    /// page on every sidebar visit, and nothing here is pre-ticked: each tick is
    /// a decision about a file macOS loads, which is not something to make the
    /// person take twice.
    private static var cached: LeftoversViewModel?
    public static func shared(vm: ModuleViewModel) -> LeftoversViewModel {
        // Keyed to the view model it was built against — see
        // `DiskViewModel.shared(vm:)`: switching the module off deallocates the
        // engine, while the transport held here survives and answers every
        // request with empty Data from then on.
        if let cached, cached.vm === vm { return cached }
        let created = LeftoversViewModel(vm: vm)
        cached = created
        ModuleUICache.dropWhenDisabled(LeftoversDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        client = TransportClient(vm.transport)
    }

    /// Kinds the user has hidden. System extensions are the common case:
    /// they are informational, and someone reviewing login items does not
    /// want them in the way.
    @Published public var hiddenKinds: Set<StaleKind> = []

    public var visibleItems: [StaleItem] {
        // "Leftovers" is a status, not a permission to delete: an extension
        // whose app is gone belongs here even though clearing it happens in
        // System Settings.
        (showAll ? items : items.filter { $0.status == .orphaned })
            .filter { !hiddenKinds.contains($0.kind) }
    }

    /// Counted over what the list actually shows. Counting the whole scan
    /// while the list is filtered made "Выбрать все" tick rows nobody could
    /// see — and then delete them.
    public var leftoverCount: Int { visibleItems.filter(\.removable).count }

    /// What the bar at the bottom is about, both halves of it. It used to pair
    /// the number of removable rows found with the size of the selection, so
    /// "1 item · 0 B" stood under a visible row saying 4 KB. A count and a size
    /// joined by a middle dot read as one measurement, and were two.
    public var selectedCount: Int { selectedItems.count }
    public var selectedBytes: Int { selectedItems.reduce(0) { $0 + $1.sizeBytes } }

    /// Counted over what the list actually shows — the rule `removeSelected`
    /// follows when it decides what may go.
    private var selectedItems: [StaleItem] {
        visibleItems.filter { selected.contains($0.path) }
    }

    /// Everything the user could tick right now.
    public var selectablePaths: Set<String> {
        Set(visibleItems.filter(\.removable).map(\.path))
    }

    /// A hidden row must not stay ticked from before it was hidden.
    public func dropHiddenSelections() {
        selected.formIntersection(selectablePaths)
    }

    public func scan() async {
        scanning = true
        defer { scanning = false }
        items = await client.request(LeftoversCommand.scan) ?? []
        // Nothing is ticked by default: these files are load-bearing, so the
        // user chooses each one. But a rescan is not a fresh start — switching
        // one row off rescans, and clearing the set threw away every other tick
        // the user had made, with no warning and no way back.
        if scanned { dropHiddenSelections() } else { selected = [] }
        scanned = true
    }

    /// Switches a login item off through launchd, then rescans so the row
    /// shows what actually happened rather than what we hoped.
    public func setDisabled(_ disabled: Bool, item: StaleItem) async {
        await client.send(LeftoversCommand.setDisabled,
                          encoding: LeftoversToggle(label: item.identifier, disabled: disabled))
        await scan()
    }

    /// Deletes one item, in use or not — the row asks first when it matters.
    public func remove(_ item: StaleItem) async {
        let result: LeftoversRemoval? = await client.request(LeftoversCommand.trash, encoding: [item.path])
        failures = result?.failed ?? []
        removedCount = result?.removed.count ?? 0
        banner = LfStr.movedToTrash(Bytes(result?.freedBytes ?? 0))
        await scan()
    }

    public func removeSelected() async {
        // `visibleItems`, not `items`. A tick made while the list showed
        // everything survived a switch back to the filtered view: the row
        // disappeared, `selected` kept its path, the count and the size on
        // screen were computed over what was visible — and this then trashed it
        // anyway. Deleting something the person cannot see, and did not see
        // counted, is the one thing this module must not do.
        let paths = selectedItems.map(\.path)
        guard !paths.isEmpty else { return }
        let result: LeftoversRemoval? = await client.request(LeftoversCommand.trash, encoding: paths)
        failures = result?.failed ?? []
        removedCount = result?.removed.count ?? 0
        banner = LfStr.movedToTrash(Bytes(result?.freedBytes ?? 0))
        await scan()
    }
}
