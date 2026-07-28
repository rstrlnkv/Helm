import Foundation
import HelmRuntime
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
    /// Descriptions for a batch, and the batch does not fail as a unit.
    ///
    /// `brew desc` validates every name before it prints anything, so one name
    /// it can no longer resolve — installed from a tap since removed, renamed
    /// upstream, still on disk and still reported by `brew list --versions` —
    /// makes the whole call exit non-zero with **empty** stdout. The status was
    /// thrown away, so every row on the page lost its description and nothing
    /// said why.
    ///
    /// A failure splits the batch and asks again. A single bad name in fifty
    /// costs about a dozen calls instead of fifty, and a good batch is still
    /// exactly one.
    public func descriptions(names: [String], isCask: Bool) -> [String: String] {
        guard let brew = locator.brewPath(), !names.isEmpty else { return [:] }
        return describe(names, isCask: isCask, brew: brew)
    }

    private func describe(_ names: [String], isCask: Bool, brew: String) -> [String: String] {
        let result = runner.run(brew, ["desc", isCask ? "--cask" : "--formula"] + names, env: [:])
        if result.status == 0 { return BrewDescParser.parse(result.stdout) }
        // One name and it still failed: that is the name brew cannot resolve.
        // Nothing to say about it, and nothing it should cost the others.
        guard names.count > 1 else { return [:] }
        let middle = names.count / 2
        return describe(Array(names[..<middle]), isCask: isCask, brew: brew)
            .merging(describe(Array(names[middle...]), isCask: isCask, brew: brew)) { a, _ in a }
    }

    public func search(_ query: String) -> [SearchHit] {
        guard let brew = locator.brewPath(), !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        // One call per kind: brew no longer labels a flat result list, and the
        // kind decides whether the install is `brew install` or `brew install
        // --cask`. Ids are already namespaced f:/c:, so a name that exists as
        // both stays two distinguishable rows.
        let formulae = runner.run(brew, ["search", "--formula", query], env: [:]).stdout
        let casks = runner.run(brew, ["search", "--cask", query], env: [:]).stdout
        let hits = BrewSearchParser.parse(formulae, kind: false)
                 + BrewSearchParser.parse(casks, kind: true)
        // brew answers alphabetically, which buries the obvious one.
        return SearchRanking.rank(hits, query: query)
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

    /// `verb` is what happened; `subject` is the package it happened to, kept
    /// apart from the label so the log can carry one and redact the other.
    ///
    /// Every operation this module runs comes through here, and until this was
    /// written none of them left a trace: two package operations that changed
    /// the machine — an install and an uninstall — produced 0 lines in
    /// helm.log, which is the file the dev channel is triaged against.
    private func runOp(verb: String, subject: String? = nil,
                       label: String, launch: String, args: [String],
                       env: [String: String] = [:]) {
        guard beginBusy() else {
            HelmLog.shared.warn("homebrew", "\(verb) refused: another operation is running")
            emitLog("⚠︎ Another operation is already running.")
            return
        }
        let what = subject.map { "\(verb) \(Redact.pkg($0))" } ?? verb
        HelmLog.shared.info("homebrew", "\(what) started")
        emitState(OpState(phase: .running, label: label))
        runner.stream(launch, args, env: env,
                      onLine: { [weak self] line in self?.emitLog(line) },
                      onExit: { [weak self] code in
                          guard let self else { return }
                          self.endBusy()
                          if code == 0 {
                              HelmLog.shared.info("homebrew", "\(what) done")
                          } else {
                              HelmLog.shared.warn("homebrew", "\(what) failed, exit \(code)")
                          }
                          self.emitState(OpState(phase: code == 0 ? .done : .failed,
                                                 label: label, exitCode: Int(code)))
                      })
    }

    public func install(name: String, isCask: Bool) {
        guard let brew = locator.brewPath() else { return }
        runOp(verb: "install", subject: name, label: "install \(name)", launch: brew, args: isCask ? ["install", "--cask", name] : ["install", name])
    }
    public func uninstall(name: String, isCask: Bool) {
        guard let brew = locator.brewPath() else { return }
        runOp(verb: "uninstall", subject: name, label: "uninstall \(name)", launch: brew, args: isCask ? ["uninstall", "--cask", name] : ["uninstall", name])
    }
    public func upgrade(name: String) {
        guard let brew = locator.brewPath() else { return }
        runOp(verb: "upgrade", subject: name, label: "upgrade \(name)", launch: brew, args: ["upgrade", name])
    }
    public func upgradeAll() {
        guard let brew = locator.brewPath() else { return }
        runOp(verb: "upgrade all", label: "upgrade all", launch: brew, args: ["upgrade"])
    }

    /// Install Homebrew itself: pre-create /opt/homebrew owned by the user via one
    /// native admin prompt, then run the official installer non-interactively.
    public func installBrew() {
        guard beginBusy() else { emitLog("⚠︎ Another operation is already running."); return }
        emitState(OpState(phase: .running, label: "install Homebrew"))
        // `user` is NSUserName(), which on a managed Mac is whatever the
        // directory says; this string is evaluated by a root shell. Single
        // quotes stop expansion, and the name is checked before it gets there.
        guard AccountName.isPlausible(user) else {
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
            case "status":        return json(await offTheCooperativePool { self.status() })
            case "listInstalled": return json(await offTheCooperativePool { self.listInstalled() })
            case "outdated":      return json(await offTheCooperativePool { self.outdated() })
            case "search":
                let query = String(decoding: cmd.payload, as: UTF8.self)
                return json(await offTheCooperativePool { self.search(query) })
            case "descriptions":
                guard let r = try? JSONDecoder().decode(DescReq.self, from: cmd.payload) else { return Data() }
                return json(await offTheCooperativePool { self.descriptions(names: r.names, isCask: r.isCask) })
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
