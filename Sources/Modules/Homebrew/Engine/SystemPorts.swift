import Foundation
import HelmRuntime
import os

// MARK: - Locator

public struct FSBrewLocator: BrewLocator {
    init() {}
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
/// **Bytes, not text.** `availableData` splits on byte boundaries, so a
/// multi-byte character can straddle two reads, and a failable decode of the
/// chunk would lose the whole chunk. `brew` prints non-ASCII on every
/// successful install.
///
/// So the split happens on the newline *byte* and only complete lines are
/// decoded; an unfinished character stays in the buffer with its line.
/// `String(decoding:as:)`, not the failable initialiser: bytes that are not
/// UTF-8 at all come through as replacement characters instead of taking the
/// lines around them.
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

public struct ShellProcessRunner: ProcessRunner {
    /// How long a *query* may go unanswered before it is a hang, not a wait.
    ///
    /// `run`, `runData` and `runCapturingDiagnostics` serve the read-only queries
    /// (list, outdated, desc, search, uses, info, config, doctor); the long
    /// operations stream and are stopped by hand, never by a clock.
    /// Warm queries answer in well under a second and a cold `brew outdated`,
    /// which goes to the network, in seconds. Ninety seconds clears that more
    /// than tenfold and still ends a hung brew (another brew's lock, a stalled
    /// network read) inside the same sitting.
    static let defaultQueryTimeout: TimeInterval = 90

    private let queryTimeout: TimeInterval

    init(queryTimeout: TimeInterval = ShellProcessRunner.defaultQueryTimeout) {
        self.queryTimeout = queryTimeout
    }

    private func environment(_ extra: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
    }

    /// The body is `HelmProcess`, like every other module's. Stderr is dropped:
    /// `BrewListParser` takes the first word of every line as a package name,
    /// so a warning from `brew` would become a row with an Uninstall button.
    ///
    /// `stream` keeps stderr: a console should show what the tool says. It is
    /// output that gets parsed that must not carry diagnostics.
    public func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) {
        let result = HelmProcess.run(launchPath, args, env: env, timeout: queryTimeout)
        return (result.status, result.output)
    }

    /// The bytes without the String round-trip (`HelmProcess.runData`).
    public func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data) {
        let r = HelmProcess.runData(launchPath, args, env: env, timeout: queryTimeout)
        return (r.status, r.output)
    }

    /// `brew doctor` prints its entire answer on standard error and nothing on
    /// standard output. `run` drops stderr on purpose for every other query
    /// (`brew uses` warns there), so `doctor` gets the one method that goes
    /// and gets it, rather than a change to `run` that would break every other
    /// parser here.
    ///
    /// **A merged read, through `HelmProcess`.** The same launch guard, launch
    /// slot, deadline (TERM, then KILL after a grace) and read-before-wait as
    /// `runData`, with standard error merged into the one pipe; past the
    /// deadline the answer is `HelmProcess.timedOutStatus` with no output.
    public func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        let r = HelmProcess.runData(launchPath, args, env: env, timeout: queryTimeout,
                                    standardError: .merged)
        return (r.status, String(decoding: r.output, as: UTF8.self))
    }

    /// **The exit is reported at end of pipe, not at end of process.** When the
    /// child exits, what the reader has not picked up is still in the pipe, and
    /// the reader always runs behind: `onLine` hops to the main actor and
    /// redraws a console. Ending at the process would lose the tail of a
    /// `brew install`, the part that says where it put things.
    ///
    /// Reading to the end first is the order `HelmProcess.run` uses. EOF
    /// arrives only when every writer has closed, so the wait below is
    /// immediate rather than a poll.
    @discardableResult
    public func stream(_ launchPath: String, _ args: [String], env: [String: String],
                       onLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        stream(launchPath, args, env: env, reach: .wholeGroup, onLine: onLine, onExit: onExit)
    }

    @discardableResult
    public func stream(_ launchPath: String, _ args: [String], env: [String: String], reach: StopReach,
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
        // Carries the exit status from the termination callback to whoever reports it.
        let status = OSAllocatedUnfairLock(initialState: Int32(-1))
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { proc in
            status.withLock { $0 = proc.terminationStatus }
            exited.signal()
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else {
                // Empty means end of file: everything written has been read.
                handle.readabilityHandler = nil
                buffer.flush()
                exited.wait()
                onExit(status.withLock { $0 })
                return
            }
            buffer.feed(d)
        }
        // `HelmProcess.start`, never `try p.run()`: a launch `NSTask` *raises*
        // on takes the whole app down, because the exception has no Swift
        // frame to land on.
        guard HelmProcess.start(p, path: launchPath) else {
            // No child, so no EOF is ever coming — the page would keep its
            // spinner forever waiting for one.
            pipe.fileHandleForReading.readabilityHandler = nil
            onExit(-1)
            return NoProcess()
        }
        // The handle retains the `Process`, so the child stays addressable.
        return LiveProcess(p, reach: reach)
    }
}

