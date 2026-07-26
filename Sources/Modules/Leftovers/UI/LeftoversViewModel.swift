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

    private let client: TransportClient

    public init(vm: ModuleViewModel) { client = TransportClient(vm.transport) }

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
        items = await client.request("scan") ?? []
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
        await client.send("setDisabled",
                          encoding: LeftoversToggle(label: item.identifier, disabled: disabled))
        await scan()
    }

    /// Deletes one item, in use or not — the row asks first when it matters.
    public func remove(_ item: StaleItem) async {
        let result: LeftoversRemoval? = await client.request("trash", encoding: [item.path])
        failures = result?.failed ?? []
        banner = LfStr.removedFreed(Bytes(result?.freedBytes ?? 0))
        await scan()
    }

    public func removeSelected() async {
        let paths = items.map(\.path).filter { selected.contains($0) }
        guard !paths.isEmpty else { return }
        let result: LeftoversRemoval? = await client.request("trash", encoding: paths)
        failures = result?.failed ?? []
        banner = LfStr.removedFreed(Bytes(result?.freedBytes ?? 0))
        await scan()
    }
}
