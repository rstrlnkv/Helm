import Foundation
import HelmRuntime
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
    @Published public private(set) var failures: [HelmTrash.Refusal] = []
    /// How many actually moved — see `DiskViewModel.removedCount`.
    @Published public private(set) var removedCount = 0
    /// A removal is running. The page dims what would start a second one — see
    /// `trash`, where the cost of the second is a wrong report about the first.
    @Published public private(set) var busy = false

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
        matchingStatus.filter { !hiddenKinds.contains($0.kind) }
    }

    /// What the page draws instead of the list, or nil when there is a list.
    ///
    /// Asked of `visibleItems`, which is what the `List` is built from — the page
    /// asked `items.isEmpty`, and on any ordinary Mac those differ: the scan finds
    /// hundreds of settings files in use and no leftovers at all.
    /// `LeftoversEmpty.reason` holds the rule and says why there are three answers.
    public var nothingToShow: LeftoversEmpty.Reason? {
        LeftoversEmpty.reason(scanned: scanned, visible: visibleItems.count,
                              hiddenByKind: hiddenByKindCount)
    }

    /// How many rows the kind filter is holding back — answered without walking
    /// the scan at all until somebody has hidden a kind, which is every session by
    /// default. The page asks this on each pass over `body`, over a list that is
    /// hundreds of items long on an ordinary Mac.
    private var hiddenByKindCount: Int {
        guard !hiddenKinds.isEmpty else { return 0 }
        return matchingStatus.count { hiddenKinds.contains($0.kind) }
    }

    /// The rows the status filter keeps, before the kind filter runs — the half of
    /// `visibleItems` that says whether the filter menu is what emptied the list.
    ///
    /// "Leftovers" is a status, not a permission to delete: an extension whose app
    /// is gone belongs here even though clearing it happens in System Settings.
    private var matchingStatus: [StaleItem] {
        showAll ? items : items.filter { $0.status == .orphaned }
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

    /// Which request the list belongs to.
    ///
    /// **The Scan button is not the only caller.** `setDisabled` rescans so the row
    /// shows what launchd actually did, and `trash` rescans after a removal — so
    /// two quick toggles are two scans over the same `items`, and without this the
    /// list went to whichever the machine answered *last* rather than to the last
    /// thing the person asked for. `LatestRequest` carries why it is a counter and
    /// not a latch.
    private var scans = LatestRequest()

    public func scan() async {
        let mine = scans.take()
        scanning = true
        // Only the newest request may say the page is idle: an older scan
        // finishing would otherwise re-enable the button over a scan still
        // running.
        defer { if scans.isLatest(mine) { scanning = false } }
        let found: [StaleItem] = await client.request(LeftoversCommand.scan) ?? []
        guard scans.isLatest(mine) else { return }
        items = found
        // Nothing is ticked by default: these files are load-bearing, so the
        // user chooses each one. But a rescan is not a fresh start — switching
        // one row off rescans, and clearing the set threw away every other tick
        // the user had made, with no warning and no way back.
        if scanned { dropHiddenSelections() } else { selected = [] }
        scanned = true
    }

    /// Switches a login item off through launchd, then rescans so the row
    /// shows what actually happened rather than what we hoped.
    ///
    /// **Not while a removal is running.** This was one of three controls that
    /// stayed live for the length of a `trash` request, and the least harmless of
    /// them: it rescans, so the fresh `items` land on top of the list the removal
    /// is about to report on. The page dims the button as well — both, or neither
    /// is reliable (ARCHITECTURE.md § One removal at a time).
    public func setDisabled(_ disabled: Bool, item: StaleItem) async {
        guard !busy else { return }
        await client.send(LeftoversCommand.setDisabled,
                          encoding: LeftoversToggle(label: item.identifier, disabled: disabled))
        await scan()
    }

    /// Deletes one item, in use or not — the row asks first when it matters.
    public func remove(_ item: StaleItem) async {
        await trash([item.path])
    }

    public func removeSelected() async {
        // `visibleItems`, not `items`. A tick made while the list showed
        // everything survived a switch back to the filtered view: the row
        // disappeared, `selected` kept its path, the count and the size on
        // screen were computed over what was visible — and this then trashed it
        // anyway. Deleting something the person cannot see, and did not see
        // counted, is the one thing this module must not do.
        await trash(selectedItems.map(\.path))
    }

    /// The one way anything leaves: ask the engine, then report what it says and
    /// rescan so the list shows what happened rather than what was hoped.
    ///
    /// Both callers had these four lines written out, which is four chances for
    /// the row's outcome and the bar's outcome to come to mean different things
    /// — and the banner is the only place a refusal is ever named.
    private func trash(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        // **One removal at a time.** The buttons dim only on an empty selection,
        // and the selection is not emptied until the rescan that follows this
        // has come back — so between the press and that moment the button is
        // live and the paths are still ticked. A second press does not delete
        // anything twice; the files are already in the Trash. It comes back
        // with a refusal *per file*, because a path that is no longer there is
        // a refusal with a reason, and the three lines below then overwrite the
        // report of the removal that worked. The person is told nothing moved
        // and shown a list of everything that did — in the one place this
        // module ever names a refusal.
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let result: LeftoversRemoval? = await client.request(LeftoversCommand.trash,
                                                            encoding: paths)
        failures = result?.refused ?? []
        removedCount = result?.removed.count ?? 0
        banner = LfStr.movedToTrash(Bytes(result?.freedBytes ?? 0))
        await scan()
    }
}
