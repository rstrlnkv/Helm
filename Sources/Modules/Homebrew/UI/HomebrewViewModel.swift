import Foundation
import HelmContract
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewViewModel: ObservableObject {
    private let client: TransportClient
    private var eventsTask: Task<Void, Never>?
    private let vm: ModuleViewModel

    @Published public private(set) var status = BrewStatus(installed: false, brewPath: nil)
    @Published public private(set) var installed: [BrewPackage] = []
    /// True until the first list has come back, so the UI can tell "loading"
    /// apart from "genuinely nothing installed".
    @Published public private(set) var loadedInstalled = false
    @Published public private(set) var outdated: [OutdatedPackage] = []
    @Published public private(set) var searchHits: [SearchHit] = []
    /// The last of what `brew` said, not all of it. 1000 is `LogTail`'s bound
    /// and this is the same problem: a running record somebody reads the end of.
    public static let consoleLimit = 1000
    @Published public private(set) var consoleLines: [String] = []
    @Published public private(set) var op: OpState = .idle
    /// Package descriptions keyed by "f:name" / "c:name", fetched in batches
    /// after a list or search loads.
    @Published public private(set) var descriptions: [String: String] = [:]

    /// One instance per host view model, for the app's lifetime.
    ///
    /// Leaving the page in Settings tears down the subtree and its
    /// `@StateObject`; coming back builds a new one and re-runs `.task`. On a
    /// fresh instance `descriptions` is empty, so returning to Homebrew re-ran
    /// `brew list --versions` twice and a `brew desc` batch over every package
    /// installed — every visit, for a list that had not changed.
    ///
    /// Keyed to the view model it was built against, not merely "exists", for
    /// the reason `DiskViewModel.shared` gives: turning the module off drops
    /// the engine, and a cache held past that is talking to a corpse.
    private static var cached: HomebrewViewModel?
    public static func shared(vm: ModuleViewModel) -> HomebrewViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = HomebrewViewModel(vm: vm)
        cached = created
        // The descriptor's id, not the word typed again: a module id written by
        // hand is tied to the thing it names or it is a comment.
        ModuleUICache.dropWhenDisabled(HomebrewDescriptor.id.rawValue) { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        self.client = TransportClient(vm.transport)
        // Held only to start the loop below — it was a stored property nothing
        // read after `init`.
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await e in events {
                guard let self else { break }   // page closed: stop consuming
                self.handle(e)
            }
        }
    }

    /// Ends the event loop, which unregisters the transport subscriber. The
    /// `guard` above already released the view model; without this the task
    /// itself waited for an event that may never come.
    deinit { eventsTask?.cancel() }

    /// What the page asks for on appear. The first visit does the work; later
    /// visits show what is already here.
    public func loadIfNeeded() async {
        guard !loadedStatus else { return }
        await refreshStatus()
        if status.installed { await refreshInstalled() }
    }

    public var running: Bool { op.phase == .running }

    // MARK: - Events

    /// The enum, not the two literals the engine also types out — see
    /// `HomebrewEvent`. A name that stops matching here empties the console and
    /// says nothing about why.
    private func handle(_ e: EngineEvent) {
        switch HomebrewEvent(rawValue: e.name) {
        case .opLog:
            consoleLines.append(String(decoding: e.payload, as: UTF8.self))
            // Bounded, the way `LogTail` is. Nothing trimmed this: it is
            // cleared by pressing Clear and by starting an install, so on the
            // ordinary path — upgrade, upgrade again, search — it only grew,
            // for the life of the app, since this view model is cached per host
            // view model. The engine keeps stderr on purpose because a console
            // should show what the tool says, and a `brew` command passes 64 KB
            // of deprecation warnings without trying. Each line is also a view:
            // the page renders a `ForEach` over the whole array and scrolls on
            // every count change, so the cost is paid twice.
            //
            // From the front, which is what a terminal's scrollback does: the
            // end is the half a person is reading.
            if consoleLines.count > Self.consoleLimit {
                consoleLines.removeFirst(consoleLines.count - Self.consoleLimit)
            }
        case .opState:
            guard let s = try? JSONDecoder().decode(OpState.self, from: e.payload) else { return }
            op = s
            if s.phase == .done { Task { await self.refreshAfterOp() } }
        case .none:
            break
        }
    }

    /// The status too, and it is not a nicety: installing Homebrew is one of
    /// the operations that ends here, and `status.installed` is the only thing
    /// `HomebrewSettingsPage.body` branches on. Refreshing the package lists
    /// but not the status left somebody who had just installed Homebrew looking
    /// at the install screen, with the only way forward being to close Settings
    /// and open it again. Now that the view model outlives the page, closing
    /// Settings no longer papers over it either.
    private func refreshAfterOp() async {
        await refreshStatus()
        await refreshInstalled()
        await refreshOutdated()
    }

    // MARK: - Queries

    /// False until the first answer, so `loadIfNeeded` can tell "not asked yet"
    /// from "asked, and brew is not installed".
    @Published public private(set) var loadedStatus = false
    public func refreshStatus() async {
        status = await client.request(HomebrewCommand.status) ?? status
        loadedStatus = true
    }
    public func refreshInstalled() async {
        installed = await client.request(HomebrewCommand.listInstalled) ?? []
        loadedInstalled = true
        await loadDescriptions(formulae: installed.filter { !$0.isCask }.map(\.name),
                               casks: installed.filter(\.isCask).map(\.name))
    }
    public func refreshOutdated() async {
        outdated = await client.request(HomebrewCommand.outdated) ?? []
        loadedOutdated = true
    }
    @Published public private(set) var loadedOutdated = false
    public func search(_ q: String) async {
        searchHits = await client.request(HomebrewCommand.search, payload: Data(q.utf8)) ?? []
        await loadDescriptions(formulae: searchHits.filter { !$0.isCask }.map(\.name),
                               casks: searchHits.filter(\.isCask).map(\.name))
    }

    public func description(name: String, isCask: Bool) -> String? {
        descriptions[BrewKey.of(name: name, isCask: isCask)]
    }

    /// Only what is not held yet, one `brew desc` call per kind.
    ///
    /// Every key here goes through `BrewKey`. The prefix used to be written out
    /// at each of these five places and at the three row identities, and the two
    /// halves have to agree exactly: a description stored under a key no row
    /// asks for is a row with no description and nothing in any log.
    private func loadDescriptions(formulae: [String], casks: [String]) async {
        await load(formulae, isCask: false)
        await load(casks, isCask: true)
    }

    private func load(_ names: [String], isCask: Bool) async {
        let wanted = names.filter { descriptions[BrewKey.of(name: $0, isCask: isCask)] == nil }
        guard !wanted.isEmpty,
              let found: [String: String] = await client.request(
                  HomebrewCommand.descriptions,
                  encoding: DescriptionsRequest(names: wanted, isCask: isCask))
        else { return }
        for (name, text) in found { descriptions[BrewKey.of(name: name, isCask: isCask)] = text }
    }

    // MARK: - Operations (fire-and-forget; progress via events)

    public func install(_ hit: SearchHit) {
        client.fire(HomebrewCommand.install,
                    encoding: PackageRef(name: hit.name, isCask: hit.isCask))
    }
    public func uninstall(_ pkg: BrewPackage) {
        client.fire(HomebrewCommand.uninstall,
                    encoding: PackageRef(name: pkg.name, isCask: pkg.isCask))
    }
    public func upgrade(_ pkg: OutdatedPackage) {
        client.fire(HomebrewCommand.upgrade, payload: Data(pkg.name.utf8))
    }
    public func upgradeAll() { client.fire(HomebrewCommand.upgradeAll) }
    public func installBrew() { consoleLines.removeAll(); client.fire(HomebrewCommand.installBrew) }

    public func clearConsole() { consoleLines.removeAll() }
}
