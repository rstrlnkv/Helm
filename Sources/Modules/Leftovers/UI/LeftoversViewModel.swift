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
    /// The last removal's reply never came back.
    ///
    /// The fourth thing the report is read as: not a claim that anything moved,
    /// not a refusal, and not silence. Clearing the other three was the right
    /// half of the fix and only half of it — `HelmRemovalOutcome.verdict(removed:
    /// 0, failed: 0)` is `.silent`, so the page said nothing at all about a
    /// destructive press somebody had made, while the rescan underneath quietly
    /// changed the list.
    @Published public private(set) var replyLost = false
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
    ///
    /// **No `busy` guard here, and that is the point of the comment.** `trash`
    /// holds `busy` across the rescan it makes afterwards, and that rescan is what
    /// drops the ticks on rows the removal took — a guard here would be inert
    /// where it looked most careful, and would leave a batch's own rows ticked
    /// under the report saying they are gone.
    public func dropHiddenSelections() {
        selected.formIntersection(selectablePaths)
    }

    /// The three gestures that change the selection: the bar's two buttons and a
    /// row's checkbox.
    ///
    /// **On the model, because the dimming cannot be the whole guard.** The page
    /// wrote `selected` directly, so «the model refuses this while a removal runs;
    /// the page has to say so» — this page's own comment about the switch — had
    /// only its second half here: `.disabled(lvm.busy)` was one redraw away from
    /// being everything that stood between a press and the selection changing
    /// under a report about to arrive.
    public func tickAll() {
        guard !busy else { return }
        selected = selectablePaths
    }

    public func untickAll() {
        guard !busy else { return }
        selected.removeAll()
    }

    public func setTicked(_ ticked: Bool, path: String) {
        guard !busy else { return }
        if ticked { selected.insert(path) } else { selected.remove(path) }
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

    /// The Scan button, and the sixth control on this page that can start work in
    /// the middle of a removal.
    ///
    /// It was gated on `scanning` alone, which is nothing at all while a removal
    /// runs — and what a scan costs there is what `setDisabled` costs, in that
    /// method's own words: the fresh `items` land on top of the list the removal is
    /// about to report on.
    ///
    /// **The guard is on the press, not on the reading.** `trash` holds `busy`
    /// across the rescan it makes for itself, so `guard !busy` inside `reload`
    /// would refuse that one too and leave the list showing rows that are already
    /// in the Trash — the inert half of a fix that looks most careful where it does
    /// the most harm, which is the trap `dropHiddenSelections` records.
    public func scan() async {
        guard !busy else { return }
        await reload()
    }

    /// Bring the list up to date. Every caller that has already decided it may act.
    private func reload() async {
        let mine = scans.take()
        scanning = true
        // Only the newest request may say the page is idle: an older scan
        // finishing would otherwise re-enable the button over a scan still
        // running.
        defer { if scans.isLatest(mine) { scanning = false } }
        let found: [StaleItem]? = await client.request(LeftoversCommand.scan)
        guard scans.isLatest(mine) else { return }
        // **An unanswered request is not an answer.** `TransportClient.request`
        // answers nil for a request that threw and for a reply that would not
        // decode — and this module reaches the second in the tree:
        // `LeftoversEngine.wireTransport` returns empty `Data` when the engine has
        // gone under a page that is still up, which is also what `shared(vm:)`
        // says a cached model outliving its engine gets from then on. Folded to
        // `[]` that became «No leftovers found» — this page's one claim about the
        // state of somebody's Mac — and on a rescan it threw away the list they
        // were working through with every tick on it. `DiskViewModel.scan` keeps
        // its screen where it was for the same nil.
        guard let found else { return }
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
                          encoding: LeftoversToggle(label: item.identifier, path: item.path,
                                                    disabled: disabled))
        await reload()
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
        // **A batch nobody answered is not a batch that moved nothing.** Folded
        // with `??`, «Moved to the Trash — 0 B» stood over an empty refusal list,
        // and `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent` —
        // so the one thing the person was told about a removal that never
        // happened is that it did, in a row that draws nothing.
        //
        // Nor is it a batch that failed: the engine may have moved the files and
        // the reply been lost. So the report claims nothing about what moved, and
        // says instead that it does not know — the rescan below is what puts the
        // list right, and the sentence points at it. Clearing the three fields
        // and stopping there left the page silent about a destructive press.
        guard let result else {
            clearRemovalReport()
            replyLost = true
            // Counts and outcomes are free; nothing here names a file. It was the
            // one branch in this module that reached the screen without reaching
            // the log, which is the branch a person would be attaching a log to
            // ask about.
            HelmLog.shared.info(LeftoversEngine.moduleID, "trash reply lost")
            await reload()
            return
        }
        // The four fields are one report, so a round that *was* answered has to
        // put the previous round's «no answer» down as well — otherwise the
        // sentence outlives the press it was about.
        replyLost = false
        failures = result.refused
        removedCount = result.removed.count
        banner = LfStr.movedToTrash(result.removed.count, Bytes(result.freedBytes))
        await reload()
    }

    /// Nothing on screen about a removal — the shape `DiskViewModel` already
    /// keeps, and the four fields are read as one report.
    private func clearRemovalReport() {
        banner = nil
        failures = []
        removedCount = 0
        replyLost = false
    }
}
