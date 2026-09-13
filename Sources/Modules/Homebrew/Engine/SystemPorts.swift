import Foundation
import HelmRuntime

// MARK: - Locator

public struct FSBrewLocator: BrewLocator {
    public init() {}
    public func brewPath() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }
}

// MARK: - Process runner

/// Splits streamed bytes into whole lines, thread-safely.
///
/// **Bytes, not text.** This used to decode each chunk with
/// `String(data:encoding:.utf8)` and `return` on nil. `availableData` splits on
/// byte boundaries, not character boundaries, so a multi-byte character
/// straddling two reads leaves the first chunk ending mid-sequence — and the
/// whole chunk went, not the one character. Everything ahead of the split was
/// plain ASCII and perfectly decodable, and it went too. Reachable with any
/// non-ASCII output past one read, which `brew` produces on every successful
/// install.
///
/// So the split happens on the newline *byte* and only complete lines are
/// decoded; an unfinished character simply stays in the buffer with the rest of
/// its unfinished line. `String(decoding:as:)` rather than the failable
/// initialiser, because bytes that are not UTF-8 at all are still somebody's
/// log: they come through as replacement characters instead of taking the lines
/// around them with them.
final class LineBuffer: @unchecked Sendable {
    private static let newline: UInt8 = 0x0A
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var partial = Data()
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        lock.lock()
        partial.append(data)
        var complete: [Data] = []
        while let newline = partial.firstIndex(of: Self.newline) {
            complete.append(partial[partial.startIndex..<newline])
            partial = partial[partial.index(after: newline)...]
        }
        // Re-base: a slice keeps its parent's indices, so without this the
        // buffer's start walks forward for the life of the stream.
        partial = Data(partial)
        lock.unlock()
        for line in complete { onLine(String(decoding: line, as: UTF8.self)) }
    }

    /// The last line of a tool that did not end with a newline is still a line.
    func flush() {
        lock.lock(); let rest = partial; partial = Data(); lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self)) }
    }
}

/// Carries the exit status from the termination callback to whoever reports it.
private final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int32 = -1
    func set(_ v: Int32) { lock.lock(); value = v; lock.unlock() }
    var status: Int32 { lock.lock(); defer { lock.unlock() }; return value }
}

public struct ShellProcessRunner: ProcessRunner {
    /// How long a *query* may go unanswered before it is a hang, not a wait.
    ///
    /// `run` serves only the read-only queries (list, outdated, desc, search);
    /// the long operations stream and are stopped by hand, never by a clock.
    /// Measured on the owner's log before choosing: warm queries answer in
    /// 0.3–0.6 s, and a cold `brew outdated` — which goes to the network —
    /// took 7.4 s (helm.log, 2026-08-15 16:09:35→42). Ninety seconds clears the
    /// slowest measured query more than tenfold and still ends a hung brew —
    /// another brew's lock never released, a stalled network read — inside the
    /// same sitting, with the Refresh button live again.
    public static let defaultQueryTimeout: TimeInterval = 90

    private let queryTimeout: TimeInterval

    public init(queryTimeout: TimeInterval = ShellProcessRunner.defaultQueryTimeout) {
        self.queryTimeout = queryTimeout
    }

    private func environment(_ extra: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        for (k, v) in extra { e[k] = v }
        return e
    }

