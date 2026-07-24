import Foundation
import HelmContract

/// Manages Homebrew via the `brew` CLI. Fast queries answer over `transport.send`
/// (JSON); long operations (install/uninstall/upgrade/installBrew) stream
/// `opLog`/`opState` events. One long operation at a time.
public final class HomebrewEngine: ModuleEngine, @unchecked Sendable {
    private let locator: BrewLocator
    private let runner: ProcessRunner
    private let privileged: PrivilegedRunner
    private let user: String
    private let localTransport: LocalTransport
    public let transport: EngineTransport

    private let lock = NSLock()
    private var busy = false

    private static let installerURL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

    public init(locator: BrewLocator, runner: ProcessRunner, privileged: PrivilegedRunner,
                user: String, transport: LocalTransport = LocalTransport()) {
        self.locator = locator
        self.runner = runner
        self.privileged = privileged
        self.user = user
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    // MARK: - Queries

    public func status() -> BrewStatus {
        let path = locator.brewPath()
        return BrewStatus(installed: path != nil, brewPath: path)
    }

    public func listInstalled() -> [BrewPackage] {
        guard let brew = locator.brewPath() else { return [] }
        let f = runner.run(brew, ["list", "--versions", "--formula"], env: [:]).stdout
        let c = runner.run(brew, ["list", "--versions", "--cask"], env: [:]).stdout
        return BrewListParser.parse(f, isCask: false) + BrewListParser.parse(c, isCask: true)
    }

    public func outdated() -> [OutdatedPackage] {
        guard let brew = locator.brewPath() else { return [] }
        let out = runner.run(brew, ["outdated", "--json=v2"], env: [:]).stdout
        return BrewOutdatedParser.parse(Data(out.utf8))
    }

    public func search(_ query: String) -> [SearchHit] {
        guard let brew = locator.brewPath(), !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let out = runner.run(brew, ["search", query], env: [:]).stdout
        return BrewSearchParser.parse(out)
    }

    // MARK: - Long operations

    private func beginBusy() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }
    private func endBusy() { lock.lock(); busy = false; lock.unlock() }

    private func emitLog(_ line: String) {
        localTransport.emit(EngineEvent(name: "opLog", payload: Data(line.utf8)))
    }
    private func emitState(_ s: OpState) {
        localTransport.emit(EngineEvent(name: "opState", payload: (try? JSONEncoder().encode(s)) ?? Data()))
    }

    private func runOp(label: String, launch: String, args: [String], env: [String: String] = [:]) {
        guard beginBusy() else { emitLog("⚠︎ Another operation is already running."); return }
        emitState(OpState(phase: .running, label: label))
        runner.stream(launch, args, env: env,
                      onLine: { [weak self] line in self?.emitLog(line) },
                      onExit: { [weak self] code in
                          guard let self else { return }
                          self.endBusy()
                          self.emitState(OpState(phase: code == 0 ? .done : .failed,
                                                 label: label, exitCode: Int(code)))
                      })
    }

    public func install(name: String, isCask: Bool) {
        guard let brew = locator.brewPath() else { return }
        runOp(label: "install \(name)", launch: brew, args: isCask ? ["install", "--cask", name] : ["install", name])
    }
    public func uninstall(name: String, isCask: Bool) {
        guard let brew = locator.brewPath() else { return }
        runOp(label: "uninstall \(name)", launch: brew, args: isCask ? ["uninstall", "--cask", name] : ["uninstall", name])
    }
    public func upgrade(name: String) {
        guard let brew = locator.brewPath() else { return }
        runOp(label: "upgrade \(name)", launch: brew, args: ["upgrade", name])
    }
    public func upgradeAll() {
        guard let brew = locator.brewPath() else { return }
        runOp(label: "upgrade all", launch: brew, args: ["upgrade"])
    }

    /// Install Homebrew itself: pre-create /opt/homebrew owned by the user via one
    /// native admin prompt, then run the official installer non-interactively.
    public func installBrew() {
        guard beginBusy() else { emitLog("⚠︎ Another operation is already running."); return }
        emitState(OpState(phase: .running, label: "install Homebrew"))
        let prep = "mkdir -p /opt/homebrew && chown -R \(user):admin /opt/homebrew"
        guard privileged.runAdmin(prep) else {
            endBusy()
            emitState(OpState(phase: .failed, label: "install Homebrew", exitCode: 1))
            emitLog("Administrator authorization was cancelled.")
            return
        }
        // One shell level: fetch the official installer and run it in this bash.
        let installer = "eval \"$(/usr/bin/curl -fsSL \(Self.installerURL))\""
        runner.stream("/bin/bash", ["-c", installer], env: ["NONINTERACTIVE": "1"],
                      onLine: { [weak self] line in self?.emitLog(line) },
                      onExit: { [weak self] code in
                          guard let self else { return }
                          self.endBusy()
                          self.emitState(OpState(phase: code == 0 ? .done : .failed,
                                                 label: "install Homebrew", exitCode: Int(code)))
                      })
    }

    // MARK: - Transport

    private struct PkgReq: Codable { let name: String; let isCask: Bool }
    private struct NameReq: Codable { let name: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            func json<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }
            switch cmd.name {
            case "status":        return json(self.status())
            case "listInstalled": return json(self.listInstalled())
            case "outdated":      return json(self.outdated())
            case "search":        return json(self.search(String(decoding: cmd.payload, as: UTF8.self)))
            case "install":
                if let r = try? JSONDecoder().decode(PkgReq.self, from: cmd.payload) { self.install(name: r.name, isCask: r.isCask) }
            case "uninstall":
                if let r = try? JSONDecoder().decode(PkgReq.self, from: cmd.payload) { self.uninstall(name: r.name, isCask: r.isCask) }
            case "upgrade":
                if let r = try? JSONDecoder().decode(NameReq.self, from: cmd.payload) { self.upgrade(name: r.name) }
            case "upgradeAll": self.upgradeAll()
            case "installBrew": self.installBrew()
            default: break
            }
            return Data()
        }
    }
}
