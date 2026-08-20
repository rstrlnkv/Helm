import Foundation
import HelmRuntime
import HelmContract

/// Manages Homebrew via the `brew` CLI. Fast queries answer over `transport.send`
/// (JSON); long operations (install/uninstall/upgrade/installBrew) stream
/// `opLog`/`opState` events. One long operation at a time.
///
/// **Every value goes behind a `--`.** Arguments are an array and the executable
/// path is absolute, so no shell ever sees them and there is nothing to inject
/// into — but `brew` parses them, and it reads a leading `-` as a flag wherever
/// it finds one. `query` is typed by the user; `name` is a word parsed out of
/// brew's own stdout. Verified against Homebrew 6.0.13: `brew search --formula
/// -n` prints usage and never searches, while `brew search --formula -- -n`
/// searches for `-n`.
public final class HomebrewEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It is the `module.homebrew.*` prefix of every setting this module has
    /// ever saved and the category its log lines file under.
    /// `HomebrewDescriptor.id` is built from this rather than repeating it,
    /// the direction the descriptors already carry their command enums, so the
    /// two spellings are one. **The string itself never changes** — it names
    /// stored settings already on people's machines.
    public static let moduleID = "homebrew"

    private let locator: BrewLocator
    private let runner: ProcessRunner
    private let privileged: PrivilegedRunner
    private let user: String
    private let localTransport: LocalTransport
    private let marker: OpMarker
    public let transport: EngineTransport

    private let lock = NSLock()
    private var busy = false
    /// The running operation's process, for `stop` — and the retention that
    /// keeps it addressable at all: the runner's local reference used to be
    /// the only one.
    private var current: RunningProcess?
    /// Whether the person asked for the end that is coming, so a signal death
    /// they requested is reported as `.stopped` and one they did not stays an
    /// honest failure. Cleared when the next operation starts.
    private var stopRequested = false

    private static let installerURL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

    public init(locator: BrewLocator, runner: ProcessRunner, privileged: PrivilegedRunner,
                user: String, transport: LocalTransport = LocalTransport(),
                marker: OpMarker = InMemoryOpMarker()) {
        self.locator = locator
        self.runner = runner
        self.privileged = privileged
        self.user = user
        self.localTransport = transport
        self.transport = transport
        self.marker = marker
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    // MARK: - Queries

    public func status() -> BrewStatus {
        let path = locator.brewPath()
        // Not while an operation runs: the marker belongs to the launch after
        // this one, and the page refreshes its status freely.
        lock.lock(); let running = busy; lock.unlock()
        let interrupted = running ? nil : marker.take()
        if let interrupted {
            // The label names a package; the log carries counts and outcomes.
            HelmLog.shared.warn(Self.moduleID,
                                "an operation was still running when Helm last quit "
                                + "(\(Redact.pkg(interrupted)))")
        }
        return BrewStatus(installed: path != nil, brewPath: path, interruptedOp: interrupted)
    }

    /// Whether the runner's deadline passed — with the outcome named in the
    /// log, because "brew is hung" shown as an empty list is a lie about the
    /// machine (`ATimedOutQueryIsANamedRefusalTests`).
    private func timedOut(_ status: Int32, query: String) -> Bool {
        guard status == HelmProcess.timedOutStatus else { return false }
        HelmLog.shared.warn(Self.moduleID, "\(query) timed out — keeping the last answer")
        return true
    }

    /// The tool's answer, or nil past the runner's deadline.
    ///
    /// **Only the deadline**, because for `search` a non-zero exit is an
    /// answer: measured against Homebrew 6.0.18, `brew search --formula --
    /// <no match>` exits 1 with empty stdout, which is how that subcommand
    /// spells "nothing found". `describe` reads it the same way for its own
    /// reason — a non-zero exit there is one name it cannot resolve, and the
    /// batch splits rather than gives up. Every other query wants `refused`.
    private func completed(_ result: (status: Int32, stdout: String),
                           query: String) -> String? {
        timedOut(result.status, query: query) ? nil : result.stdout
    }

    /// Whether brew declined to answer at all — the deadline, or any other
    /// non-zero exit.
    ///
    /// The exit code is the only thing left that knows: the sentence explaining
    /// a refusal goes to stderr and `HelmProcess` sends stderr to `nullDevice`.
    /// So a broken tap, a Ruby error, another brew holding the lock — a state
    /// this module reaches by itself, since a child brew survives the app —
    /// arrived here as empty stdout and was parsed into an empty list, which the
    /// page draws as a fact about the machine: "No packages installed." over a
    /// full Cellar, «Updates: 0» over thirty held-back updates.
    ///
    /// Measured on this Mac before trusting the code (Homebrew 6.0.18, three
    /// consecutive readings): `brew list --versions` and `brew outdated
    /// --json=v2` both exit **0** whatever they find — including with five
    /// packages outdated — so for these two a non-zero exit is never the
    /// answer's shape.
    private func refused(_ status: Int32, query: String) -> Bool {
        if timedOut(status, query: query) { return true }
        guard status != 0 else { return false }
        HelmLog.shared.warn(Self.moduleID,
                            "\(query) refused by brew, exit \(status) — keeping the last answer")
        return true
    }

    /// The tool's answer, or nil when it refused to give one.
    private func answered(_ result: (status: Int32, stdout: String),
                          query: String) -> String? {
        refused(result.status, query: query) ? nil : result.stdout
    }

    /// Labelled, like the scans in the other modules: reading and parsing the
    /// whole installed set is bulk work, and an operation that is not named in
    /// the memory trail cannot be blamed by it.
    ///
    /// This used to close with two things that are no longer true, and both
    /// were reasons not to trust the reading. `MemoryReclaim.afterHeavyWork` was
    /// measured returning 0 MB in nine probes and removed on 2026-07-31, so
    /// there is no reclaim for a phase to be missing; and `HelmLog.memory`
    /// prints on every call now rather than above 8 MB, because a gate that
    /// hides zero hides the answer (ARCHITECTURE.md § Memory).
    ///
    /// nil when brew did not answer in time — never an empty list, which reads
    /// as a clean machine.
    public func listInstalled() -> [BrewPackage]? {
        guard let brew = locator.brewPath() else {
            // The module's whole surface is empty in this case, and until now
            // nothing said why: a person reads "no packages" as a clean machine.
            HelmLog.shared.warn(Self.moduleID, "brew is not installed — nothing to list")
            return []
        }
        let packages = HelmActivity.phase("homebrew.listInstalled") { () -> [BrewPackage]? in
            // Both halves or neither: a refusal of the cask half alone kept the
            // formulae and every installed app vanished from the page, which is
            // worse than nothing because it looks complete.
            guard let f = answered(runner.run(brew, ["list", "--versions", "--formula"], env: [:]),
                                   query: "list formulae"),
                  let c = answered(runner.run(brew, ["list", "--versions", "--cask"], env: [:]),
                                   query: "list casks")
            else { return nil }
            return BrewListParser.parse(f, isCask: false) + BrewListParser.parse(c, isCask: true)
        }
        HelmLog.shared.memory("homebrew.listInstalled")
        // Counts, never names: a list of installed packages is a description of
        // somebody's machine and their work.
        if let packages { HelmLog.shared.info(Self.moduleID, "installed: \(packages.count)") }
        return packages
    }

    public func outdated() -> [OutdatedPackage]? {
        guard let brew = locator.brewPath() else { return [] }
        let parsed = HelmActivity.phase("homebrew.outdated") { () -> [OutdatedPackage]? in
            // `runData`, because the parser wants bytes: routing them through a
            // String held a second copy of the whole payload for the parse
            // (`OutdatedQueryAllocationBenchmark`).
            let result = runner.runData(brew, ["outdated", "--json=v2"], env: [:])
            guard !refused(result.status, query: "outdated") else { return nil }
            // And the parser answers nil too: bytes that are not the document
            // this decoder knows are not an up-to-date machine either.
            guard let parsed = BrewOutdatedParser.parse(result.stdout) else {
                HelmLog.shared.warn(Self.moduleID,
                                    "outdated: brew answered a shape this build cannot read "
                                    + "— keeping the last answer")
                return nil
            }
            return parsed
        }
        HelmLog.shared.memory("homebrew.outdated")
        if let parsed { HelmLog.shared.info(Self.moduleID, "outdated: \(parsed.count)") }
        return parsed
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
        // Bounded: the split is a bisection, and a batch refused wholesale
        // walks to a leaf per name (`DescriptionBudget`).
        let budget = DescriptionBudget(forBatchOf: names.count)
        // Named while it runs, like the two list queries: one batch covers the
        // whole installed set, and a bad name in it turns into a dozen calls.
        let found = HelmActivity.phase("homebrew.descriptions") {
            describe(names, isCask: isCask, brew: brew, budget: budget)
        }
        if budget.exhausted {
            // Counts, never names.
            HelmLog.shared.warn(Self.moduleID,
                                "descriptions: brew refused \(names.count) names wholesale "
                                + "— gave up after \(budget.allowance) calls")
        }
        HelmLog.shared.memory("homebrew.descriptions")
        return found
    }

    private func describe(_ names: [String], isCask: Bool, brew: String,
                          budget: DescriptionBudget) -> [String: String] {
        guard budget.spend() else { return [:] }
        let result = runner.run(brew, ["desc", isCask ? "--cask" : "--formula", "--"] + names, env: [:])
        if result.status == 0 { return BrewDescParser.parse(result.stdout) }
        // A timeout, never split: each half would hang for the same full
        // deadline, so a fifty-name batch would park the queue for hours.
        // Descriptions are a nicety; the rows draw without them.
        guard completed(result, query: "descriptions") != nil else { return [:] }
        // One name and it still failed: that is the name brew cannot resolve.
        // Nothing to say about it, and nothing it should cost the others.
        guard names.count > 1 else { return [:] }
        let middle = names.count / 2
        return describe(Array(names[..<middle]), isCask: isCask, brew: brew, budget: budget)
            .merging(describe(Array(names[middle...]), isCask: isCask, brew: brew,
                              budget: budget)) { a, _ in a }
    }

    public func search(_ query: String) -> [SearchHit]? {
        guard let brew = locator.brewPath(), !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let hits = HelmActivity.phase("homebrew.search") { () -> [SearchHit]? in
            // One call per kind: brew no longer labels a flat result list, and
            // the kind decides whether the install is `brew install` or `brew
            // install --cask`. Ids are already namespaced f:/c:, so a name that
            // exists as both stays two distinguishable rows.
            guard let formulae = completed(runner.run(brew, ["search", "--formula", "--", query], env: [:]),
                                           query: "search formulae"),
                  let casks = completed(runner.run(brew, ["search", "--cask", "--", query], env: [:]),
                                        query: "search casks")
            else { return nil }
            return BrewSearchParser.parse(formulae, isCask: false)
                 + BrewSearchParser.parse(casks, isCask: true)
        }
        HelmLog.shared.memory("homebrew.search")
        // brew answers alphabetically, which buries the obvious one.
        return hits.map { SearchRanking.rank($0, query: query) }
    }

    // MARK: - Long operations

    /// One phase for all five long operations, opened and closed by the busy
    /// gate itself. An operation ends in a callback, so no scope can hold its
    /// phase — but a `begin` balanced by hand is what the scope rule exists to
    /// remove, so the balance rides the one this module already keeps: the
    /// gate, whose release `OneOperationAtATimeTests` guards on every path. An
    /// unclosed phase here is a wedged module, which is a failure four tests
    /// already catch. The verb is in the `[homebrew]` info line beside it; the
    /// label carries no package name, because the trail is the log's.
    private static let operationPhase = "homebrew.operation"

    private func beginBusy() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if busy { return false }
        busy = true
        stopRequested = false
        HelmActivity.begin(Self.operationPhase)
        return true
    }
    private func endBusy() {
        lock.lock(); busy = false; current = nil; lock.unlock()
        HelmActivity.end(Self.operationPhase)
        HelmLog.shared.memory("homebrew.operation")
    }

    /// Whether the exit that just landed was asked for. Read at the exit, not
    /// when Stop is pressed: the answer belongs to the operation that ends.
    private var wasStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopRequested
    }

    /// The one way every long operation ends, whatever started it: the stop
    /// answer is read while it is still this operation's, the marker cleared
    /// before the gate opens (or the next operation's marker could lose to
    /// this one's clear), the gate opened, the state event sent. Returns
    /// whether the end was asked for, so the caller can word its log line.
    ///
    /// `code` is nil when no child ever ran — a stop that landed before the
    /// launch. There is no exit code for a process that was never started, and
    /// inventing one would put a number on the page's failure that names
    /// nothing.
    @discardableResult
    private func concludeOp(code: Int32?, label: String) -> Bool {
        let stopped = wasStopped
        marker.clear()
        endBusy()
        // nil is "no child ever ran", which is not a success.
        let phase: OpPhase = code == 0 ? .done : .failed
        emitState(OpState(phase: phase, label: label, exitCode: code.map(Int.init),
                          reason: phase == .failed && stopped ? .stopped : nil))
        return stopped
    }

    /// Ends the running long operation. SIGTERM through the handle; the exit
    /// arrives the way every exit does — EOF, then `onExit` — so the busy gate
    /// and the state event follow the one path they already have.
    ///
    /// **The press is recorded even when there is nothing to terminate yet.**
    /// This used to `guard busy, let handle = current`, and `current` is set
    /// after the child has been launched: everything before that point is a
    /// window in which the page shows a live Stop button and the press falls
    /// into a bare `return` — no state, no log, and `stopRequested` never set,
    /// so nothing later could tell that the person had asked. The launch reads
    /// the flag instead (`stoppedBeforeLaunch`).
    public func stop() {
        lock.lock()
        guard busy else { lock.unlock(); return }
        stopRequested = true
        let handle = current
        lock.unlock()
        HelmLog.shared.info(Self.moduleID, "stop requested")
        handle?.terminate()
    }

    /// Whether the person pressed Stop before this operation had a child, in
    /// which case the operation ends here and the launch must not happen.
    ///
    /// For a package operation that window is a spawn, measured in
    /// milliseconds. For `installBrew` it is **the administrator password
    /// dialog**: `runAdmin` blocks this thread for as long as a person takes to
    /// find their password, and the module used to go on to download and run
    /// the Homebrew installer after a Stop pressed while it was up.
    ///
    /// Nothing was launched, so no `onExit` is coming to conclude the operation
    /// — it is concluded here, or the gate stays shut for the life of the app.
    private func stoppedBeforeLaunch(label: String) -> Bool {
        guard wasStopped else { return false }
        HelmLog.shared.info(Self.moduleID, "stopped before the child was started")
        concludeOp(code: nil, label: label)
        return true
    }

    private func emitLog(_ line: String) {
        localTransport.emit(EngineEvent(name: HomebrewEvent.opLog.rawValue,
                                        payload: Data(line.utf8)))
    }
    private func emitState(_ s: OpState) {
        localTransport.emit(HomebrewEvent.opState, encoding: s)
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
            HelmLog.shared.warn(Self.moduleID, "\(verb) refused: another operation is running")
            emitLog("⚠︎ Another operation is already running.")
            return
        }
        let what = subject.map { "\(verb) \(Redact.pkg($0))" } ?? verb
        HelmLog.shared.info(Self.moduleID, "\(what) started")
        emitState(OpState(phase: .running, label: label))
        startChild(label: label, launch: launch, args: args, env: env) { [weak self] code in
            guard let self else { return }
            let stopped = self.concludeOp(code: code, label: label)
            if code == 0 {
                HelmLog.shared.info(Self.moduleID, "\(what) done")
            } else if stopped {
                HelmLog.shared.info(Self.moduleID, "\(what) stopped on request, exit \(code)")
            } else {
                HelmLog.shared.warn(Self.moduleID, "\(what) failed, exit \(code)")
            }
        }
    }

    /// **The one place this module starts a child**, so the three things that
    /// belong to every launch cannot be remembered at one site and forgotten at
    /// the next: the Stop that arrived before the child existed, the marker
    /// that reports a quit mid-operation, and the handle joining the operation
    /// it belongs to. The two callers differ only in what they say at the exit.
    private func startChild(label: String, launch: String, args: [String],
                            env: [String: String],
                            onExit: @escaping @Sendable (Int32) -> Void) {
        guard !stoppedBeforeLaunch(label: label) else { return }
        // The child survives a quit; whatever is still written at the next
        // launch is the report (`AQuitMidOperationIsReportedTests`).
        marker.write(label)
        adopt(runner.stream(launch, args, env: env,
                            onLine: { [weak self] line in self?.emitLog(line) },
                            onExit: onExit))
    }

    /// The handle joins the operation it belongs to — unless the operation has
    /// already ended (a stream that exits synchronously releases the gate
    /// before it returns), in which case there is nothing left to address.
    private func adopt(_ handle: RunningProcess) {
        lock.lock()
        guard busy else { lock.unlock(); return }
        current = handle
        let stopped = stopRequested
        lock.unlock()
        // The other half of the window `stoppedBeforeLaunch` closes: a press
        // that landed after that check and before this line found `current`
        // still nil, so it terminated nothing. It has a child to reach now.
        if stopped { handle.terminate() }
    }

    /// brew can vanish between `status()` and the press: Homebrew's own
    /// uninstaller in a terminal, with Helm's window sitting open on the list
    /// brew answered before it went. This used to be a bare `return` — no
    /// `opState`, no log, a button that did nothing visibly forever. A refusal
    /// is an outcome and it is named (`AVanishedBrewIsNotASilentPressTests`).
    private func brewOrRefuse(verb: String, label: String) -> String? {
        if let brew = locator.brewPath() { return brew }
        HelmLog.shared.warn(Self.moduleID, "\(verb) refused: brew is no longer installed")
        emitState(OpState(phase: .failed, label: label, reason: .brewMissing))
        return nil
    }

    public func install(name: String, isCask: Bool) {
        guard let brew = brewOrRefuse(verb: "install", label: "install \(name)") else { return }
        runOp(verb: "install", subject: name, label: "install \(name)", launch: brew, args: isCask ? ["install", "--cask", "--", name] : ["install", "--", name])
    }
    public func uninstall(name: String, isCask: Bool) {
        guard let brew = brewOrRefuse(verb: "uninstall", label: "uninstall \(name)") else { return }
        runOp(verb: "uninstall", subject: name, label: "uninstall \(name)", launch: brew, args: isCask ? ["uninstall", "--cask", "--", name] : ["uninstall", "--", name])
    }
    public func upgrade(name: String) {
        guard let brew = brewOrRefuse(verb: "upgrade", label: "upgrade \(name)") else { return }
        runOp(verb: "upgrade", subject: name, label: "upgrade \(name)", launch: brew, args: ["upgrade", "--", name])
    }
    public func upgradeAll() {
        guard let brew = brewOrRefuse(verb: "upgrade all", label: "upgrade all") else { return }
        runOp(verb: "upgrade all", label: "upgrade all", launch: brew, args: ["upgrade"])
    }

    /// Install Homebrew itself: pre-create /opt/homebrew owned by the user via one
    /// native admin prompt, then run the official installer non-interactively.
    public func installBrew() {
        // One label, read by every way this operation can end — including the
        // marker, which is compared against nothing but itself.
        let label = "install Homebrew"
        guard beginBusy() else { emitLog("⚠︎ Another operation is already running."); return }
        emitState(OpState(phase: .running, label: label))
        // `user` is NSUserName(), which on a managed Mac is whatever the
        // directory says; this string is evaluated by a root shell. Single
        // quotes stop expansion, and the name is checked before it gets there.
        guard AccountName.isPlausible(user) else {
            concludeOp(code: 1, label: label)
            emitLog("Unsupported account name.")
            return
        }
        // Absolute paths, because this string is resolved by a root shell that
        // inherits our `PATH` — and Helm's environment comes from the launchd
        // GUI session, which any process running as the user can rewrite
        // (`launchctl setenv PATH …`). A bare `mkdir` is then whichever `mkdir`
        // that process planted. Every other privileged string in the app
        // already names its tools in full; see `SudoersRule.installCommand`.
        let prep = "/bin/mkdir -p /opt/homebrew && /usr/sbin/chown -R '\(user)':admin /opt/homebrew"
        guard privileged.runAdmin(prep) else {
            concludeOp(code: 1, label: label)
            emitLog("Administrator authorization was cancelled.")
            return
        }
        // Download, then run — not `eval "$(curl …)"`, where a failed download
        // evaluates the empty string, exits 0, and the module reports a
        // successful install of nothing.
        let installer = "set -e; script=$(/usr/bin/mktemp); "
                      + "/usr/bin/curl -fsSL \(Self.installerURL) -o \"$script\"; "
                      + "/bin/bash \"$script\"; rc=$?; /bin/rm -f \"$script\"; exit $rc"
        // The dialog above blocked this thread for as long as the person took
        // to find their password, with a live Stop button on the page the whole
        // time; `startChild` is where a press that landed during it is read.
        startChild(label: label, launch: "/bin/bash", args: ["-c", installer],
                   env: ["NONINTERACTIVE": "1"]) { [weak self] code in
            self?.concludeOp(code: code, label: label)
        }
    }

    // MARK: - Transport

    /// nil folded to the wire's zero bytes — "the module could not answer",
    /// which a timed-out query is; the view model keeps the last answer it
    /// had. `fileID`/`line` pass through, so `EngineReply`'s error line still
    /// names the arm and not this fold.
    private func reply<T: Encodable>(_ value: T?, for cmd: EngineCommand,
                                     fileID: String = #fileID, line: Int = #line) -> Data {
        guard let value else { return Data() }
        return EngineReply.encode(value, for: cmd, fileID: fileID, line: line)
    }

    /// **No `default`.** Every case of `HomebrewCommand` has an arm, which is
    /// what the enum's own doc comment promises — and a `default: break` sat at
    /// the bottom making that promise false: a case added to the enum would have
    /// fallen through it and answered `Data()`, which this codebase reads as
    /// «the module could not answer». The unknown-name door is one line above,
    /// where it belongs.
    private func wireTransport() {
        localTransport.setHandler { [weak self] cmd in
            guard let self else { return Data() }
            // The local `json(_:)` these arms shared is `EngineReply` now — the
            // same fold, where the other eight engines can reach it. Spelled per
            // arm rather than wrapped again, because the helper takes its `#line`
            // from the call site and a wrapper would report every arm as itself.
            guard let name = HomebrewCommand(rawValue: cmd.name) else { return Data() }
            switch name {
            case .status:
                return EngineReply.encode(await offTheCooperativePool { self.status() }, for: cmd)
            // The three queries below can answer nil — a timeout, which must
            // not reach the page as an empty machine; `reply` folds it to the
            // wire's zero bytes.
            case .listInstalled:
                return self.reply(await offTheCooperativePool { self.listInstalled() }, for: cmd)
            case .outdated:
                return self.reply(await offTheCooperativePool { self.outdated() }, for: cmd)
            case .search:
                let query = String(decoding: cmd.payload, as: UTF8.self)
                return self.reply(await offTheCooperativePool { self.search(query) }, for: cmd)
            case .descriptions:
                guard let r = EngineReply.decode(DescriptionsRequest.self, from: cmd)
                else { return Data() }
                let found = await offTheCooperativePool { self.descriptions(names: r.names, isCask: r.isCask) }
                return EngineReply.encode(found, for: cmd)
            case .install:
                if let r = EngineReply.decode(PackageRef.self, from: cmd) {
                    self.install(name: r.name, isCask: r.isCask)
                }
            case .uninstall:
                if let r = EngineReply.decode(PackageRef.self, from: cmd) {
                    self.uninstall(name: r.name, isCask: r.isCask)
                }
            // A bare name, like `search` — the one-field struct that used to
            // wrap it bought nothing and cost a second declaration.
            case .upgrade: self.upgrade(name: String(decoding: cmd.payload, as: UTF8.self))
            case .upgradeAll: self.upgradeAll()
            case .installBrew: self.installBrew()
            case .stop: self.stop()
            }
            return Data()
        }
    }
}
