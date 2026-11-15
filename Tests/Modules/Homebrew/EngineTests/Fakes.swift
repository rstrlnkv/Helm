import Foundation
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

// The Homebrew engine's `ProcessRunner` and `PrivilegedRunner` fakes that more than
// one test file needed, in one place. A fake keeps its port's states only, and every
// construction names the port it stands in for (`runner:`, `privileged:`)
// (Architecture/TestsAndMeasurement.md § Fakes). Fakes that script one test's
// scenario (canned answers, handles, interruptions) stay beside that test.
// `NoPrivileges` and `IdleRunner` answer with fixed stand-in values (declined, status 0,
// empty output) that no test asserts: no test reads them, so they are inert.

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

/// Answers every query with status 0 and nothing on standard output, and ends
/// every streamed child at once.
struct IdleRunner: ProcessRunner, @unchecked Sendable {
    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

/// Records `(args, env)` of every query and every stream, and ends each streamed
/// child at once.
final class EnvironmentRecorder: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(args: [String], env: [String: String])] = []
    var calls: [(args: [String], env: [String: String])] { lock.withLock { _calls } }

    func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) {
        lock.withLock { _calls.append((args, env)) }
        return (0, "")
    }

    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.withLock { _calls.append((args, env)) }
        onExit(0)
        return NoProcess()
    }
}

/// One recorded `stream` invocation: what would have been launched, with what.
struct StreamCall {
    let launch: String
    let args: [String]
    let env: [String: String]
}

/// Records what it was asked to stream and does not finish it until the test
/// says so. A runner that answered synchronously would release the busy gate
/// before the first call returned, and every gate assertion would pass with the
/// gate deleted. Each streamed child gets a `Handle` that counts the TERMs it
/// receives, which a `NoProcess` could not: "the installer was terminated" is
/// unrepresentable against a fake simpler than the port.
final class HangingRunner: ProcessRunner, @unchecked Sendable {
    /// A handle the way the real one is: terminating it does not finish the
    /// stream by itself — the child dies, *then* EOF and the exit arrive.
    final class Handle: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var terminations: Int { lock.lock(); defer { lock.unlock() }; return n }
        var terminated: Bool { terminations > 0 }
        func terminate() { lock.lock(); n += 1; lock.unlock() }
    }

    private let lock = NSLock()
    private var _streamCalls: [StreamCall] = []
    private var _handles: [Handle] = []
    private var _exits: [@Sendable (Int32) -> Void] = []
    /// What `brew list` answers on standard output (formulae only; `--cask` is empty).
    var listing = ""

    var streamCalls: [StreamCall] { lock.lock(); defer { lock.unlock() }; return _streamCalls }
    var handles: [Handle] { lock.lock(); defer { lock.unlock() }; return _handles }
    /// The arguments of each streamed call, in order.
    var calls: [[String]] { streamCalls.map(\.args) }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        if args.first == "list", !args.contains("--cask") { return (0, listing) }
        return (0, "")
    }

    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        let handle = Handle()
        lock.lock()
        _streamCalls.append(StreamCall(launch: launchPath, args: args, env: env))
        _handles.append(handle)
        _exits.append(onExit)
        lock.unlock()
        return handle
    }

    /// The child is gone; the pipe closes; the exit lands. SIGTERM deaths
    /// report the signal number, which is what the engine must not read as
    /// a build failure once it asked for the stop itself.
    func finishAll(code: Int32 = 0) {
        lock.lock(); let exits = _exits; _exits = []; lock.unlock()
        for exit in exits { exit(code) }
    }
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