/// The real handle: SIGTERM, so a brew mid-operation gets to clean up after
/// itself — never KILL, which is how half-written Cellar state is made. The
/// exit still arrives through the pipe's EOF, the same way an honest exit does.
///
/// **`.wholeGroup` signals the group, and only a group this child leads.**
/// `Process` makes the child its own group leader, so `killpg(pid)` reaches the
/// child and everything it started that has not left the group. A group id
/// that is not the child's own is somebody else's; then this falls back to
/// `Process.terminate()`.
///
/// **`.process` is `Process.terminate()` and nothing more, which already
/// reaches the child's group** (`StopReach`). The two reaches differ in the
/// leader check and the repeats; a `kill(pid)` for `.process` would leave the
/// `curl` or `git` a brew operation started alive after the Stop.
///
/// **The group is signalled again while the leader is still there.** A shell
/// forking at the instant of the signal creates a program the signal never
/// sees. The shell notices its own TERM at the next command boundary and forks
/// nothing further, so a second signal a moment later finds that program. The
/// repeats stop as soon as the leader is gone.
private struct LiveProcess: RunningProcess, @unchecked Sendable {
    let process: Process
    let reach: StopReach
    /// Seconds after the first signal at which the group is signalled again.
    private static let repeats: [TimeInterval] = [0.1, 0.4]

    init(_ process: Process, reach: StopReach) {
        self.process = process
        self.reach = reach
    }

    func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard reach == .wholeGroup, signalGroup(pid) else {
            process.terminate()
            return
        }
        let handle = self
        for delay in Self.repeats {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [handle] in
                guard handle.process.isRunning else { return }
                _ = handle.signalGroup(pid)
            }
        }
    }

    private func signalGroup(_ pid: pid_t) -> Bool {
        pid > 1 && getpgid(pid) == pid && killpg(pid, SIGTERM) == 0
    }
}

// MARK: - Privileged runner

public struct OSAPrivilegedRunner: PrivilegedRunner {
    init() {}
    /// Through `PrivilegedRun`, which reads the `(-128)` of a cancelled dialog
    /// off standard error, so a cancel is not a failed `mkdir`. The escaping
    /// stays in `AppleScript`, reached through it.
    public func runAdmin(_ script: String) -> PrivilegedOutcome {
        PrivilegedRun.run(script)
    }
}

// MARK: - Command Line Tools

/// Apple's Command Line Tools, read and asked for on the real machine.
///
/// Both short launches go through `HelmProcess`, and so through the launch
/// guard: `xcode-select` is a system tool and still a launch, and a launch that
/// raises must not take the app with it.
public struct SystemCommandLineTools: CommandLineToolsPort {
    /// The bundle id of Apple's installer, read out of the `Info.plist` of
    /// `/System/Library/CoreServices/Install Command Line Developer Tools.app`
    /// on macOS 27 and unread on 26. That app is `LSUIElement`: no Dock icon,
    /// but it is in the running list. A wrong identity degrades to a wait that
    /// ends at Stop (`CommandLineTools.next`, rule 4), and the log says so once.
    private static let installerBundleID = "com.apple.dt.CommandLineTools.installondemand"

