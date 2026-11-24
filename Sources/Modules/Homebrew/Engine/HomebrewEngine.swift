import Foundation
import HelmRuntime
import HelmContract

/// Manages Homebrew via the `brew` CLI. The model reads it through the typed
/// members of "The model's door" and presses through `perform(_:)`; long
/// operations (install/uninstall/upgrade/installBrew) stream `HomebrewNews` on
/// `stream()`. One long operation at a time.
///
/// **Every value goes behind a `--`.** Arguments are an array and the executable
/// path is absolute, so no shell ever sees them and there is nothing to inject
/// into — but `brew` parses them, and it reads a leading `-` as a flag wherever
/// it finds one. `query` is typed by the user; `name` is a word parsed out of
/// brew's own stdout. `brew search --formula -n` prints usage and never
/// searches; `brew search --formula -- -n` searches for `-n`.
///
/// **No gate of its own on a package reference.** The engine executes the name
/// it is handed through the door, which is sound only while the model is the one
/// caller, in-process.
public final class HomebrewEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down: the
    /// `module.homebrew.*` prefix of its settings and its log category;
    /// `HomebrewDescriptor.id` is built from it. **The string never changes**:
    /// it names stored settings already on people's machines.
    public static let moduleID = "homebrew"

    /// What `list`, `desc`, `uses`, `info` and `config` run with, and `doctor`
    /// through `doctorEnvironment`.
    ///
    /// `brew list --versions` answers about packages already installed and
    /// `brew desc` describes the names it is given; neither reading changes
    /// when the catalogue is refreshed. Left
    /// to itself brew may refresh it anyway, which turns a question about this
    /// disk into a download nobody asked for — and on a Mac with no network at
    /// all, into a failure to answer something brew already knew.
    ///
    /// **This is about what a local read is allowed to do, not about speed**:
    /// brew refreshes periodically rather than per call, so on a warm machine
    /// the variable changes no timing.
    ///
    /// **Not `outdated`, and not `search`.** Those two are answers *about* the
    /// catalogue: refusing the refresh there would let «Updates: 0» stand over a
    /// catalogue weeks old, which is the same lie as an empty list over a full
    /// Cellar. The one exception is the person's own: `outdated` runs with this
    /// environment when the setting `UpdateBeforeChecking` is OFF.
    static let queryEnvironment = ["HOMEBREW_NO_AUTO_UPDATE": "1"]

    /// What `brew doctor` runs with: the query environment and
    /// **`HOMEBREW_NO_COLOR`**, because doctor is the one query whose answer is
    /// read by finding a line that starts `Warning:`. brew colours a non-terminal
    /// stream when `HOMEBREW_COLOR` is set — in the environment or in a
    /// `brew.env` file it loads itself, which beats the environment — and a
    /// coloured line starts with an escape, so no finding is found. The variable
    /// overrides the colour. It is this query's alone: `list`, `search` and `desc` print the same bytes
    /// coloured or not, and `config` echoes the variables it sees, so it would
    /// put one of Helm's own into the text a person copies into a bug report.
    static let doctorEnvironment = queryEnvironment.merging(["HOMEBREW_NO_COLOR": "1"]) { _, new in new }

    /// What a long operation runs with. The console is a place a person reads
    /// what brew is doing to their machine; brew's environment hints are advice
    /// about shell profiles, several lines of it, printed beside the install
    /// they are watching.
    ///
    /// `installBrew` is the one long operation that does not carry this, and
    /// cannot: it runs Homebrew's own `install.sh` under `/bin/bash`, not
    /// `brew`, so there is no brew yet to read the variable.
    static let operationEnvironment = ["HOMEBREW_NO_ENV_HINTS": "1"]

    /// What Homebrew's own `install.sh` runs with.
    ///
    /// `NONINTERACTIVE` because there is no terminal for its questions.
    /// **`HOMEBREW_NO_SUDO`** because the script probes for `sudo` and, with the
    /// probe passing, calls a `sudo` that has no terminal and no askpass to ask
    /// on: docs.brew.sh/Installation documents the variable as the way to turn
    /// its `sudo` calls off. The probe passes on any Mac with a `NOPASSWD` rule
    /// in `/etc/sudoers.d`, and Keep Awake writes one. Everything the script needs root for, Helm did in the one dialog before it.
    static let installerEnvironment = ["NONINTERACTIVE": "1", "HOMEBREW_NO_SUDO": "1"]

    /// The label every way `installBrew` can end carries. It is English because
    /// it is a log line and a state's name, not a sentence: the page words this
    /// operation in the person's language by comparing against this constant
    /// (`HbStr.operationName`, `HbStr.interruptedAtQuit`). Every other label is
    /// shown as written where it is made, a phrase naming the brew run without
    /// the word `brew` (`upgrade wget`, `upgrade all`), untranslated.
    public static let installBrewLabel = "install Homebrew"

    /// Seconds between two looks at whether Apple's tools have arrived. The wait
    /// has no deadline, because an install of Apple's tools may honestly take a
    /// long while.
    static let toolsTick: TimeInterval = 2

    private let locator: BrewLocator
    private let runner: ProcessRunner
    private let privileged: PrivilegedRunner
    private let user: String
    private let news: EngineNews<HomebrewNews>
    private let marker: OpMarker
    private let popularity: PopularityReading
    private let weight: PackageWeight
    private let tools: CommandLineToolsPort
    private let ticker: WaitTicker
    /// Shared by every engine of the process in the app (`OperationGate.process`).
    private let gate: OperationGate
    /// Read at each `outdated()`: ON asks brew with no environment (it refreshes the
    /// catalogue first), OFF with `queryEnvironment`.
    private let updateBeforeChecking: UpdateBeforeChecking

    private let lock = NSLock()
    private var busy = false
    /// Started by `activate()`, cancelled by `deactivate()`, not left to
    /// `deinit`: a module switched off mid-fetch must stop reaching the network.
    /// What the task may capture is spelled out in `activate()`.
    private var popularityRefresh: Task<Void, Never>?
    /// The running operation's process, for `stop`, and the one reference that
    /// keeps it addressable.
    private var current: RunningProcess?
    /// Whether the person asked for the end that is coming, so a signal death
    /// they requested is reported as `.stopped` and one they did not stays an
    /// honest failure. Cleared when the next operation starts.
    private var stopRequested = false
    /// Whether the running operation is the install of Homebrew itself, the one
    /// long operation `deactivate()` ends: it is the one that can raise a
    /// password dialog and start `install.sh` on its own, later, for a module
    /// the person has switched off. A package operation or a doctor fix is left
    /// to finish: terminating a half-built `brew` run is how a broken Cellar is
    /// made (`AQuitMidOperationIsReportedTests`). Set with the gate, cleared with it.
    private var installing = false
    /// Whether the module is switched off: set by `deactivate()`, cleared by
    /// `activate()`. While it is set the gate admits no operation, so nothing
    /// launches a child for a module that is off (`beginBusy`). Under `lock`.
    private var off = false
    /// What each package was last measured to occupy, keyed `f:name@version`.
    /// Under `lock`, emptied in `concludeOp`; the lock is never held across the
    /// walk itself, the part that takes time.
    private var sizes: [String: Int] = [:]
    /// The wait for Apple's Command Line Tools, as its token: the tick that is
    /// armed, cancelled by releasing it. Under `lock`, and **whoever sets it to
    /// nil owns the ending of the operation** — a tick that reached a verdict,
    /// `stop()`, `deactivate()` — so no two of them can both end it.
    private var toolsWait: AnyObject?
    /// Which wait a tick belongs to, so a tick already in flight when Stop was
    /// pressed and Install pressed again cannot act for the new wait. Under `lock`.
    private var waitGeneration = 0
    /// What the wait has read so far. Under `lock`; written by the ticks, which
    /// are serial because each one arms the next.
    private var waitReading = CommandLineTools.Wait()

    /// Names `HEAD` rather than a pinned revision or a checksum: whatever the
    /// branch holds the day the button is pressed is what runs.
    private static let installerURL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

    public init(locator: BrewLocator, runner: ProcessRunner, privileged: PrivilegedRunner,
                user: String, news: EngineNews<HomebrewNews> = EngineNews(),
                marker: OpMarker = InMemoryOpMarker(),
                popularity: PopularityReading = NoPopularity(),
                weight: PackageWeight = NoPackageWeight(),
                tools: CommandLineToolsPort = ToolsAlreadyInstalled(),
                ticker: WaitTicker = NoWaitTicker(),
                gate: OperationGate = OperationGate(),
                updateBeforeChecking: UpdateBeforeChecking = .inMemory) {
        self.locator = locator
        self.runner = runner
        self.privileged = privileged
        self.user = user
        self.news = news
        self.marker = marker
        self.popularity = popularity
        self.weight = weight
        self.tools = tools
        self.ticker = ticker
        self.gate = gate
        self.updateBeforeChecking = updateBeforeChecking
    }

    public func activate() {
        // Where brew is, filed first (ARCHITECTURE.md § The model). The
        // locator and not `status()`: that one takes the quit marker.
        news.say(.brew(path: locator.brewPath().flatMap { $0.isEmpty ? nil : $0 }),
                 slot: HomebrewSlot.brewFound.rawValue)
        // Not in `init`, because `init` runs for every module the host knows
        // about and `activate` only for the ones that are switched on: a module
        // the person has turned off never reaches the network for readings its
        // search box will not draw. The store's daily gate keeps a launch from
        // being a fetch every time.
        //
        // **`[popularity]` and nothing else.** The task points at no part of
        // this engine, so `deinit` can cancel it. A `self` capture, even a weak
        // one, keeps `deinit` from running while the task is alive
        // (ARCHITECTURE.md § State that outlives a page and ends with its module).
        //
        // **Started under the lock.** Created outside it, the fetch runs while
        // the field is still nil, and a `deactivate()` landing there cancels
        // nothing. `Task { }` does not suspend and the body takes the store's
        // lock, never this one, so this cannot deadlock.
        lock.lock()
        off = false
        // Cancel before assigning, or a second activation orphans the first fetch.
        let orphan = popularityRefresh
        popularityRefresh = Task { [popularity] in await popularity.refreshIfDue() }
        lock.unlock()
        orphan?.cancel()
    }

    public func deactivate() {
        cancelTheRefresh()
        endTheOperation()
    }

    /// The backstop for the routes that do not go through `deactivate()`.
    /// ARCHITECTURE.md § An observer outlives the thing it points at. The wait
    /// token is dropped here and no event is sent: the block holds `self` weakly,
    /// so the engine is what the token was never keeping alive, and an engine
    /// that is going has nobody to tell.
    deinit {
        cancelTheRefresh()
        lock.lock()
        let wait = toolsWait
        toolsWait = nil
        lock.unlock()
        _ = wait
        // An engine dropped in the tools wait (no child, a weak tick) would
        // keep the process-wide gate shut for good. Owner-checked: a no-op
        // when this engine holds nothing.
        gate.release(self)
    }

    /// A module switched off shuts the gate (`off`) for **every** kind of
    /// operation and ends the **install of Homebrew** as stopped, wherever it
    /// is, **whether or not there is a wait to take**. Every step that would ask
    /// Apple, raise the administrator dialog or launch `install.sh` reads the
    /// flag first (`stoppedBeforeLaunch`), so a switch-off landing between any
    /// two of them finds a check waiting. The wait is released here, so no later
    /// tick can raise a password dialog for a module that is off; a running
    /// child is terminated, as Stop does.
    ///
    /// **A package operation or a doctor fix is not terminated**
    /// (ARCHITECTURE.md § The model). Its exit reaches `concludeOp`
    /// because `runOp`'s `onExit` holds the engine strongly; a weak hold would
    /// lose it with the engine the host drops, and the marker would stay.
    private func endTheOperation() {
        lock.lock()
        off = true
        guard busy, installing else { lock.unlock(); return }
        stopRequested = true
        let wait = toolsWait
        toolsWait = nil
        let handle = current
        lock.unlock()
        endWaitOrTerminate(wait: wait, handle: handle,
                           waitLine: "\(Self.installBrewLabel) stopped waiting: module switched off")
    }

    /// The tail Stop and the switch-off share: a wait that was taken is logged
    /// and concluded here, since no child and no exit are coming; otherwise
    /// the child, if any, is terminated.
    private func endWaitOrTerminate(wait: AnyObject?, handle: RunningProcess?, waitLine: String) {
        if wait != nil {
            HelmLog.shared.info(Self.moduleID, waitLine)
            concludeOp(code: nil, label: Self.installBrewLabel, reason: nil)
            return
        }
        handle?.terminate()
    }

    /// Taken under the lock, cancelled outside it.
    private func cancelTheRefresh() {
        lock.lock()
        let task = popularityRefresh
        popularityRefresh = nil
        lock.unlock()
        task?.cancel()
    }

    // MARK: - Queries

    func status() -> BrewStatus {
        let path = locator.brewPath()
        // Not while any engine's operation runs: its marker belongs to the
        // launch after this one, and the page refreshes its status freely.
        let interrupted = gate.takeMarkerIfFree(marker)
        if let interrupted {
            // The label names a package; the log carries counts and outcomes.
            HelmLog.shared.warn(Self.moduleID,
                                "an operation was still running when Helm last quit "
                                + "(\(Redact.pkg(interrupted)))")
        }
        return BrewStatus(installed: path != nil, brewPath: path, interruptedOp: interrupted)
    }

    /// Whether the runner's deadline passed, with the outcome named in the
    /// log: "brew is hung" shown as an empty list is a lie about the machine
    /// (`ATimedOutQueryIsANamedRefusalTests`). "Keeping the last answer" only
    /// for the queries whose caller keeps one (`outcome(of:)`); the others say
    /// "no answer".
    private func timedOut(_ status: Int32, query: String) -> Bool {
        guard status == HelmProcess.timedOutStatus else { return false }
        HelmLog.shared.warn(Self.moduleID, "\(query) timed out — \(Self.outcome(of: query))")
        return true
    }

    /// What became of a query's absent answer, for the log line.
    private static func outcome(of query: String) -> String {
        ["list formulae", "list casks", "outdated", "config", "descriptions"].contains(query)
            ? "keeping the last answer" : "no answer"
    }

    /// The tool's answer, or nil past the runner's deadline.
    ///
    /// **Only the deadline**, because for `search` a non-zero exit is an
    /// answer: `brew search --formula -- <no match>` exits 1 with empty stdout.
    /// For `describe` a non-zero exit is one name it cannot resolve, and the
    /// batch splits rather than gives up. Every other query wants `refused`.
    private func completed(_ result: (status: Int32, stdout: String),
                           query: String) -> String? {
        timedOut(result.status, query: query) ? nil : result.stdout
    }

    /// Whether brew declined to answer at all — the deadline, or any other
    /// non-zero exit.
    ///
    /// The exit code is the only thing left that knows: the sentence explaining
    /// a refusal goes to stderr, which `HelmProcess` sends to `nullDevice`.
    /// A broken tap, a Ruby error or another brew holding the lock (a child brew
    /// survives the app) is empty stdout, which parsed as an empty list would
    /// read "No packages installed." over a full Cellar.
    ///
    /// `brew list --versions` and `brew outdated --json=v2` exit **0** whatever
    /// they find, so for these two a non-zero exit is never the answer's shape.
    private func refused(_ status: Int32, query: String) -> Bool {
        if timedOut(status, query: query) { return true }
        guard status != 0 else { return false }
        HelmLog.shared.warn(Self.moduleID,
                            "\(query) refused by brew, exit \(status) — \(Self.outcome(of: query))")
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
    /// nil when there is no brew, or brew refused or did not answer in time:
    /// never an empty list, which reads as a clean machine.
    func listInstalled() -> [BrewPackage]? {
        guard let brew = locator.brewPath() else {
            // nil, not an empty list: a person reads "no packages" as a clean
            // machine, and the model draws brew-missing on nil.
            HelmLog.shared.warn(Self.moduleID, "brew is not installed — nothing to list")
            return nil
        }
        let packages = HelmActivity.phase("homebrew.listInstalled") { () -> [BrewPackage]? in
            // Both halves or neither: formulae without casks looks complete
            // while every installed app is missing.
            guard let f = answered(runner.run(brew, ["list", "--versions", "--formula"],
                                              env: Self.queryEnvironment),
                                   query: "list formulae"),
                  let c = answered(runner.run(brew, ["list", "--versions", "--cask"],
                                              env: Self.queryEnvironment),
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

    func outdated() -> [OutdatedPackage]? {
        guard let brew = locator.brewPath() else { return nil }
        let parsed = HelmActivity.phase("homebrew.outdated") { () -> [OutdatedPackage]? in
            // `runData`: the parser wants bytes, and a String would be a second
            // copy of the whole payload.
            let result = runner.runData(brew, ["outdated", "--json=v2"],
                                           env: updateBeforeChecking.isOn ? [:] : Self.queryEnvironment)
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

    /// One `brew desc` call per batch of names, a batch being no more than one
    /// argv carries (`HelmProcess.maxArguments`). A search that matches
    /// everything hands over thousands of formulae, and `NSTask` raises on that
    /// many arguments, which `describe` would read as brew refusing the batch.
    ///
    /// The batches stop after the first one that showed a property of the tool
    /// rather than of a name: one that timed out, or one refused wholesale. Each
    /// further batch would cost a full deadline or up to `n + 1` launches to
    /// learn the same thing.
    ///
    /// They stop too when `stillWanted` says no, asked before each batch after
    /// the first: a search typed over has nobody waiting for its descriptions,
    /// and the newer search queues behind this call. The batch in flight
    /// finishes; a launched `brew` is not interrupted.
    ///
    /// Within a batch, one name brew can no longer resolve (from a tap since
    /// removed, renamed upstream) makes `brew desc` exit non-zero with **empty**
    /// stdout. A failure splits the batch and asks again: a single bad name in
    /// fifty costs about a dozen calls, and a good batch is still one call.
    func descriptions(names: [String], isCask: Bool,
                      stillWanted: () -> Bool = { true }) -> [String: String] {
        guard let brew = locator.brewPath(), !names.isEmpty else { return [:] }
        // `["desc", kind, "--"]` ahead of the names count against the limit.
        let perCall = HelmProcess.maxArguments - 3
        // Named while it runs, like the two list queries: a bad name in a
        // batch turns into a dozen calls.
        let found = HelmActivity.phase("homebrew.descriptions") { () -> [String: String] in
            var found: [String: String] = [:]
            for start in stride(from: 0, to: names.count, by: perCall) {
                if start > 0, !stillWanted() {
                    // Counts, never names; not brew's doing.
                    HelmLog.shared.info(Self.moduleID,
                                        "descriptions: \(names.count - start) names left undescribed "
                                        + "— no longer wanted")
                    break
                }
                let batch = Array(names[start..<min(start + perCall, names.count)])
                // Bounded per batch (`DescriptionBudget`): a batch refused
                // wholesale bisects to a leaf per name.
                let budget = DescriptionBudget(forBatchOf: batch.count)
                found.merge(describe(batch, isCask: isCask, brew: brew, budget: budget)) { a, _ in a }
                if budget.exhausted {
                    // Counts, never names.
                    HelmLog.shared.warn(Self.moduleID,
                                        "descriptions: brew refused \(batch.count) names wholesale "
                                        + "— gave up after \(budget.allowance) calls")
                }
                if budget.exhausted || budget.timedOut {
                    // The timeout line came from `timedOut(_:query:)`. Counts, never names.
                    let left = names.count - (start + batch.count)
                    if left > 0 {
                        HelmLog.shared.warn(Self.moduleID,
                                            "descriptions: \(left) names left undescribed "
                                            + "— the batch before them showed brew will not answer")
                    }
                    break
                }
            }
            return found
        }
        HelmLog.shared.memory("homebrew.descriptions")
        return found
    }

    private func describe(_ names: [String], isCask: Bool, brew: String,
                          budget: DescriptionBudget) -> [String: String] {
        guard budget.spend() else { return [:] }
        let result = runner.run(brew, ["desc", isCask ? "--cask" : "--formula", "--"] + names,
                                env: Self.queryEnvironment)
        if result.status == 0 { return BrewDescParser.parse(result.stdout) }
        // A timeout, never split: each half would hang for the same full
        // deadline, so a fifty-name batch would park the queue for hours.
        // Descriptions are a nicety; the rows draw without them.
        guard completed(result, query: "descriptions") != nil else {
            budget.noteTimeout()
            return [:]
        }
        // One name and it still failed: that is the name brew cannot resolve.
        // Nothing to say about it, and nothing it should cost the others.
        guard names.count > 1 else { return [:] }
        let middle = names.count / 2
        return describe(Array(names[..<middle]), isCask: isCask, brew: brew, budget: budget)
            .merging(describe(Array(names[middle...]), isCask: isCask, brew: brew,
                              budget: budget)) { a, _ in a }
    }

    func search(_ query: String) -> [SearchHit]? {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        guard let brew = locator.brewPath() else { return nil }
        let hits = HelmActivity.phase("homebrew.search") { () -> [SearchHit]? in
            // One call per kind: brew does not label a flat result list, and
            // the kind decides `brew install` or `brew install --cask`. Ids are
            // namespaced f:/c:, so a name that is both stays two rows.
            guard let formulae = completed(runner.run(brew, ["search", "--formula", "--", query], env: [:]),
                                           query: "search formulae"),
                  let casks = completed(runner.run(brew, ["search", "--cask", "--", query], env: [:]),
                                        query: "search casks")
            else { return nil }
            return BrewSearchParser.parse(formulae, isCask: false)
                 + BrewSearchParser.parse(casks, isCask: true)
        }
        // **After the ranking**, hence the `defer`: the first `readings()` is
        // the largest allocation a search makes (`FilePopularityStore.stored`),
        // and read before it the next search would be blamed for it
        // (ARCHITECTURE.md § The memory trail).
        defer { HelmLog.shared.memory("homebrew.search") }
        // Behind the guard: a search brew refused has nothing to rank, and
        // there is no reason for it to pay for a reading.
        guard let hits else { return nil }
        // brew answers alphabetically, which buries the obvious one. One ask,
        // because both lists are ranked from this one press and a refresh may
        // be landing while it happens.
        let counts = popularity.readings()
        return SearchRanking.rank(hits, query: query,
                                  formulae: counts.formulae,
                                  casks: counts.casks)
    }

    /// Which installed packages still need `name`.
    ///
    /// `brew uninstall` is an irreversible deletion, and the dialog says what
    /// it takes with it: removing `openssl@3` can break several formulae.
    ///
    /// Casks are answered without running anything: `brew uses` takes a formula,
    /// and handed a cask name it exits 0 with a warning on stderr the runner
    /// drops.
    ///
    /// **An empty list is not the same sentence as "nothing needs it".** An
    /// unresolvable *formula* name (from a tap since removed) also exits 0 with
    /// empty stdout. So the empty branch means "brew named nobody", which
    /// covers "brew could not look"; nothing downstream may turn it into a
    /// reassurance.
    ///
    /// nil when brew refused to answer, and when there is no brew to ask
    /// (`FSBrewLocator` re-reads at every call, so it can go while the dialog is
    /// open): the dialog must not promise "nothing depends on this" on a query
    /// that never ran.
    ///
    /// **No scoped phase, on purpose**: one `brew uses` over one name is not
    /// bulk work.
    func dependents(name: String, isCask: Bool) -> [String]? {
        // Known rather than measured, which is why this one stays `[]`.
        guard !isCask else { return [] }
        guard let brew = locator.brewPath() else {
            // Said out loud for the reason `listInstalled` says it: silence
            // here reads downstream as a machine with nothing on it.
            HelmLog.shared.warn(Self.moduleID, "brew is not installed — cannot ask what depends on a package")
            return nil
        }
        // `--`: see the type's doc comment.
        let result = runner.run(brew, ["uses", "--installed", "--", name],
                                env: Self.queryEnvironment)
        guard let out = answered(result, query: "dependents") else { return nil }
        return BrewUsesParser.parse(out)
    }

    /// What `brew info --json=v2` knows about one package — its description,
    /// homepage, licence, deprecation, whether it is installed and by whom.
    /// Asked once, when the person opens a package's detail, and never
    /// cached: the answer is about a Cellar and a catalogue that both change
    /// under the app.
    ///
    /// `runData`, for the reason `outdated` uses it.
    ///
    /// nil when brew refused to answer, when there is no brew to ask, and
    /// when the document itself is not one `BrewInfoParser` recognises — a
    /// shape this build cannot read is not the same sentence as "brew has
    /// nothing to say about this package".
    func info(name: String, isCask: Bool) -> PackageInfo? {
        guard let brew = locator.brewPath() else {
            HelmLog.shared.warn(Self.moduleID, "brew is not installed — cannot ask about a package")
            return nil
        }
        // `--`: see the type's doc comment.
        let result = runner.runData(brew,
                                    ["info", "--json=v2", isCask ? "--cask" : "--formula", "--", name],
                                    env: Self.queryEnvironment)
        guard !refused(result.status, query: "info") else { return nil }
        guard let parsed = BrewInfoParser.parse(result.stdout, isCask: isCask) else {
            // **Not "keeping the last answer"**: `HomebrewViewModel.refillInfo`
            // clears `info` before every ask, so nothing is kept, and a line
            // naming the wrong outcome sends triage after an answer that does
            // not exist.
            HelmLog.shared.warn(Self.moduleID,
                                "info: brew answered a shape this build cannot read "
                                + "— nothing is drawn for this package")
            return nil
        }
        return parsed
    }

    /// How much disk one installed package occupies — walked, because nothing
    /// tells us.
    ///
    /// `brew info --json=v2` carries no size (`bottle.files.*.size` is null,
    /// `installed[]` has no size field), so the figure is a walk of the
    /// package's own Cellar directory: `PackageWeight`, off the cooperative
    /// pool at `measure(_:version:)`, the door that calls this.
    ///
    /// **Remembered per `name@version`, for this engine's life.** An upgrade
    /// replaces the keg, and the next ask carries the new version, so the old
    /// entry is missed rather than trusted. Every entry is dropped when any
    /// operation finishes (`forgetSizes`): `brew reinstall` and a doctor fix
    /// rewrite a keg without moving its version, and `upgrade all` moves
    /// packages this key knows nothing about.
    ///
    /// **nil is never remembered**: a refusal may be lifted and a keg may
    /// arrive, and a remembered nil would keep the row absent for good.
    func size(name: String, isCask: Bool, version: String) -> Int? {
        let key = BrewKey.of(name: name, isCask: isCask) + "@" + version
        lock.lock(); let remembered = sizes[key]; lock.unlock()
        if let remembered { return remembered }
        guard let measured = weight.bytes(ofPackage: name, isCask: isCask) else { return nil }
        lock.lock(); sizes[key] = measured; lock.unlock()
        return measured
    }

    /// Drops every remembered figure. Called from `concludeOp`, so it runs
    /// whatever the operation was and however it ended — a failed `brew
    /// upgrade` has already moved everything ahead of the package it failed on.
    private func forgetSizes() {
        lock.lock(); sizes.removeAll(); lock.unlock()
    }

    /// What `brew doctor` found, parsed from its diagnostics stream.
    ///
    /// **The exit status is not the gate here.** `brew doctor` exits non-zero
    /// whenever it has something to say, so `refused` would report a clean
    /// machine exactly when it is not. `completed`, as for `search`: only the
    /// deadline disqualifies the reading.
    ///
    /// `runCapturingDiagnostics`, not `run`: `brew doctor` prints its whole
    /// answer on standard error, so `run` would answer nil on every call.
    ///
    /// The gate that matters is `DoctorParser.parse`: nil for empty input, an
    /// empty array for real output naming no issue, **and that only with exit
    /// 0.** `cmd/doctor.rb` exits 1 both on a finding and when it fails on its
    /// own account (`ofail`), so exit 1 with no finding parsed is nil (the
    /// page's «Homebrew did not answer»), never a clean Mac.
    ///
    /// **No fix is filled in here, and this query reads nothing but `brew
    /// doctor`.** A candidate needs an installed list, a second reading on
    /// plain `run`, and `ADoctorReadingIsNotGatedOnExitStatusTests` keeps this
    /// query off `run`. The candidate is built on the page's side and judged
    /// again by `runDoctorFix` against a list read at the press, which decides
    /// whether anything runs.
    func doctor() -> [DoctorIssue]? {
        guard let brew = locator.brewPath() else {
            HelmLog.shared.warn(Self.moduleID, "brew is not installed — cannot run doctor")
            return nil
        }
        let result = runner.runCapturingDiagnostics(brew, ["doctor"], env: Self.doctorEnvironment)
        guard let out = completed((result.status, result.output), query: "doctor") else { return nil }
        let issues = DoctorParser.parse(out)
        if issues?.isEmpty == true, result.status != 0 {
            HelmLog.shared.warn(Self.moduleID,
                                "doctor exited \(result.status) but no finding could be read "
                                + "from its answer — not read as a clean Mac")
            return nil
        }
        return issues
    }

    /// What `brew config` says about this Homebrew and this Mac — the version,
    /// the prefix, the checkout, the compiler, the Command Line Tools.
    ///
    /// **`run` and `answered`**: `brew config` answers on standard output with
    /// exit 0. `runCapturingDiagnostics` would fold a tap's deprecation warning
    /// into the document, where its colon parses as a key; a non-zero exit is
    /// brew declining, not part of the answer.
    ///
    /// nil when brew refused, when there is no brew to ask, and when the
    /// document holds no `key: value` line at all — `BrewConfigParser.parse`'s
    /// own doc comment says why the last of those is not an empty reading.
    func config() -> BrewConfig? {
        guard let brew = locator.brewPath() else {
            HelmLog.shared.warn(Self.moduleID,
                                "brew is not installed — cannot read its configuration")
            return nil
        }
        let result = runner.run(brew, ["config"], env: Self.queryEnvironment)
        guard let out = answered(result, query: "config") else { return nil }
        guard let lines = BrewConfigParser.parse(out) else {
            // Named, as `info`'s nil is: an unreadable shape is not brew
            // having nothing to say.
            HelmLog.shared.warn(Self.moduleID,
                                "config: brew printed nothing this build reads as `key: value` "
                                + "— no configuration is drawn")
            return nil
        }
        return BrewConfig(lines: lines, text: out)
    }

    // MARK: - Long operations

    /// One phase for all the long operations, opened and closed by the busy
    /// gate (ARCHITECTURE.md § Operations). The balance rides the gate,
    /// whose release `OneOperationAtATimeTests` guards on every path. The label
    /// carries no package name.
    private static let operationPhase = "homebrew.operation"

    private func beginBusy(installingBrew: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if busy || off || !gate.take(self) { return false }
        busy = true
        stopRequested = false
        installing = installingBrew
        HelmActivity.begin(Self.operationPhase)
        return true
    }
    /// Names why `beginBusy` said no: a module that is off, or an operation
    /// that is running. Only the second is a line for the console.
    private func refuseLaunch(_ verb: String) {
        lock.lock(); let isOff = off; lock.unlock()
        if isOff {
            HelmLog.shared.warn(Self.moduleID, "\(verb) refused: the module is switched off")
            return
        }
        HelmLog.shared.warn(Self.moduleID, "\(verb) refused: another operation is running")
        news.say(.busy, slot: HomebrewSlot.opLog.rawValue)
    }
    private func endBusy() {
        lock.lock(); busy = false; installing = false; current = nil; lock.unlock()
        gate.release(self)
        HelmActivity.end(Self.operationPhase)
        HelmLog.shared.memory("homebrew.operation")
    }

    /// Whether the exit that just landed was asked for. Read at the exit, not
    /// when Stop is pressed: the answer belongs to the operation that ends.
    private var wasStopped: Bool { lock.withLock { stopRequested } }

    /// The one way every long operation ends, whatever started it: the stop
    /// answer is read while it is still this operation's, the marker cleared
    /// before the gate opens (or the next operation's marker could lose to
    /// this one's clear), the gate opened, the state event sent. Returns
    /// whether the end was asked for, so the caller can word its log line.
    ///
    /// `code` is nil when no child ever ran (a stop before the launch): an
    /// invented exit code would name nothing on the page.
    ///
    /// `reason` names a failure the engine knows more about than an exit code;
    /// it is dropped for a success, and **a Stop the person pressed wins over
    /// it** — a dialog answered no after Stop was pressed is the person's Stop.
    @discardableResult
    private func concludeOp(code: Int32?, label: String, reason: OpFailureReason? = nil) -> Bool {
        let stopped = wasStopped
        marker.clear()
        endBusy()
        // Whatever it was, it may have rewritten a keg: the figures are a
        // reading of a Cellar that has just moved.
        forgetSizes()
        // nil is "no child ever ran", which is not a success.
        let phase: OpPhase = code == 0 ? .done : .failed
        emitState(OpState(phase: phase, label: label, exitCode: code.map(Int.init),
                          reason: phase == .failed ? (stopped ? .stopped : reason) : nil))
        return stopped
    }

    /// Ends the running long operation. With a child, SIGTERM through its
    /// handle (`StopReach` says how far it goes); the exit arrives the way every
    /// exit does — EOF, then `onExit` — so the busy gate and the state event
    /// follow the one path they already have. **While the install is only
    /// waiting for Apple's tools there is no child and no exit**: Stop takes the
    /// wait's token and concludes the operation itself, below.
    ///
    /// **The press is recorded even when there is nothing to terminate yet.**
    /// `current` is set only after the launch, while the page already shows a
    /// live Stop; the launch reads the flag (`stoppedBeforeLaunch`).
    func stop() {
        lock.lock()
        guard busy else { lock.unlock(); return }
        stopRequested = true
        let handle = current
        // Taking the wait's token ends the wait; its taker ends the operation.
        let wait = toolsWait
        toolsWait = nil
        lock.unlock()
        HelmLog.shared.info(Self.moduleID, "stop requested")
        endWaitOrTerminate(wait: wait, handle: handle, waitLine: "\(Self.installBrewLabel) stopped waiting")
    }

    /// Whether a Stop — or the module's switch-off, which sets the same flag
    /// (`endTheOperation`) — arrived before this operation had a child, in which
    /// case the operation ends here and the launch must not happen.
    ///
    /// For a package operation that window is a spawn. For `installBrew` there
    /// are several: the request for Apple's tools, each reading of them, and
    /// above all **the administrator password dialog**, which blocks this
    /// thread for as long as a person takes to find their password.
    ///
    /// No `onExit` is coming, so the operation is concluded here, or the gate
    /// stays shut for the life of the app.
    private func stoppedBeforeLaunch(label: String) -> Bool {
        guard wasStopped else { return false }
        HelmLog.shared.info(Self.moduleID, "stopped before the child was started")
        concludeOp(code: nil, label: label)
        return true
    }

    private func emitLog(_ line: String) {
        news.say(.line(line), slot: HomebrewSlot.opLog.rawValue)
    }
    private func emitState(_ s: OpState) {
        news.say(.state(s), slot: HomebrewSlot.opState.rawValue)
    }

    /// `verb` is what happened; `subject` is the package it happened to, kept
    /// apart from the label so the log can carry one and redact the other.
    /// Every operation that changes the machine comes through here and leaves
    /// a line in the log.
    private func runOp(verb: String, subject: String? = nil,
                       label: String, launch: String, args: [String],
                       env: [String: String] = HomebrewEngine.operationEnvironment) {
        guard beginBusy() else { refuseLaunch(verb); return }
        let what = subject.map { "\(verb) \(Redact.pkg($0))" } ?? verb
        HelmLog.shared.info(Self.moduleID, "\(what) started")
        emitState(OpState(phase: .running, label: label))
        startChild(label: label, launch: launch, args: args, env: env, reach: .process) { code in
            let stopped = self.concludeOp(code: code, label: label)
            self.logEnd(what, code: code, stopped: stopped)
        }
    }

    /// The three words a child's end is logged in, for every operation that
    /// runs one: `runOp` and `installBrew` say the same thing the same way.
    private func logEnd(_ what: String, code: Int32, stopped: Bool) {
        if code == 0 {
            HelmLog.shared.info(Self.moduleID, "\(what) done")
        } else if stopped {
            HelmLog.shared.info(Self.moduleID, "\(what) stopped on request, exit \(code)")
        } else {
            HelmLog.shared.warn(Self.moduleID, "\(what) failed, exit \(code)")
        }
    }

    /// **The one place this module starts a child**, so the three things that
    /// belong to every launch cannot be remembered at one site and forgotten at
    /// the next: the Stop that arrived before the child existed, the marker
    /// that reports a quit mid-operation, and the handle joining the operation
    /// it belongs to. The two callers differ in what they say at the exit and
    /// in how far a Stop reaches: `runOp` names `.process`, the installer's
    /// wrapper names `.wholeGroup`.
    private func startChild(label: String, launch: String, args: [String],
                            env: [String: String], reach: StopReach,
                            onExit: @escaping @Sendable (Int32) -> Void) {
        guard !stoppedBeforeLaunch(label: label) else { return }
        // The child survives a quit; whatever is still written at the next
        // launch is the report (`AQuitMidOperationIsReportedTests`).
        marker.write(label)
        adopt(runner.stream(launch, args, env: env, reach: reach,
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
        // The other half of `stoppedBeforeLaunch`'s window: a press after that
        // check found `current` nil and terminated nothing.
        if stopped { handle.terminate() }
    }

    /// brew can vanish between `status()` and the press: Homebrew's own
    /// uninstaller in a terminal, with Helm's window open on the old list. A
    /// refusal is an outcome and it is named, never a silent button.
    private func brewOrRefuse(verb: String, label: String) -> String? {
        if let brew = locator.brewPath() { return brew }
        HelmLog.shared.warn(Self.moduleID, "\(verb) refused: brew is no longer installed")
        refuseInsideGate(verb: verb, label: label, reason: .brewMissing)
        return nil
    }

    /// A refused press writes `.failed` only while it holds the gate. Outside
    /// it, the state belongs to the operation that does hold it, and a second
    /// press would overwrite its `.running`: Stop gone, gates open, a child
    /// still alive. The gate is released after the emit, so no press slips in
    /// between. A press that cannot take the gate says so in the console.
    private func refuseInsideGate(verb: String, label: String, reason: OpFailureReason) {
        guard beginBusy() else { refuseLaunch(verb); return }
        defer { endBusy() }
        emitState(OpState(phase: .failed, label: label, reason: reason))
    }

    /// The refusal and the run both name the operation's label, so it is said
    /// once here by each caller.
    private func runPackageOp(verb: String, subject: String? = nil, label: String, args: [String]) {
        guard let brew = brewOrRefuse(verb: verb, label: label) else { return }
        runOp(verb: verb, subject: subject, label: label, launch: brew, args: args)
    }

    func install(name: String, isCask: Bool) {
        runPackageOp(verb: "install", subject: name, label: "install \(name)", args: isCask ? ["install", "--cask", "--", name] : ["install", "--", name])
    }
    func uninstall(name: String, isCask: Bool) {
        runPackageOp(verb: "uninstall", subject: name, label: "uninstall \(name)", args: isCask ? ["uninstall", "--cask", "--", name] : ["uninstall", "--", name])
    }
    func upgrade(name: String) {
        runPackageOp(verb: "upgrade", subject: name, label: "upgrade \(name)", args: ["upgrade", "--", name])
    }
    func upgradeAll() {
        runPackageOp(verb: "upgrade all", label: "upgrade all", args: ["upgrade"])
    }

    /// Runs one command `brew doctor`'s answer was read as proposing — **after
    /// judging it again here**, and through the same `runOp` every other
    /// operation goes through.
    ///
    /// **The UI's judgement decides what to draw; this one decides what to
    /// run.** The page judged against the list it held when the issue was
    /// drawn, which may be a day old; the package may be gone since. So the
    /// list is read **now**, one line before the act, and `DoctorFix.judge` is
    /// asked again; nothing arriving through the door is trusted to have been
    /// judged, including an argv no page ever drew.
    ///
    /// A Cellar that could not be read is not a Cellar the name is in: a nil
    /// `listInstalled` refuses the run by reading, not by luck.
    ///
    /// Every operand goes behind `--` (the type's doc comment).
    func runDoctorFix(_ argv: [String]) {
        // The command without `brew`, the shape the other labels have and the
        // one `DoctorFix` judges.
        let label = argv.joined(separator: " ")
        guard let brew = brewOrRefuse(verb: "doctor fix", label: label) else { return }
        guard let names = listInstalled()?.map(\.name),
              DoctorFix.judge(argv, installed: names).kind == .runnable else {
            // Named, never silent; the argv is redacted like every package name.
            HelmLog.shared.warn(Self.moduleID,
                                "doctor fix refused: \(Redact.pkg(label)) is not runnable "
                                + "against the Cellar as it is now")
            refuseInsideGate(verb: "doctor fix", label: label, reason: .fixRefused)
            return
        }
        let operands = Array(argv.dropFirst())
        runOp(verb: "doctor fix", subject: operands.first, label: label, launch: brew,
              args: [argv[0], "--"] + operands)
    }

    /// Install Homebrew itself, in three parts that only ever run in this order:
    /// Apple's Command Line Tools (asked for and waited on, when they are not
    /// there), then the one root step (`/opt/homebrew`, one native password
    /// dialog), then Homebrew's own `install.sh` non-interactively.
    ///
    /// **Why the tools come first.** `install.sh` installs them itself only when
    /// `sudo` can ask on a terminal, and Helm runs it with neither. The password
    /// is asked *after* the tools: someone who cancels Apple's download has
    /// spent no password, and `/opt/homebrew` is not made for nothing.
    ///
    /// Arrives through `perform(_:)`, on the concurrent global queue: the
    /// dialog blocks this thread.
    func installBrew() {
        // One label, read by every way this operation can end — including the
        // marker, which is compared against nothing but itself.
        let label = Self.installBrewLabel
        guard beginBusy(installingBrew: true) else { refuseLaunch(label); return }
        HelmLog.shared.info(Self.moduleID, "\(label) started")
        emitState(OpState(phase: .running, label: label))
        // `user` is NSUserName(), which on a managed Mac is whatever the
        // directory says; this string is evaluated by a root shell. Single
        // quotes stop expansion, and the name is checked before it gets there.
        guard AccountName.isPlausible(user) else {
            HelmLog.shared.warn(Self.moduleID, "\(label) failed: unsupported account name")
            concludeOp(code: 1, label: label, reason: .unsupportedAccount)
            return
        }
        if toolsPresent() { prepareAndRun(label); return }
        // Read after each look that can take a while, and again right before the
        // request: a Stop or a switch-off that landed in `xcode-select -p` or in
        // the hop to the main thread must not be answered with Apple's window.
        guard !stoppedBeforeLaunch(label: label) else { return }
        // Apple's window may already be open from an earlier press; a second
        // request would ask for a second window.
        if !tools.installerIsRunning() {
            guard !stoppedBeforeLaunch(label: label) else { return }
            switch tools.requestInstall() {
            case .filed:
                break
            case .refused(let status):
                HelmLog.shared.warn(Self.moduleID, "xcode-select --install refused, exit \(status)")
                proceedOrRefuseTools(label)
                return
            case .timedOut:
                HelmLog.shared.warn(Self.moduleID, "xcode-select --install timed out")
                proceedOrRefuseTools(label)
                return
            }
        }
        HelmLog.shared.info(Self.moduleID, "\(label) waiting for the Command Line Tools")
        emitState(OpState(phase: .running, label: label, waiting: .commandLineTools))
        lock.lock()
        // A Stop that landed while the request was being filed had no wait to
        // take and no child to terminate; the flag is what it left.
        guard busy, !stopRequested else { lock.unlock(); _ = stoppedBeforeLaunch(label: label); return }
        waitGeneration += 1
        let generation = waitGeneration
        waitReading = CommandLineTools.Wait()
        toolsWait = ticker.schedule(after: Self.toolsTick) { [weak self] in
            self?.tick(label, generation: generation)
        }
        lock.unlock()
    }

    /// A refused or unanswered request is not yet a refusal to install: the
    /// tools may have arrived by another road in the meantime — a second
    /// window, a terminal.
    private func proceedOrRefuseTools(_ label: String) {
        if toolsPresent() { prepareAndRun(label); return }
        failNoTools(label)
    }

    private func failNoTools(_ label: String) {
        HelmLog.shared.warn(Self.moduleID,
                            "\(label) failed: the Command Line Tools were not installed")
        concludeOp(code: nil, label: label, reason: .toolsNotInstalled)
    }

    private func toolsPresent() -> Bool {
        CommandLineTools.present(isExecutable: { tools.isExecutable($0) },
                                 selected: { tools.selectedDeveloperDirectory() })
    }

    /// One look at whether Apple's tools are here, on the ticker's queue.
    ///
    /// **The tools port is not called under `lock`**: `installerIsRunning` hops
    /// to the main thread, which may be waiting for that lock. (`schedule` is
    /// called under it: it only queues the next tick.) The installer is read
    /// *before* `git`: the other way round, Apple's window could finish between
    /// the two looks and read as closed with no tools, a failure over a success.
    private func tick(_ label: String, generation: Int) {
        let running = tools.installerIsRunning()
        let present = tools.isExecutable(CommandLineTools.git)
        lock.lock()
        let reading = waitReading
        lock.unlock()
        let step = CommandLineTools.next(reading, toolsPresent: present, installerRunning: running)
        lock.lock()
        // Stop, `deactivate()` or `deinit` got here first — or this tick belongs
        // to a wait that has been replaced.
        guard toolsWait != nil, waitGeneration == generation else { lock.unlock(); return }
        waitReading = step.wait
        if step.verdict == .keepWaiting {
            toolsWait = ticker.schedule(after: Self.toolsTick) { [weak self] in
                self?.tick(label, generation: generation)
            }
            lock.unlock()
            if step.sayNeverSeen {
                HelmLog.shared.warn(Self.moduleID,
                                    "Apple's installer was never seen running — waiting on the tools alone")
            }
            return
        }
        toolsWait = nil
        lock.unlock()
        switch step.verdict {
        case .keepWaiting:
            return
        case .toolsArrived:
            toolsArrived(label)
        case .closedWithoutTools:
            // The tick looks only at the fixed `git`, to spend no process per
            // tick; "missing" is said only on the press's own reading
            // (`xcode-select -p` too).
            if toolsPresent() {
                toolsArrived(label)
            } else {
                failNoTools(label)
            }
        }
    }

    private func toolsArrived(_ label: String) {
        HelmLog.shared.info(Self.moduleID, "\(label) the Command Line Tools arrived")
        emitState(OpState(phase: .running, label: label))
        prepareAndRun(label)
    }

    /// The root step and the installer, once the tools are on the Mac. Neither the
    /// tools port nor `runAdmin` is called under `lock` (`tick` says why for the
    /// tools; the dialog parks this thread for as long as a person takes).
    private func prepareAndRun(_ label: String) {
        // No dialog after a Stop that landed since the wait ended.
        guard !stoppedBeforeLaunch(label: label) else { return }
        // Read again one line before the dialog: no password is spent on a
        // `mkdir` for an installer that will stop at its `git` check.
        guard toolsPresent() else {
            failNoTools(label)
            return
        }
        // Read again after the reading: with Xcode's tools it is a process with
        // a ten-second deadline, and a Stop inside it is read nowhere else.
        guard !stoppedBeforeLaunch(label: label) else { return }
        // Absolute paths: a root shell resolves this with our `PATH`, which any
        // process running as the user can rewrite (`launchctl setenv PATH …`).
        // See `SudoersRule.installCommand`.
        let prep = "/bin/mkdir -p /opt/homebrew && /usr/sbin/chown -R '\(user)':admin /opt/homebrew"
        switch privileged.runAdmin(prep) {
        case .done:
            break
        case .declined:
            // The person's answer, not a defect: info, not warn.
            HelmLog.shared.info(Self.moduleID, "\(label) administrator authorization declined")
            concludeOp(code: nil, label: label, reason: .authorizationDeclined)
            return
        case .failed(let status):
            HelmLog.shared.warn(Self.moduleID, "\(label) failed: /opt/homebrew was not prepared, exit \(status)")
            concludeOp(code: status, label: label, reason: .prefixNotPrepared)
            return
        }
        // Download, then run — not `eval "$(curl …)"`, where a failed download
        // evaluates the empty string, exits 0, and the module reports a
        // successful install of nothing.
        //
        // **`|| rc=$?`, not `; rc=$?`.** Under `set -e` a failing installer
        // would end the shell before the Stop note is read and `exit $rc` runs;
        // `||` keeps `set -e` from firing, so the installer's own code reaches
        // `concludeOp`. `rc=0` first, because `exit` on an unset `rc` answers
        // the status of whatever ran last.
        //
        // **Stop ends the installer and takes the script with it, at any moment
        // of the wrapper's life.** The wrapper is launched with `.wholeGroup`:
        // one TERM reaches its whole process group, the download or the
        // installer and whatever it started. So the wrapper starts nothing in
        // the background and has no job control: a `&` child read through `$!`
        // leaves a window where a TERM finds nothing to address, and `set -m`
        // prints `[1]+ Done …` into the console.
        //
        // What is left for the shell is the tail. A trap runs once the
        // foreground command has ended by the same TERM, so `exit 143` follows;
        // the `rm` sits in an EXIT trap set before the file exists, which also
        // covers a download that fails under `set -e`. **`mktemp` runs with TERM
        // ignored**, because its result is a name: killed after making the file
        // and before the assignment, it leaves a file nobody can name. The Stop
        // is noted by the first trap and read on the line after.
        //
        // **The cleanup ignores TERM.** The `rm` is in the group a Stop signals,
        // and a Stop signals more than once; `trap "" TERM` inside the trap is
        // inherited by the `rm`, so the installer does not stay in the
        // temporary folder.
        //
        // **A Stop that arrives after the installer has finished is not a Stop.**
        // The wrapper then ends with the installer's own status; 143 is kept
        // for a press that did stop something. An installer that answered 0 has
        // installed Homebrew, and the page must say so.
        let installer = "set -e; script=; stopped=; "
                      + "trap 'trap \"\" TERM; /bin/rm -f \"$script\"' EXIT; "
                      + "trap 'stopped=1' TERM; "
                      + "script=$(trap '' TERM; exec /usr/bin/mktemp); "
                      + "trap 'exit 143' TERM; [ -z \"$stopped\" ] || exit 143; "
                      + "/usr/bin/curl -fsSL \(Self.installerURL) -o \"$script\"; "
                      + "trap 'stopped=1' TERM; [ -z \"$stopped\" ] || exit 143; "
                      + "rc=0; /bin/bash \"$script\" || rc=$?; "
                      + "[ \"$rc\" -eq 0 ] || [ -z \"$stopped\" ] || exit 143; "
                      + "exit $rc"
        // A Stop pressed while the dialog was up is read in `startChild`.
        startChild(label: label, launch: "/bin/bash", args: ["-c", installer],
                   env: Self.installerEnvironment, reach: .wholeGroup) { code in
            let stopped = self.concludeOp(code: code, label: label,
                                          reason: code == 0 ? nil : .installerFailed)
            self.logEnd(label, code: code, stopped: stopped)
        }
    }

    // MARK: - The model's door

    /// The last line, the last state and where brew is, in the order the three kinds
    /// first appeared, then every line, state and brew after them in the order they
    /// were said.
    ///
    /// **Registered before this returns, in the one hold of the lock that replays
    /// what was last said** (`EngineNews.stream`), so no emit falls between the
    /// replay and the subscription. Synchronous, so the model takes it in its
    /// own `init`. Ending the iteration removes the subscriber. Unbounded on
    /// purpose: a dropped `.done` is a page that never leaves «running»; the
    /// console's bound is the model's.
    public func stream() -> AsyncStream<HomebrewNews> { news.stream() }

    public var subscriberCount: Int { news.subscriberCount }

    // The readings below hop off the cooperative pool: each sync method they
    // call blocks its thread on a child, a lock or a directory. A nil keeps its
    // one meaning: «the module could not answer», which a timed-out query is;
    // what the page does with it is the model's.

    public func readStatus() async -> BrewStatus { await offTheCooperativePool { self.status() } }
    public func readInstalled() async -> [BrewPackage]? { await offTheCooperativePool { self.listInstalled() } }
    public func readOutdated() async -> [OutdatedPackage]? { await offTheCooperativePool { self.outdated() } }
    /// `stillWanted` is read on the pool thread, so it must be callable from
    /// any thread: Swift task cancellation does not cross `offTheCooperativePool`,
    /// and the caller's own state is not ours to read.
    public func readDescriptions(of names: [String], isCask: Bool,
                                 stillWanted: @escaping @Sendable () -> Bool) async -> [String: String] {
        await offTheCooperativePool { self.descriptions(names: names, isCask: isCask, stillWanted: stillWanted) }
    }
    public func find(_ query: String) async -> [SearchHit]? { await offTheCooperativePool { self.search(query) } }
    /// Which installed packages still need a given one. Never cached: the
    /// Cellar changes under the app.
    public func readDependents(of package: PackageRef) async -> [String]? {
        await offTheCooperativePool { self.dependents(name: package.name, isCask: package.isCask) }
    }
    /// What `brew info --json=v2` knows about one package. Never cached.
    public func readInfo(about package: PackageRef) async -> PackageInfo? {
        await offTheCooperativePool { self.info(name: package.name, isCask: package.isCask) }
    }
    /// How much disk one installed package occupies, with the version the figure
    /// is remembered against.
    ///
    /// **The answer is remembered against the version it was measured for**
    /// (`size(name:isCask:version:)`). The page passes `PackageInfo`'s
    /// `installedVersion`; never empty, since a package with no installed
    /// version has no keg to walk.
    public func measure(_ package: PackageRef, version: String) async -> Int? {
        await offTheCooperativePool {
            self.size(name: package.name, isCask: package.isCask, version: version)
        }
    }
    public func readDoctor() async -> [DoctorIssue]? { await offTheCooperativePool { self.doctor() } }
    public func readConfig() async -> BrewConfig? { await offTheCooperativePool { self.config() } }

    /// Every press, and returns at once; what happens arrives on `stream()`.
    ///
    /// **On the concurrent global queue, not the cooperative pool and not a
    /// serial queue**, and the hop is inside so no caller can forget it
    /// (ARCHITECTURE.md § The model). Stop must overtake the
    /// password dialog (`AStopBeforeTheChildExistsTests`); a pool thread parked
    /// there is one the app's `async` work needs.
    public func perform(_ act: HomebrewAct) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            switch act {
            case .install(let package): install(name: package.name, isCask: package.isCask)
            case .uninstall(let package): uninstall(name: package.name, isCask: package.isCask)
            case .upgrade(let name): upgrade(name: name)
            case .upgradeAll: upgradeAll()
            case .doctorFix(let argv): runDoctorFix(argv)
            case .installBrew: installBrew()
            case .stop: stop()
            }
        }
    }
}