    /// The port stays — it is what makes the engine testable — but the body is
    /// `HelmProcess`, like every other module's.
    ///
    /// Two things were different here, and both were wrong in the same
    /// direction. This copy merged stderr into stdout, and all four of its
    /// callers parse what they get: `BrewListParser` takes the first word of
    /// every line as a package name, so a version-support warning from `brew`
    /// became a row with an Uninstall button beside it. And it waited with
    /// `waitUntilExit`, the 50 ms run-loop poll `HelmProcess` was written to
    /// remove, paid twice per query.
    ///
    /// `stream` keeps stderr: a console should show what the tool says. It is
    /// output that gets parsed that must not carry diagnostics.
    public func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) {
        let result = HelmProcess.run(launchPath, args, env: environment(env),
                                     timeout: queryTimeout)
        return (result.status, result.output)
    }

    /// The bytes without the String round-trip — `HelmProcess.runData`'s doc
    /// comment carries the measured difference.
    public func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data) {
        let r = HelmProcess.runData(launchPath, args, env: environment(env), timeout: queryTimeout)
        return (r.status, r.output)
    }

    /// **The exit is reported at end of pipe, not at end of process.** These are
    /// two different moments and the process is the earlier one: the child
    /// exits, the termination callback fires, and whatever it had written that
    /// the reader had not picked up yet is still sitting in the pipe. Clearing
    /// the readability handler there threw that away — so the tail of a
    /// `brew install`, which is the part that says where it put things, was
    /// missing from the console whenever the reader ran behind the writer. It
    /// always does: `onLine` hops to the main actor and redraws a console.
    /// Measured at 5000 lines with a 2 ms consumer, five runs out of five lost
    /// between 396 and 4200 of them.
    ///
    /// Reading to the end first is the same order `HelmProcess.run` uses, and
    /// for the same reason. EOF arrives only when every writer has closed, so
    /// by then the child has finished; the wait below is immediate rather than
    /// a poll.
    @discardableResult
    public func stream(_ launchPath: String, _ args: [String], env: [String: String],
                       onLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.environment = environment(env)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let buffer = LineBuffer(onLine: onLine)
        let status = StatusBox()
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { proc in
            status.set(proc.terminationStatus)
            exited.signal()
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else {
                // Empty means end of file: everything written has been read.
                handle.readabilityHandler = nil
                buffer.flush()
                exited.wait()
                onExit(status.status)
                return
            }
            buffer.feed(d)
        }
        // `HelmProcess.start`, never `try p.run()`. The five operations that
        // reach this line are the ones that change the machine, and every one
        // of them carries a package name parsed out of brew's own stdout: a
        // launch `NSTask` *raises* on takes the whole app down, because the
        // exception has no Swift frame to land on. `run` and `runData` moved
        // behind that door when it was written and this one did not.
        guard HelmProcess.start(p, path: launchPath) else {
            // No child, so no EOF is ever coming — the page would keep its
            // spinner forever waiting for one.
            pipe.fileHandleForReading.readabilityHandler = nil
            onExit(-1)
            return NoProcess()
        }
        // The handle retains the `Process`: it used to be a local nobody kept,
        // leaving the running child with no way to be addressed again.
        return LiveProcess(p)
    }
}

/// The real handle: SIGTERM, so a brew mid-operation gets to clean up after
/// itself — never KILL, which is how half-written Cellar state is made. The
/// exit still arrives through the pipe's EOF, the same way an honest exit does.
private struct LiveProcess: RunningProcess, @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

// MARK: - Privileged runner

public struct OSAPrivilegedRunner: PrivilegedRunner {
    public init() {}
    public func runAdmin(_ script: String) -> Bool {
        // `AppleScript` in HelmRuntime — the escaping was written out here and
        // in `SudoersRule`, and Keep Awake's copy carried the comment saying so.
        let osa = AppleScript.administratorShellScript(script)
        return HelmProcess.run("/usr/bin/osascript", ["-e", osa]).status == 0
    }
}

// MARK: - Operation marker

/// The marker as a file, so it survives the quit it exists to report.
///
/// The label an operation writes is a brew command with a package name in it —
/// a fact about the person's machine, so the file goes through `PrivateFile`
/// like every other file that names somebody's things. It lives in Helm's own
/// Application Support folder, which `HelmSupport.directory` already redirects
/// into scratch under a test runner.
public struct FileOpMarker: OpMarker {
    private let url: URL

    public init(directory: URL = HelmSupport.directory) {
        url = directory.appendingPathComponent("homebrew-operation")
    }