    /// The request is only filed, but it may ask for a password, so the
    /// deadline leaves room for one.
    private static let requestDeadline: TimeInterval = 30
    private static let selectDeadline: TimeInterval = 10

    init() {}

    public func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    public func selectedDeveloperDirectory() -> String? {
        let result = HelmProcess.run("/usr/bin/xcode-select", ["-p"], timeout: Self.selectDeadline)
        // Exit 2 is «no developer directory»; the deadline and a failed launch
        // are other statuses. All three are nil, for the reason the protocol gives.
        return result.status == 0 ? result.output : nil
    }

    public func requestInstall() -> ToolsRequest {
        let result = HelmProcess.run("/usr/bin/xcode-select", ["--install"], timeout: Self.requestDeadline)
        if result.status == HelmProcess.timedOutStatus { return .timedOut }
        return result.status == 0 ? .filed : .refused(result.status)
    }

    /// `RunningApps` is refreshed on the main thread only, so the reading hops
    /// there (ARCHITECTURE.md § Running applications). AppKit itself does not come into this module.
    public func installerIsRunning() -> Bool {
        let ids = Thread.isMainThread
            ? RunningApps.shared.bundleIDs()
            : DispatchQueue.main.sync { RunningApps.shared.bundleIDs() }
        return ids.contains(Self.installerBundleID)
    }
}

/// The real ticker. **Not the main queue**, unlike Keep Awake's clock: what a
/// tick continues into is a blocking password dialog, and that must not be
/// raised on the thread that draws the page.
public struct DispatchWaitTicker: WaitTicker {
    init() {}
    public func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        DelayedWork.schedule(on: .global(qos: .userInitiated), after: interval, block)
    }
}

// MARK: - Operation marker

/// The marker as a file, so it survives the quit it exists to report.
///
/// The label names a package, a fact about the person's machine, so the file
/// goes through `PrivateFile`. `HelmSupport.directory` redirects it into
/// scratch under a test runner.
public struct FileOpMarker: OpMarker {
    private let url: URL

    init(directory: URL = HelmSupport.directory) {
        url = directory.appendingPathComponent("homebrew-operation")
    }

    /// A marker that does not land leaves the next launch nothing to report a
    /// quit with. Nothing can be done here, so it is said; the label is not,
    /// because it names a package.
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

/// Homebrew's published install counts, cached in Helm's own folder.
///
/// Two whole public documents, fetched at most once a day
/// (ARCHITECTURE.md § Install counts). Every header that could name this Mac
/// is pinned on the session (`session`). The ETag is stored beside each file, so a daily ask
/// can be a 304 with no body.
///
/// **Can be, not is.** GitHub Pages answers `W/"<mtime>-<size>"` and its nodes
/// hold the same document with mtimes a second apart, so the same tag earns a
/// 304 from one node and a 200 from the next. A 200 costs only the document,
/// and the daily gate holds either way.
///
/// **Everything here fails towards the unranked search.** An unreadable file,
/// a refused fetch, an unparseable document: each leaves the readings as they
/// were. A refusal must never be recorded as an *empty* reading (`[:]` means
/// nobody installs anything), which is why `PopularityRefresh.answer` names
/// its refusals.
///
/// **And a refusal must not stamp the clock.** The clock is the cached file's
/// modification date, so only a write sets it; a 304 is the one exception,
/// an answer worth a day. A cancellation mid-fetch is ordinary (`deactivate()`
/// runs on every route out of the app) and reads as "ask again next launch".
public final class FilePopularityStore: PopularityReading, @unchecked Sendable {

