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

    /// Runs blocking work (Process + waitUntilExit, file IO) on a dispatch
    /// queue so it never parks a Swift-concurrency pool thread for seconds.
    private func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: work()) }
        }
    }

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

    /// One `brew desc` call per kind covers a whole list of names.
    public func descriptions(names: [String], isCask: Bool) -> [String: String] {
        guard let brew = locator.brewPath(), !names.isEmpty else { return [:] }
        let out = runner.run(brew, ["desc", isCask ? "--cask" : "--formula"] + names, env: [:]).stdout
        return BrewDescParser.parse(out)
    }

    public func search(_ query: String) -> [SearchHit] {
        guard let brew = locator.brewPath(), !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        // One call per kind: brew no longer labels a flat result list, and the
        // kind decides whether the install is `brew install` or `brew install
        // --cask`. Ids are already namespaced f:/c:, so a name that exists as
        // both stays two distinguishable rows.
        let formulae = runner.run(brew, ["search", "--formula", query], env: [:]).stdout
        let casks = runner.run(brew, ["search", "--cask", query], env: [:]).stdout
        return BrewSearchParser.parse(formulae, kind: false)
             + BrewSearchParser.parse(casks, kind: true)
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

    /// Account names sudo-adjacent shells will take, and nothing else.
    static func isPlausibleAccountName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-")
        }
    }

    /// Install Homebrew itself: pre-create /opt/homebrew owned by the user via one
    /// native admin prompt, then run the official installer non-interactively.
    public func installBrew() {
        guard beginBusy() else { emitLog("⚠︎ Another operation is already running."); return }
        emitState(OpState(phase: .running, label: "install Homebrew"))
        // `user` is NSUserName(), which on a managed Mac is whatever the
        // directory says; this string is evaluated by a root shell. Single
        // quotes stop expansion, and the name is checked before it gets there.
        guard Self.isPlausibleAccountName(user) else {
            endBusy()
            emitState(OpState(phase: .failed, label: "install Homebrew", exitCode: 1))
            emitLog("Unsupported account name.")
            return
        }
        let prep = "mkdir -p /opt/homebrew && chown -R '\(user)':admin /opt/homebrew"
        guard privileged.runAdmin(prep) else {
            endBusy()
            emitState(OpState(phase: .failed, label: "install Homebrew", exitCode: 1))
            emitLog("Administrator authorization was cancelled.")
            return
        }
        // Download, then run — not `eval "$(curl …)"`, where a failed download
        // evaluates the empty string, exits 0, and the module reports a
        // successful install of nothing.
        let installer = "set -e; script=$(/usr/bin/mktemp); "
                      + "/usr/bin/curl -fsSL \(Self.installerURL) -o \"$script\"; "
                      + "/bin/bash \"$script\"; rc=$?; /bin/rm -f \"$script\"; exit $rc"
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
    private struct DescReq: Codable { let names: [String]; let isCask: Bool }
    private struct NameReq: Codable { let name: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            func json<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }
            switch cmd.name {
            case "status":        return json(await self.blocking { self.status() })
            case "listInstalled": return json(await self.blocking { self.listInstalled() })
            case "outdated":      return json(await self.blocking { self.outdated() })
            case "search":
                let query = String(decoding: cmd.payload, as: UTF8.self)
                return json(await self.blocking { self.search(query) })
            case "descriptions":
                guard let r = try? JSONDecoder().decode(DescReq.self, from: cmd.payload) else { return Data() }
                return json(await self.blocking { self.descriptions(names: r.names, isCask: r.isCask) })
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