    /// A marker that does not land is the calm the protocol above exists to
    /// prevent: brew goes on changing the Cellar after Helm quits, and the next
    /// launch has nothing to report it with. Nothing can be done about it here —
    /// the write is the whole mechanism — so it is said, and the label is not,
    /// because the label is a brew command with a package name in it.
    public func write(_ label: String) {
        if !PrivateFile.writeMakingTheFolder(Data(label.utf8), at: url) {
            HelmLog.shared.warn(HomebrewEngine.moduleID,
                                "the running operation could not be written down — a quit before "
                                + "it finishes will not be reported at the next launch")
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    public func take() -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        clear()
        return String(bytes: data, encoding: .utf8)
    }
}

// MARK: - Install counts

/// A tally two threads may touch. A lock rather than an actor, because what
/// increments it is a `@Sendable` closure with nowhere to await.
final class AskCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func record() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Homebrew's published install counts, cached in Helm's own folder.
///
/// Two whole public documents, fetched at most once a day. Nothing this ask
/// puts on the wire names this Mac, this person, or what was searched — no
/// query, no package name, nothing about what is installed here, and every
/// header that could carry such a thing is pinned to a fixed value on the
/// session (see `session`, which carries the measurement). The ETag is stored
/// beside each file, so a daily ask can be a 304 with no body at all.
///
/// **Can be, not is.** Measured against the live endpoint on 2026-09-14: GitHub
/// Pages answers with `W/"<mtime>-<size>"` and its nodes hold the same document
/// with mtimes a second apart, so the same stored tag earned a 304 from one node
/// and a 200 from the next, about half the time each. That costs nothing but the
/// document — a 200 rewrites the same bytes and the newer tag — and the gate
/// above it is what keeps the ask to one a day either way.
///
/// **Everything here fails towards today's behaviour.** An unreadable file, a
/// refused fetch, a document this build cannot parse: each leaves the readings
/// as they were and search goes on ordering results the way it does now. The
/// one way to get that wrong is to record a refusal as an *empty* reading —
/// `[:]` is a well-formed answer meaning nobody installs anything — which is
/// why `PopularityRefresh.answer` names its refusals rather than handing back
/// an optional two things could mean.
///
/// **And a refusal must not stamp the clock.** The clock is the cached file's
/// own modification date, so only a write sets it; the single exception is a
/// 304, which is an answer — what is stored *is* current — and is worth a day.
/// `refreshIfDue` is `async` and cannot throw, so a cancellation inside it is
/// silent by construction, and `deactivate()` runs on every route out of the
/// app including `applicationWillTerminate`: being cancelled mid-fetch is
/// ordinary here, and it must read as "ask again next launch".
public final class FilePopularityStore: PopularityReading, @unchecked Sendable {

    /// What a fetch is, as a function — the one seam in this type, so that
    /// everything it does with an answer can be exercised without a network.
    /// It stands for `URLSession.data(for:)` and for nothing else: the clock,
    /// the files and the readings are the real ones in every test.
    typealias Transfer = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    struct Endpoint: Sendable {
        let url: URL
        let file: String
        /// Which half of a reading this document is.
        ///
        /// The ETag gate is the only thing that asks, and it asks through
        /// `readings()` — so the one parse it costs is the parse the rest of
        /// the day would have paid anyway, rather than a second one of its own.
        let half: @Sendable (PopularityReadings) -> InstallCounts
    }

    static let formulae = Endpoint(
        url: URL(string: "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json")!,
        file: "homebrew-installs-formulae.json",
        half: { $0.formulae })
    static let casks = Endpoint(
        url: URL(string: "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json")!,
        file: "homebrew-installs-casks.json",
        half: { $0.casks })

    /// How long a transfer may go without a byte arriving. A read-only query
    /// gets a deadline — nothing waits on this one, since it is a background
    /// refresh of a figure that only reorders a list, but an unanswered read
    /// holds a task for as long as the wire lets it.
    private static let idleDeadline: TimeInterval = 30

    /// How long the whole transfer may take, whatever arrives meanwhile.
    ///
    /// **`idleDeadline` alone is not a bound.** It restarts on every packet, so
    /// an endpoint trickling a byte at a time never trips it — and the ceiling
    /// in `PopularityRefresh` cannot help either, because it is consulted once
    /// `URLSession` has already buffered the body. This is the one thing that
    /// ends such a transfer, which is what lets the store claim a bound on the
    /// wire at all (CLAUDE.md § What not to do, and what breaks if you do).
    ///
    /// Two minutes for the larger document, 453,903 bytes on 2026-09-13, is a
    /// floor of about 30 kbit/s — slower than any link this app is usable over,
    /// and still inside the sitting it was started in.
    private static let wireDeadline: TimeInterval = 120

