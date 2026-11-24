import Foundation
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

// The Homebrew engine's fakes, in one place. A fake keeps its port's states only, and the
// port it stands in for is named at the construction (`brewEngine`'s own parameters, or
// `runner:`, `privileged:`) (Architecture/TestsAndMeasurement.md § Fakes). In the tests that run by
// default there is one `ProcessRunner` fake, `ScriptedRunner`: a test keeps its scenario in what it
// passes at construction (answers, the diagnostics stream, what a streamed child does, hooks
// for acting mid-call), not in a private class beside it.
// `NoPrivileges` answers with a fixed stand-in value (declined) that no test asserts.

/// The password dialog answered no: nothing ran.
struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

/// Homebrew is not installed, or was uninstalled in a terminal beside this
/// window — `FSBrewLocator` re-reads the disk at every call, so this is an
/// ordinary answer and not a broken fixture.
struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}

/// The engine every test builds: one inert set of ports (no brew on disk is read,
/// no dialog, an in-memory marker), so a test names only the port its question
/// is about (`runner`, `locator`, `marker`, ...).
func brewEngine(_ runner: ProcessRunner,
                locator: BrewLocator = FixedLocator(),
                privileged: PrivilegedRunner = NoPrivileges(),
                news: EngineNews<HomebrewNews> = EngineNews(),
                marker: OpMarker = InMemoryOpMarker(),
                popularity: PopularityReading = NoPopularity(),
                weight: PackageWeight = NoPackageWeight()) -> HomebrewEngine {
    HomebrewEngine(locator: locator, runner: runner, privileged: privileged, user: "tester",
                   news: news, marker: marker, popularity: popularity, weight: weight,
                   tools: ToolsAlreadyInstalled(), ticker: NoWaitTicker())
}

/// Kept only for the optional files that still conform to it (`ACaskIsNeverAskedWhatUsesItTests`,
/// `AnInfoQueryIsAboutOnePackageTests`, `ABatchThatAskedEveryNameDidNotGiveUpTests`,
/// `ASearchThatMatchesEverythingStillGetsItsDescriptionsTests`). New fakes use `ScriptedRunner`.
protocol QueryOnlyRunner: ProcessRunner {}

extension QueryOnlyRunner {
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

/// The name `ASizeIsMeasuredNotGuessedTests` (optional) is written against.
typealias IdleRunner = ScriptedRunner

/// One canned answer: the words an argument list must contain for this answer to
/// be the one, and the `(status, stdout)` brew would have replied with.
struct BrewAnswer {
    let match: [String]
    let status: Int32
    let stdout: String
    init(_ match: [String], _ status: Int32, _ stdout: String) {
        self.match = match; self.status = status; self.stdout = stdout
    }
}

/// The one `ProcessRunner` fake of this target. Records every call (what, with which
/// arguments and environment, on which thread) and answers as it is configured:
///
/// - **queries** (`run`, `runData`): `reply` first (nil passes), then the first of
///   `answers` whose words the arguments all contain, then status 0 and nothing. `runData`
///   answers from the same table, so a query that takes either path reads the same brew.
/// - **the diagnostics stream** (`runCapturingDiagnostics`): `diagnostics`, which is handed
///   the environment so a fake can answer as brew does for what it was asked. The port gives
///   it no default on purpose (`Ports.swift`).
/// - **a streamed child** (`stream`): `.finish(code)` ends it before the call returns, with a
///   `NoProcess`; `.hold` does not finish it until the test says so (`finishAll`, `exit`), and
///   hands back a `Handle` that counts the TERMs it receives. A runner that answered
///   synchronously would release the busy gate before the first call returned, and every gate
///   assertion would pass with the gate deleted.
///
/// `onRun` and `onStream` let a test act while a call is happening: the only way to be
/// exactly there (a press landing during the spawn, an engine switched off during a read).
final class ScriptedRunner: ProcessRunner, @unchecked Sendable {

    enum Streams {
        /// The child exits at once with this code.
        case finish(Int32)
        /// The child runs until the test finishes it.
        case hold
    }

    enum Kind { case run, runData, diagnostics, stream }

    struct Call {
        let kind: Kind
        let launch: String
        let args: [String]
        let env: [String: String]
        /// Only a `stream` that named one; `nil` for the form without `reach:`, which
        /// is itself what a test of the reach looks for.
        let reach: StopReach?
        let onMain: Bool
        let queue: String
    }

    /// A handle the way the real one is: terminating it does not finish the
    /// stream by itself — the child dies, *then* EOF and the exit arrive.
    final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var terminations: Int { lock.lock(); defer { lock.unlock() }; return n }
        var terminated: Bool { terminations > 0 }
        func terminate() { lock.lock(); n += 1; lock.unlock() }
    }

    let streams: Streams
    let reply: (@Sendable (_ args: [String]) -> (status: Int32, stdout: String)?)?
    let diagnostics: @Sendable (_ env: [String: String]) -> (status: Int32, output: String)
    /// Called after a `run` or `runData` has been answered, with its arguments.
    var onRun: (@Sendable (_ args: [String]) -> Void)?
    /// Called after the child exists and before the handle is handed back.
    var onStream: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var _answers: [BrewAnswer]
    private var _calls: [Call] = []
    private var _handles: [Handle] = []
    private var _exits: [@Sendable (Int32) -> Void] = []
    private var _lineSink: (@Sendable (String) -> Void)?

    init(streams: Streams = .finish(0),
         answers: [BrewAnswer] = [],
         reply: (@Sendable (_ args: [String]) -> (status: Int32, stdout: String)?)? = nil,
         diagnostics: @escaping @Sendable (_ env: [String: String]) -> (status: Int32, output: String) = { _ in (0, "") }) {
        self.streams = streams
        self._answers = answers
        self.reply = reply
        self.diagnostics = diagnostics
    }