    /// What a fetch is, as a function: the one seam in this type, standing for
    /// `URLSession.data(for:)` and nothing else. The clock, the files and the
    /// readings are the real ones in every test.
    typealias Transfer = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    struct Endpoint: Sendable {
        let url: URL
        let file: String
        /// Which half of a reading this document is. The ETag gate asks through
        /// `readings()`, so it costs no parse of its own.
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

    /// How long a transfer may go without a byte arriving. Nobody waits on it,
    /// but an unanswered read holds a task for as long as the wire lets it.
    private static let idleDeadline: TimeInterval = 30

    /// How long the whole transfer may take, whatever arrives meanwhile.
    ///
    /// **`idleDeadline` alone is not a bound.** It restarts on every packet, so
    /// an endpoint trickling a byte at a time never trips it — and the ceiling
    /// in `PopularityRefresh` cannot help either, because it is consulted once
    /// `URLSession` has already buffered the body. This is the one thing that
    /// ends such a transfer.
    ///
    /// Two minutes for the larger document (about 450 KB) is a floor of about
    /// 30 kbit/s, slower than any link this app is usable over.
    private static let wireDeadline: TimeInterval = 120

    private let directory: URL
    let transfer: Transfer
    private let lock = NSLock()
    /// nil until the first ask, which is what reads the two documents off the
    /// disk. See `loadedUnderTheLock`.
    ///
    /// **About 3 MB while it is held**, read off the allocator's books
    /// (ARCHITECTURE.md § The memory trail): the module's largest standing
    /// allocation, for the life of the process. It is the reading itself, so it
    /// cannot go; it starts nil so a Mac whose owner never searches never pays.
    private var stored: PopularityReadings?

    convenience init(directory: URL = HelmSupport.directory) {
        self.init(directory: directory, transfer: FilePopularityStore.liveTransfer)
    }

    init(directory: URL, transfer: @escaping Transfer) {
        self.directory = directory
        self.transfer = transfer
    }

    public func readings() -> PopularityReadings { lock.withLock { loadedUnderTheLock() } }

    public func refreshIfDue() async {
        if let counts = await fetchIfDue(Self.formulae) {
            // May parse the other half's document: off the pool, as in
            // `fetchIfDue`.
            await offThePoolInThePhase { [self] in replaceFormulae(with: counts) }
        }
        // A cancelled task still runs the line after its `await`, and the ask
        // below would only fail the same way a moment later.
        guard !Task.isCancelled else { return }
        if let counts = await fetchIfDue(Self.casks) {
            await offThePoolInThePhase { [self] in replaceCasks(with: counts) }
        }
        // Taken whether or not anything was due: the first reading for a label
        // is the baseline every later one is a delta against.
        HelmLog.shared.memory(Self.phaseLabel)
    }

    // MARK: Private

    /// What this store's work is called in the activity trail, and the label
    /// its memory reading is filed under.
    ///
    /// **A bulk phase carries both or neither** (ARCHITECTURE.md § The memory trail).
    /// Every synchronous hop in this store can reach `InstallCounts.parse`, the
    /// module's largest allocation (`stored`).
    ///
    /// Prefixed with the module's own id, because that is what
    /// `HelmActivity.sweep(module:)` matches on when the host drops the module.
    static let phaseLabel = HomebrewEngine.moduleID + ".popularity"

    /// Off the pool and inside the phase, in one call, so no call site can
    /// carry one and forget the other.
    private func offThePoolInThePhase<T: Sendable>(
        _ body: @escaping @Sendable () -> T
    ) async -> T {
        await offTheCooperativePool { HelmActivity.phase(Self.phaseLabel, body) }
    }

    /// What the last run stored, read off the disk the first time anybody asks
    /// and kept from then on. **Called with the lock held, by every path that
    /// touches `stored`.**
    ///
    /// **Not in `init`**: parsing both documents (about 850 KB of JSON) takes
    /// tens of milliseconds, and `init` runs inside `makeModule`, on the main
    /// thread at launch.
    ///
    /// **Nor from the refresh unless it needs it.** Only the ETag gate wants a
    /// stored reading, on a day a document is due with a tag beside it, so a
    /// launch with nothing due pays nothing. A fetch day pays for one half
    /// (`replaceFormulae`, `replaceCasks`). When it is paid, it is paid off the
    /// cooperative pool: by `fetchIfDue`'s hop, `refreshIfDue`'s, and `search`'s.
    private func loadedUnderTheLock() -> PopularityReadings {
        if let stored { return stored }
        let loaded = PopularityReadings(formulae: load(Self.formulae) ?? .none,
                                        casks: load(Self.casks) ?? .none)
        stored = loaded
        return loaded
    }

    /// The two writers, synchronous and one line each, because a lock may not
    /// be held across a suspension and an `async` body may not take one at all
    /// (ARCHITECTURE.md § Sealed settings).
    ///
    /// **Only the other half is read**, not `loadedUnderTheLock()`: that would
    /// also parse the document `adopt` just wrote, whose counts are already the
    /// argument.
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
    /// their tags; a URL cache would hold a second copy and decide freshness by
    /// rules this store does not control.
    ///
    /// **The headers are pinned here because CFNetwork writes its own.**
    /// Unpinned, it sends `Accept-Language` with this Mac's own language, a
    /// fact about the person handed to a third party on a fetch they did not
    /// start. Pinned to `en`: the answer is JSON with no prose, so the value
    /// cannot change what comes back.
    ///
    /// **What is left is not pinned and does not need to be.** `Accept-Encoding`
    /// is CFNetwork's own constant and setting it by hand turns off transparent
    /// decompression; `Connection` is the same on every client; `Host` is the
    /// endpoint. Cookies are off: an ephemeral jar fills at the first
    /// `Set-Cookie`, which would name this install back on tomorrow's ask.
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
    /// this store calls `refreshIfDue` with a fake transfer; a guard there
    /// would leave them asserting about a method that returns at once. What
    /// must not happen under a suite run is a *request*, and this is the one
    /// line a request goes through.
    ///
    /// App-layer tests call `ModuleHost.bootstrap`, which activates every
    /// module, and activation starts the refresh; without this a suite run
    /// fetches from `formulae.brew.sh`. `ASuiteRunAsksHomebrewNothingTests`
    /// holds this line.
    static var liveTransfer: Transfer {
        TestProcess.isRunning ? refusedUnderTest : overTheNetwork
    }

    /// The refusal a suite run gets: a throw, the route an offline laptop
    /// takes ("no new reading, leave the clock alone"). Named so
    /// `ASuiteRunAsksHomebrewNothingTests` can assert on it: a request never
    /// sent leaves nothing else to see.
    struct NoWireUnderTest: Error {}
    static let refusedUnderTest: Transfer = { _ in throw NoWireUnderTest() }

    /// The only place `URLSession` appears. A non-HTTP response cannot come
    /// back from an `https` request, so it is a throw rather than a case the
    /// store carries: everything above this line speaks `HTTPURLResponse`.
    private static let overTheNetwork: Transfer = { request in
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
    /// **Both synchronous halves are hopped off the cooperative pool**: they
    /// read and write files and parse up to `PopularityRefresh.sizeCeiling` of
    /// JSON (ARCHITECTURE.md § Running other programs). The wire itself stays
    /// *on* the pool: an `await` on a transfer holds no thread.
    private func fetchIfDue(_ endpoint: Endpoint) async -> InstallCounts? {
        guard let request = await offThePoolInThePhase({ [self] in requestIfDue(endpoint) })
        else { return nil }
        // No network, a refused connection, either deadline, and the
        // cancellation at quit all land here, unlogged: an offline laptop is an
        // ordinary state (ARCHITECTURE.md § Diagnostics log).
        guard let (data, http) = try? await transfer(request) else { return nil }
        return await offThePoolInThePhase { [self] in adopt(data, http, from: endpoint) }
    }

    /// The request to make, or nil because nothing is due.
    ///
    /// Synchronous and off the pool: the last condition below parses this
    /// endpoint's cached document, and it is last so a request that is not due
    /// never reaches it (`TheCountsAreAskedForOnceADayTests`).
    private func requestIfDue(_ endpoint: Endpoint) -> URLRequest? {
        let file = path(endpoint)
        let written = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard PopularityRefresh.isDue(lastWritten: written, now: Date()) else { return nil }

        var request = URLRequest(url: endpoint.url)
        request.setValue("Helm", forHTTPHeaderField: "User-Agent")
        // A hand-built `URLRequest` carries its own `timeoutInterval` (default
        // 60), and which of it and the session's governs `data(for:)` is
        // unverified; set both, so the idle deadline holds whichever wins.
        request.timeoutInterval = Self.idleDeadline
        // **A tag is a claim about a body this Mac still has.** Offered with the
        // document gone, it earns a 304 about nothing, and the readings stay
        // empty while the store believes itself current.
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
            // The one answer that spends the day without writing. A touch that
            // fails leaves the store due: one more conditional ask, harmless.
            try? FileManager.default.setAttributes([.modificationDate: Date()],
                                                   ofItemAtPath: file.path)
            return nil
        case .refused(let why):
            HelmLog.shared.warn(HomebrewEngine.moduleID, why)
            return nil
        case .use(let counts):
            guard PrivateFile.writeMakingTheFolder(data, at: file) else {
                // The reading is used; only the caching failed. Said, because an
                // unwritable support folder is a fact about this Mac.
                HelmLog.shared.warn(HomebrewEngine.moduleID,
                                    "the install counts could not be cached — they will be "
                                    + "fetched again at the next launch")
                return counts
            }
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                // Discarded deliberately: a lost tag costs one full document
                // tomorrow instead of a 304.
                _ = PrivateFile.writeMakingTheFolder(Data(etag.utf8), at: etagPath(endpoint))
            }
            return counts
        }
    }
}

// MARK: - What a package occupies

/// The size of a package, walked out of `<prefix>/Cellar/<name>`.
///
/// **The prefix is asked for at every call and never remembered.** It comes
/// from the locator's answer, which re-reads the disk each time
/// (`FSBrewLocator`): Homebrew can move between `/usr/local` and
/// `/opt/homebrew` while the window is open, and a frozen prefix would measure
/// a Cellar the rest of the module is not talking to.
public struct CellarWeight: PackageWeight {
    private let locator: BrewLocator
    init(locator: BrewLocator) { self.locator = locator }