    private let directory: URL
    private let transfer: Transfer
    private let lock = NSLock()
    /// nil until the first ask, which is what reads the two documents off the
    /// disk. See `loadedUnderTheLock`.
    ///
    /// **What this costs while it is held: 2.84 MiB.** Measured on 2026-09-14
    /// against the allocator's own books rather than the process footprint,
    /// because it is a per-object cost (CLAUDE.md § What not to do, and what
    /// breaks if you do) — `malloc_zone_statistics(malloc_default_zone(),)`,
    /// `size_in_use` across parsing both of this Mac's cached documents:
    /// 2,976,224 / 2,975,696 / 2,975,696 bytes over 15,270 entries, three
    /// consecutive readings. That is the module's largest standing allocation,
    /// it lasts for the life of the process, and it is the reading itself — so
    /// there is no version of this feature without it. What there *is* a
    /// version without is paying it on a Mac whose owner never searches, which
    /// is why this field starts nil.
    private var stored: PopularityReadings?

    public convenience init(directory: URL = HelmSupport.directory) {
        self.init(directory: directory, transfer: FilePopularityStore.liveTransfer)
    }

    init(directory: URL, transfer: @escaping Transfer) {
        self.directory = directory
        self.transfer = transfer
    }

    public func readings() -> PopularityReadings {
        lock.lock(); defer { lock.unlock() }
        return loadedUnderTheLock()
    }

    public func refreshIfDue() async {
        if let counts = await fetchIfDue(Self.formulae) {
            // On the day a fetch lands, this is the process's first ask for the
            // half that was not fetched, so it is exactly the parse
            // `fetchIfDue`'s own doc comment hops for — it belongs off the pool
            // for the same reason.
            await offThePoolInThePhase { [self] in replaceFormulae(with: counts) }
        }
        // A cancelled task still runs the line after its `await`, and the ask
        // below would only fail the same way a moment later.
        guard !Task.isCancelled else { return }
        if let counts = await fetchIfDue(Self.casks) {
            await offThePoolInThePhase { [self] in replaceCasks(with: counts) }
        }
        // Taken whether or not anything was due: the first reading for a label
        // is the baseline every later one is a delta against, and a refresh
        // that fetched nothing is the cheapest place to establish it.
        HelmLog.shared.memory(Self.phaseLabel)
    }

    // MARK: Private

    /// What this store's work is called in the activity trail, and the label
    /// its memory reading is filed under.
    ///
    /// **A bulk phase carries both or neither** (CLAUDE.md § What not to do,
    /// and what breaks if you do). Every synchronous hop in this store can
    /// reach `InstallCounts.parse`: the ETag gate through `readings()`, `adopt`
    /// through `PopularityRefresh.answer`, and each replace through `load`.
    /// That parse is the module's largest standing allocation — 2.84 MiB, see
    /// `stored` — so this is not work to leave out of the trail, and a named
    /// interval with no figure beside it would be the half of the trail that
    /// cannot be read.
    ///
    /// Prefixed with the module's own id, because that is what
    /// `HelmActivity.sweep(module:)` matches on when the host drops the module.
    static let phaseLabel = HomebrewEngine.moduleID + ".popularity"

    /// Off the pool and inside the phase, in one call — the two things every
    /// synchronous half of this refresh needs, so no call site can carry one
    /// and forget the other.
    private func offThePoolInThePhase<T: Sendable>(
        _ body: @escaping @Sendable () -> T
    ) async -> T {
        await offTheCooperativePool { HelmActivity.phase(Self.phaseLabel, body) }
    }

