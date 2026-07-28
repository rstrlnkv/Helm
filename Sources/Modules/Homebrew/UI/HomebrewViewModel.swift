import Foundation
import HelmContract
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewViewModel: ObservableObject {
    private let transport: EngineTransport
    private let client: TransportClient
    private let vm: ModuleViewModel

    @Published public private(set) var status = BrewStatus(installed: false, brewPath: nil)
    @Published public private(set) var installed: [BrewPackage] = []
    /// True until the first list has come back, so the UI can tell "loading"
    /// apart from "genuinely nothing installed".
    @Published public private(set) var loadedInstalled = false
    @Published public private(set) var outdated: [OutdatedPackage] = []
    @Published public private(set) var searchHits: [SearchHit] = []
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
        ModuleUICache.dropWhenDisabled("homebrew") { cached = nil }
        return created
    }

    public init(vm: ModuleViewModel) {
        self.vm = vm
        self.transport = vm.transport
        self.client = TransportClient(vm.transport)
        let events = transport.events
        Task { [weak self] in
            for await e in events {
                guard let self else { break }   // page closed: stop consuming
                await self.handle(e)
            }
        }
    }

    /// What the page asks for on appear. The first visit does the work; later
    /// visits show what is already here.
    public func loadIfNeeded() async {
        guard !loadedStatus else { return }
        await refreshStatus()
        if status.installed { await refreshInstalled() }
    }

    public var running: Bool { op.phase == .running }

    // MARK: - Events

    private func handle(_ e: EngineEvent) {
        switch e.name {
        case "opLog":
            consoleLines.append(String(decoding: e.payload, as: UTF8.self))
        case "opState":
            guard let s = try? JSONDecoder().decode(OpState.self, from: e.payload) else { return }
            op = s
            if s.phase == .done { Task { await self.refreshAfterOp() } }
        default:
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
        status = await client.request("status") ?? status
        loadedStatus = true
    }
    public func refreshInstalled() async {
        installed = await client.request("listInstalled") ?? []
        loadedInstalled = true
        await loadDescriptions(formulae: installed.filter { !$0.isCask }.map(\.name),
                               casks: installed.filter(\.isCask).map(\.name))
    }
    public func refreshOutdated() async {
        outdated = await client.request("outdated") ?? []
        loadedOutdated = true
    }
    @Published public private(set) var loadedOutdated = false
    public func search(_ q: String) async {
        searchHits = await client.request("search", payload: Data(q.utf8)) ?? []
        await loadDescriptions(formulae: searchHits.filter { !$0.isCask }.map(\.name),
                               casks: searchHits.filter(\.isCask).map(\.name))
    }

    public func description(name: String, isCask: Bool) -> String? {
        descriptions[(isCask ? "c:" : "f:") + name]
    }

    private struct DescReq: Codable { let names: [String]; let isCask: Bool }

    private func loadDescriptions(formulae: [String], casks: [String]) async {
        // Only what we don't have yet; one brew call per kind.
        let newF = formulae.filter { descriptions["f:" + $0] == nil }
        let newC = casks.filter { descriptions["c:" + $0] == nil }
        if !newF.isEmpty,
           let d: [String: String] = await client.request("descriptions", encoding: DescReq(names: newF, isCask: false)) {
            for (k, v) in d { descriptions["f:" + k] = v }
        }
        if !newC.isEmpty,
           let d: [String: String] = await client.request("descriptions", encoding: DescReq(names: newC, isCask: true)) {
            for (k, v) in d { descriptions["c:" + k] = v }
        }
    }

    // MARK: - Operations (fire-and-forget; progress via events)

    private struct PkgReq: Codable { let name: String; let isCask: Bool }
    private struct NameReq: Codable { let name: String }

    public func install(_ hit: SearchHit) { client.fire("install", encoding: PkgReq(name: hit.name, isCask: hit.isCask)) }
    public func uninstall(_ pkg: BrewPackage) { client.fire("uninstall", encoding: PkgReq(name: pkg.name, isCask: pkg.isCask)) }
    public func upgrade(_ pkg: OutdatedPackage) { client.fire("upgrade", encoding: NameReq(name: pkg.name)) }
    public func upgradeAll() { client.fire("upgradeAll") }
    public func installBrew() { consoleLines.removeAll(); client.fire("installBrew") }

    public func clearConsole() { consoleLines.removeAll() }
}
