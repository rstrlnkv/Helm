import Foundation
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

/// One recorded `stream` invocation: what would have been launched, with what.
struct StreamCall {
    let launch: String
    let args: [String]
    let env: [String: String]
}

/// Records what it was asked to stream and does not finish it until the test
/// says so. A runner that answered synchronously would release the busy gate
/// before the first call returned, and every gate assertion would pass with the
/// gate deleted.
final class HangingRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _streamCalls: [StreamCall] = []
    private var _exits: [@Sendable (Int32) -> Void] = []

    var streamCalls: [StreamCall] { lock.lock(); defer { lock.unlock() }; return _streamCalls }
    /// The arguments of each streamed call, in order.
    var calls: [[String]] { streamCalls.map(\.args) }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

    /// Not `doctor`: no fake here needs to answer on the diagnostics stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) {
        (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.lock()
        _streamCalls.append(StreamCall(launch: launchPath, args: args, env: env))
        _exits.append(onExit)
        lock.unlock()
        return NoProcess()
    }

    /// Lets the operations in flight finish, the way a `brew` that has run to
    /// completion would.
    func finishAll(code: Int32 = 0) {
        lock.lock(); let exits = _exits; _exits = []; lock.unlock()
        for exit in exits { exit(code) }
    }
}