    /// What the last run stored, read off the disk the first time anybody asks
    /// and kept from then on. **Called with the lock held, by every path that
    /// touches `stored`.**
    ///
    /// **Not in `init`, and that is a measurement rather than a taste.** The two
    /// documents are 850 KB of JSON and 15,270 packages; parsing both takes
    /// 30 ms on this Mac, optimised, three readings out of three — and `init`
    /// runs inside `makeEngine`, which `ModuleHost.enable` calls on the main
    /// thread at launch for every module that is switched on.
    ///
    /// **Nor from the refresh unless the refresh needs it.** The only thing in
    /// `fetchIfDue` that wants a stored reading is the ETag gate, which is
    /// reached on a day a document is due with a tag beside it — so the whole
    /// of this stays unpaid on a launch with nothing due, and a Mac whose
    /// owner never searches pays nothing on that launch either. **A day a
    /// fetch succeeds pays for one half**, not for this: `replaceFormulae` and
    /// `replaceCasks` read the document they are *not* replacing rather than
    /// calling this, which would also read back the one `adopt` has just
    /// written and whose counts are in the caller's hand. When it *is* paid it
    /// is paid off the cooperative pool: by `fetchIfDue`'s own hop, by
    /// `refreshIfDue`'s hop around each replace, and by `search`'s.
    private func loadedUnderTheLock() -> PopularityReadings {
        if let stored { return stored }
        let loaded = PopularityReadings(formulae: load(Self.formulae) ?? .none,
                                        casks: load(Self.casks) ?? .none)
        stored = loaded
        return loaded
    }

    /// The two writers, synchronous and one line each, because a lock may not
    /// be held across a suspension and an `async` body may not take one at all
    /// (CLAUDE.md § What not to do, and what breaks if you do).
    ///
    /// **Only the other half is read.** These used to call
    /// `loadedUnderTheLock()`, which on the first ask — the ordinary case on a
    /// fetch day, since nothing before this has needed a reading — parses
    /// *both* cached documents, including the one `adopt` wrote a moment
    /// earlier whose counts are the argument here. That is about 450 KB read
    /// and parsed for a value already in hand, once per fetch day.
    private func replaceFormulae(with counts: InstallCounts) {
        lock.lock(); defer { lock.unlock() }
        stored = PopularityReadings(formulae: counts,
                                    casks: stored?.casks ?? load(Self.casks) ?? .none)
    }

    private func replaceCasks(with counts: InstallCounts) {
        lock.lock(); defer { lock.unlock() }
        stored = PopularityReadings(formulae: stored?.formulae ?? load(Self.formulae) ?? .none,
                                    casks: counts)
    }

    /// Its own session rather than `URLSession.shared`, for the two deadlines
    /// above: `timeoutIntervalForResource` is the bound that cannot be written
    /// on a request, and the shared session's is seven days. Ephemeral with no
    /// cache, because this store keeps its own copy of both documents and
    /// their tags — a URL cache would hold a second 850 KB saying the same
    /// thing, and decide freshness by rules this store does not control.
    ///
    /// **The headers are pinned here because CFNetwork writes its own.** The
    /// request `requestIfDue` builds sets a `User-Agent` and nothing else,
    /// which said nothing about what actually left the process. Measured on
    /// 2026-09-14 against a local listener printing what it received — one
    /// fetch with this session unpinned, one with it pinned as below:
    ///
    ///     unpinned: Host, If-None-Match, Accept: */*, User-Agent: Helm,
    ///               Accept-Language: ru, Accept-Encoding: gzip, deflate,
    ///               Connection: keep-alive
    ///     pinned:   Host, If-None-Match, Accept: application/json,
    ///               User-Agent: Helm, Accept-Language: en,
    ///               Accept-Encoding: gzip, deflate, Connection: keep-alive
    ///
    /// `Accept-Language: ru` is this Mac's own language preference, put on the
    /// wire by CFNetwork with nobody here asking for it — a fact about the
    /// person, handed to a third party on a fetch they did not start. Pinned to
    /// `en`, which is what this request would rather say than anything: the
    /// answer is a JSON document with no prose in it, so the value cannot even
    /// change what comes back.
    ///
    /// **What is left is not pinned and does not need to be.** `Accept-Encoding`
    /// is CFNetwork's own constant and setting it by hand turns off transparent
    /// decompression; `Connection` is the same constant on every client; `Host`
    /// is the endpoint being asked. None of the three varies with this Mac.
    /// Cookies are off — `httpShouldSetCookies` defaults to true, and an
    /// ephemeral session's jar is empty at launch but not after the first
    /// `Set-Cookie`, which would then name this install back to the endpoint on
    /// tomorrow's ask.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = idleDeadline
        config.timeoutIntervalForResource = wireDeadline
        config.urlCache = nil
        config.httpAdditionalHeaders = ["User-Agent": "Helm",
                                        "Accept": "application/json",
                                        "Accept-Language": "en"]
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// What a store built the live way gets: the wire, or — under a test
    /// runner — a refusal that never reaches it.
    ///
    /// **The guard is on the transfer and not on `refreshIfDue`.** Every test of
    /// this store calls `refreshIfDue` deliberately, handing it a fake transfer
    /// that stands for the wire; a guard inside `refreshIfDue` would leave all
    /// of them asserting about a method that returns immediately. What must not
    /// happen under a suite run is a *request*, and this is the one line a
    /// request goes through.
    ///
    /// Without it `swift test` fetched both documents from `formulae.brew.sh`
    /// on every run — about 834 KiB to a third party, silently, with nothing
    /// failing when it failed. Three files in `Tests/HelmAppTests` call
    /// `ModuleHost.bootstrap`, which enables every module the registry knows,
    /// and `HomebrewEngine.activate` is what starts the refresh.
    /// `HelmSupport.directory` already redirects the *files* a suite run would
    /// write (`TestProcess`, which says why the question is asked this way);
    /// the ask itself was not redirected at all.
    /// `ASuiteRunAsksHomebrewNothingTests` is what holds this line.
    static var liveTransfer: Transfer {
        TestProcess.isRunning ? refusedUnderTest : overTheNetwork
    }