    /// What queries answer; a test can change it between two calls (the Cellar a
    /// terminal changed, a brew that now holds somebody else's lock).
    var answers: [BrewAnswer] {
        get { lock.withLock { _answers } }
        set { lock.withLock { _answers = newValue } }
    }

    /// Every call of every kind, in order.
    var calls: [Call] { lock.withLock { _calls } }
    /// The arguments of the `run` and `runData` calls.
    var queries: [[String]] { calls.filter { $0.kind == .run || $0.kind == .runData }.map(\.args) }
    /// The arguments of the `runCapturingDiagnostics` calls.
    var diagnosticsCalls: [[String]] { calls.filter { $0.kind == .diagnostics }.map(\.args) }
    var streamCalls: [Call] { calls.filter { $0.kind == .stream } }
    /// The arguments of each streamed call, in order.
    var streamed: [[String]] { streamCalls.map(\.args) }
    var handles: [Handle] { lock.withLock { _handles } }

    private func note(_ kind: Kind, _ launch: String, _ args: [String], _ env: [String: String],
                      reach: StopReach? = nil) {
        let call = Call(kind: kind, launch: launch, args: args, env: env, reach: reach,
                        onMain: Thread.isMainThread,
                        queue: String(cString: __dispatch_queue_get_label(nil)))
        lock.withLock { _calls.append(call) }
    }

    private func answer(_ args: [String]) -> (status: Int32, stdout: String) {
        if let given = reply?(args) { return given }
        for a in answers where a.match.allSatisfy(args.contains) { return (a.status, a.stdout) }
        return (0, "")
    }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        note(.run, launchPath, args, env)
        let given = answer(args)
        onRun?(args)
        return given
    }

    func runData(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: Data) {
        note(.runData, launchPath, args, env)
        let given = answer(args)
        onRun?(args)
        return (given.status, Data(given.stdout.utf8))
    }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        note(.diagnostics, launchPath, args, env)
        return diagnostics(env)
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        launch(launchPath, args, env, nil, onLine, onExit)
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String], reach: StopReach,
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        launch(launchPath, args, env, reach, onLine, onExit)
    }

    private func launch(_ launchPath: String, _ args: [String], _ env: [String: String], _ reach: StopReach?,
                        _ onLine: @escaping @Sendable (String) -> Void,
                        _ onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        note(.stream, launchPath, args, env, reach: reach)
        switch streams {
        case .finish(let code):
            onStream?()
            onExit(code)
            return NoProcess()
        case .hold:
            let handle = Handle()
            lock.withLock { _handles.append(handle); _exits.append(onExit); _lineSink = onLine }
            onStream?()
            return handle
        }
    }

    /// The child is gone; the pipe closes; the exit lands. SIGTERM deaths
    /// report the signal number, which is what the engine must not read as
    /// a build failure once it asked for the stop itself.
    func finishAll(code: Int32 = 0) {
        let exits = lock.withLock { () -> [@Sendable (Int32) -> Void] in
            let taken = _exits; _exits = []; return taken
        }
        for exit in exits { exit(code) }
    }

    /// A line the most recent held child prints, fed by hand so the order is the test's.
    func line(_ text: String) { lock.withLock { _lineSink }?(text) }
    /// The most recent held child exits (after `finishAll` it is no longer listed, so a
    /// test that feeds by hand does not also `finishAll`).
    func exit(_ code: Int32) { lock.withLock { _exits.last }?(code) }
}

/// What the news says now, read through its replay. A sentinel emitted before
/// reading marks where the replay ends, so the read is deterministic; it has a
/// slot of its own each time, because an earlier call's sentinel is still in the
/// replay and only this call's ends the read. Pass the `tape` subscribed before
/// the act to see every item sent since, not only the replayed latest.
func replay(_ news: EngineNews<HomebrewNews>, from tape: AsyncStream<HomebrewNews>? = nil) async -> [HomebrewNews] {
    let sentinel = "test.sentinel.\(UUID().uuidString)"
    news.say(.line(sentinel), slot: sentinel)
    var items: [HomebrewNews] = []
    for await item in tape ?? news.stream() {
        if case .line(sentinel) = item { break }
        items.append(item)
    }
    return items
}

extension Array where Element == HomebrewNews {
    var states: [OpState] {
        compactMap { item -> OpState? in if case .state(let s) = item { return s }; return nil }
    }
    var sawBusy: Bool { contains { if case .busy = $0 { return true }; return false } }
}

/// The last `opState` the news holds, read through its replay: a sentinel
/// emitted before subscribing marks where the replay ends, so the read is
/// deterministic.
func lastOpState(_ news: EngineNews<HomebrewNews>) async -> OpState? {
    await replay(news).states.last
}

/// The latest `opState` the news would replay to a page opened now, and whether
/// a `.busy` came with it.
func replayedState(_ news: EngineNews<HomebrewNews>) async -> (state: OpState?, busy: Bool) {
    let items = await replay(news)
    return (items.states.last, items.sawBusy)
}

/// Everything the stream says up to and including the first item `last`
/// accepts. A watchdog cancels the read after ten seconds, so a stream that
/// never says it fails the assertion instead of hanging the run.
func collect(_ news: AsyncStream<HomebrewNews>,
             through last: @escaping @Sendable (HomebrewNews) -> Bool) async -> [HomebrewNews] {
    let reader = Task { () -> [HomebrewNews] in
        var got: [HomebrewNews] = []
        for await item in news {
            got.append(item)
            if last(item) { break }
        }
        return got
    }
    let watchdog = Task { try? await Task.sleep(for: .seconds(10)); reader.cancel() }
    let got = await reader.value
    watchdog.cancel()
    return got
}
