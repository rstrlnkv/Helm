import Foundation
import HelmContract
import HelmUI
import Module_Homebrew_Engine

@MainActor public final class HomebrewViewModel: ObservableObject {
    private let transport: EngineTransport

    @Published public private(set) var status = BrewStatus(installed: false, brewPath: nil)
    @Published public private(set) var installed: [BrewPackage] = []
    @Published public private(set) var outdated: [OutdatedPackage] = []
    @Published public private(set) var searchHits: [SearchHit] = []
    @Published public private(set) var consoleLines: [String] = []
    @Published public private(set) var op: OpState = .idle

    public init(vm: ModuleViewModel) {
        self.transport = vm.transport
        let events = transport.events
        Task { [weak self] in
            for await e in events {
                guard let self else { break }   // page closed: stop consuming
                await self.handle(e)
            }
        }
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

    private func refreshAfterOp() async {
        await refreshInstalled()
        await refreshOutdated()
    }

    // MARK: - Queries

    public func refreshStatus() async { status = await send("status", Data(), as: BrewStatus.self) ?? status }
    public func refreshInstalled() async { installed = await send("listInstalled", Data(), as: [BrewPackage].self) ?? [] }
    public func refreshOutdated() async { outdated = await send("outdated", Data(), as: [OutdatedPackage].self) ?? [] }
    public func search(_ q: String) async {
        searchHits = await send("search", Data(q.utf8), as: [SearchHit].self) ?? []
    }

    // MARK: - Operations (fire-and-forget; progress via events)

    private struct PkgReq: Codable { let name: String; let isCask: Bool }
    private struct NameReq: Codable { let name: String }

    public func install(_ hit: SearchHit) { fire("install", PkgReq(name: hit.name, isCask: hit.isCask)) }
    public func uninstall(_ pkg: BrewPackage) { fire("uninstall", PkgReq(name: pkg.name, isCask: pkg.isCask)) }
    public func upgrade(_ pkg: OutdatedPackage) { fire("upgrade", NameReq(name: pkg.name)) }
    public func upgradeAll() { fireEmpty("upgradeAll") }
    public func installBrew() { consoleLines.removeAll(); fireEmpty("installBrew") }

    public func clearConsole() { consoleLines.removeAll() }

    // MARK: - Plumbing

    private func send<T: Decodable>(_ name: String, _ payload: Data, as: T.Type) async -> T? {
        guard let data = try? await transport.send(EngineCommand(name: name, payload: payload)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func fire<T: Encodable>(_ name: String, _ payload: T) {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: data)) }
    }
    private func fireEmpty(_ name: String) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: Data())) }
    }
}