    /// The refusal a suite run gets. A throw, because that is the shape the
    /// store already treats as "no new reading, leave the clock alone" — the
    /// same route an offline laptop takes.
    struct NoWireUnderTest: Error {}
    static let refusedUnderTest: Transfer = { _ in throw NoWireUnderTest() }

    /// How many requests have been handed to `URLSession` in this process.
    ///
    /// It exists for one assertion, and it is the only thing that can make it:
    /// a test cannot see a request that was never sent, and counting *attempts*
    /// here rather than packets on a wire is what keeps
    /// `ASuiteRunAsksHomebrewNothingTests` from passing on a machine that
    /// merely happens to be offline.
    static let wireAsks = AskCount()

    /// The only place `URLSession` appears. A non-HTTP response cannot come
    /// back from an `https` request, so it is a throw rather than a case the
    /// store carries: everything above this line speaks `HTTPURLResponse`.
    private static let overTheNetwork: Transfer = { request in
        wireAsks.record()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private func path(_ endpoint: Endpoint) -> URL {
        directory.appendingPathComponent(endpoint.file)
    }

    private func etagPath(_ endpoint: Endpoint) -> URL {
        directory.appendingPathComponent(endpoint.file + ".etag")
    }

    private func load(_ endpoint: Endpoint) -> InstallCounts? {
        guard let data = try? Data(contentsOf: path(endpoint)) else { return nil }
        return InstallCounts.parse(data)
    }

    /// nil for every route that is not a new reading — not due, refused,
    /// unchanged, cancelled — so the caller has one thing to do about all of
    /// them: leave what it has alone.
    ///
    /// **Both synchronous halves are hopped off the cooperative pool**, because
    /// between them they read a file attribute, parse up to
    /// `PopularityRefresh.sizeCeiling` of JSON, write a file through
    /// `PrivateFile` and set an attribute on it — and this runs inside a bare
    /// `Task`, which is the shared pool with one thread per core, the same
    /// shape every `brew` call in this module already goes through
    /// `offTheCooperativePool` for (CLAUDE.md § What not to do, and what breaks
    /// if you do). The wire itself stays *on* the pool: an `await` on a
    /// transfer holds no thread.
    private func fetchIfDue(_ endpoint: Endpoint) async -> InstallCounts? {
        guard let request = await offThePoolInThePhase({ [self] in requestIfDue(endpoint) })
        else { return nil }
        // No network, a refused connection, either deadline, and the
        // cancellation that arrives at quit all land here. None of them is
        // worth a line in somebody's log — an offline laptop is an ordinary
        // state, and a line that is printed on an ordinary day sends an
        // investigation after nothing (CLAUDE.md § What not to do, and what
        // breaks if you do).
        guard let (data, http) = try? await transfer(request) else { return nil }
        return await offThePoolInThePhase { [self] in adopt(data, http, from: endpoint) }
    }

    /// The request to make, or nil because nothing is due.
    ///
    /// Synchronous and off the pool: the last condition below reads and parses
    /// this endpoint's cached document, and it is written last so that a
    /// request already ruled out by an earlier condition — not due — never
    /// reaches it; `TheCountsAreAskedForOnceADayTests` holds that half.
    /// Whether the same is true when the document is due but no tag is
    /// sitting beside it is not something a test can observe from outside —
    /// `readings()` caches on first call either way, so nothing distinguishes
    /// "parsed here" from "parsed a moment later" — so this comment does not
    /// claim it.
    private func requestIfDue(_ endpoint: Endpoint) -> URLRequest? {
        let file = path(endpoint)
        let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard PopularityRefresh.isDue(lastWritten: written, now: Date()) else { return nil }

        var request = URLRequest(url: endpoint.url)
        request.setValue("Helm", forHTTPHeaderField: "User-Agent")
        // `config.timeoutIntervalForRequest` on `Self.session` is `idleDeadline`,
        // but a hand-built `URLRequest` always carries its own `timeoutInterval`
        // (default 60) and which of the two governs a `session.data(for:)` call
        // is unverified — the VPN module's precedent (`TraceExit`) calls
        // `session.data(from:)`, where the session builds the request itself and
        // never faces this. Setting it here too costs nothing and closes the
        // doubt: the idle deadline is `idleDeadline` whichever one wins.
        request.timeoutInterval = Self.idleDeadline
        // **A tag is a claim about a body this Mac still has.** Offered with the
        // document gone or unreadable, it earns a 304 — "what you have is
        // current" — about nothing at all, and the readings would stay empty
        // with the store believing itself up to date until somebody deleted the
        // tag by hand.
        if written != nil,
           let etag = try? String(contentsOf: etagPath(endpoint), encoding: .utf8),
           !endpoint.half(readings()).counts.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    /// What is done with an answer, and the only place anything is written.
    /// Synchronous and off the pool, for the reason `fetchIfDue` gives.
    private func adopt(_ data: Data, _ http: HTTPURLResponse,
                       from endpoint: Endpoint) -> InstallCounts? {
        let file = path(endpoint)
        switch PopularityRefresh.answer(statusCode: http.statusCode, data: data) {
        case .unchanged:
            // The one answer that spends the day without writing: nothing has
            // changed, so asking again this afternoon would learn nothing. A
            // touch that fails leaves the store due, which is the harmless
            // direction — one more conditional ask tomorrow morning.
            try? FileManager.default.setAttributes([.modificationDate: Date()],
                                                   ofItemAtPath: file.path)
            return nil
        case .refused(let why):
            HelmLog.shared.warn(HomebrewEngine.moduleID, why)
            return nil
        case .use(let counts):
            guard PrivateFile.writeMakingTheFolder(data, at: file) else {
                // The reading is good and is used; only the caching failed, so
                // the next launch asks again. Said out loud because a support
                // folder that cannot be written is a fact about this Mac and
                // not about Homebrew.
                HelmLog.shared.warn(HomebrewEngine.moduleID,
                                    "the install counts could not be cached — they will be "
                                    + "fetched again at the next launch")
                return counts
            }
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                // Discarded deliberately: a tag that does not land costs one
                // full document tomorrow instead of a 304, and the document
                // beside it is already stored and already the reading.
                _ = PrivateFile.writeMakingTheFolder(Data(etag.utf8), at: etagPath(endpoint))
            }
            return counts
        }
    }
}

// MARK: - Factory

public struct HomebrewSystemPorts {
    public let locator = FSBrewLocator()
    public let runner = ShellProcessRunner()
    public let privileged = OSAPrivilegedRunner()
    public let marker = FileOpMarker()
    public let popularity = FilePopularityStore()
    public init() {}
}