    public func bytes(ofPackage name: String, isCask: Bool) -> Int? {
        // **Before the prefix is even asked for.** A cask has no Cellar
        // directory, so «nothing to measure» is *known* here, and «nothing was
        // walked» stays provable from outside.
        guard !isCask, isAPackageName(name) else { return nil }
        guard let brew = locator.brewPath() else { return nil }
        // `/opt/homebrew/bin/brew` → `/opt/homebrew`, the shape of both
        // prefixes `FSBrewLocator` looks for.
        let keg = URL(fileURLWithPath: brew)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Cellar").appendingPathComponent(name)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: keg.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        // **Zero is a refusal here, not a measurement.** `FileWeight.allocated`
        // answers 0 for a path it could not read (a `chmod`, a TCC refusal),
        // and an installed keg always occupies blocks, so zero folds into the
        // one nil the row is absent for.
        let measured = FileWeight.allocated(of: keg)
        guard measured > 0 else {
            // Only about a directory that is *there*: a refusal is logged, an
            // absence is not (ARCHITECTURE.md § Diagnostics log).
            HelmLog.shared.warn(HomebrewEngine.moduleID,
                                "the Cellar directory of \(Redact.pkg(name)) measured nothing "
                                + "— it is there and could not be read")
            return nil
        }
        return measured
    }

    /// Whether `name` can name a directory *inside* the Cellar and nothing else.
    ///
    /// **The string is appended to a path that is then walked**, and it reaches
    /// this port from `brew`'s own stdout and from the search box somebody types
    /// into. `..` points the walk at the prefix, `.` at the whole Cellar, and a
    /// separator wherever it leads, all reported as one package's size. A
    /// formula's name is one path component, so this refuses everything else
    /// rather than trying to repair it.
    private func isAPackageName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }
}

// MARK: - Factory

public struct HomebrewSystemPorts {
    public let locator = FSBrewLocator()
    public let runner = ShellProcessRunner()
    public let privileged = OSAPrivilegedRunner()
    public let tools = SystemCommandLineTools()
    public let ticker = DispatchWaitTicker()
    public let marker = FileOpMarker()
    public let popularity = FilePopularityStore()
    /// Built over the same locator the engine uses, so «which brew» has one
    /// answer on this Mac rather than two.
    public var weight: CellarWeight { CellarWeight(locator: locator) }
    public init() {}
}
