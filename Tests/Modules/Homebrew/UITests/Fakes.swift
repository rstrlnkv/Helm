import Foundation
import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

// The `ProcessRunner` and `PrivilegedRunner` fakes the Homebrew model tests share,
// beside `FakeHomebrewWork`. A fake keeps its port's states only, and every
// construction names the port it stands in for (`runner:`, `privileged:`)
// (Architecture/TestsAndMeasurement.md § Fakes).

/// The password dialog answered no: nothing ran.
struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

/// The one `ProcessRunner` the model tests stand on, set up by what the test passes.
/// Every query is written down and answered with status 0 and `answer(args)` (nothing
/// by default); a streamed child ends at once, or with `hangingStreams` never does and
/// its handle is kept, because a Stop that races a stream already over proves nothing.
/// `park` holds the query it names inside the tool until `release()`, after `parked`
/// has been fulfilled on the runner's own thread, so the test knows the query is in
/// flight. A real semaphore, because a cooperative yield buys no wall-clock time and
/// cannot hold a query open across a second press, a departure or a gesture.
/// `runCapturingDiagnostics` answers status 0 and nothing.
final class FakeBrew: ProcessRunner, @unchecked Sendable {
    struct Call: Equatable {
        let kind: String
        let launchPath: String
        let args: [String]
        let env: [String: String]
    }

    /// A streamed child that never ends by itself; `terminated` says whether Stop reached it.
    final class HangingChild: RunningProcess, @unchecked Sendable {
        private let lock = NSLock()
        private var _terminated = false
        var terminated: Bool { lock.withLock { _terminated } }
        func terminate() { lock.withLock { _terminated = true } }
    }

    let parked = XCTestExpectation(description: "the parked query reached brew")
    private let held = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var _handles: [HangingChild] = []
    private let answer: @Sendable ([String]) -> String
    private let park: (@Sendable ([String]) -> Bool)?
    private let hangingStreams: Bool

    init(answer: @escaping @Sendable ([String]) -> String = { _ in "" },
         park: (@Sendable ([String]) -> Bool)? = nil,
         hangingStreams: Bool = false) {
        self.answer = answer
        self.park = park
        self.hangingStreams = hangingStreams
    }

    /// A `brew` that answers `uses <name>` from a table and, with `park`, holds the query for that name.
    convenience init(uses table: [String: String], park parked: String? = nil) {
        let answer: @Sendable ([String]) -> String = { args in
            guard args.first == "uses", let name = args.last else { return "" }
            return table[name] ?? ""
        }
        guard let parked else { self.init(answer: answer); return }
        self.init(answer: answer, park: { args in args.first == "uses" && args.last == parked })
    }

    var calls: [Call] { lock.withLock { recorded } }
    var handles: [HangingChild] { lock.withLock { _handles } }

    /// Lets the parked query answer at last.
    func release() { held.signal() }

    private func note(_ kind: String, _ path: String, _ args: [String], _ env: [String: String]) {
        lock.withLock { recorded.append(Call(kind: kind, launchPath: path, args: args, env: env)) }
    }

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        note("run", launchPath, args, env)
        if park?(args) == true {
            parked.fulfill()
            held.wait()
        }
        return (0, answer(args))
    }

    func runData(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: Data) {
        note("runData", launchPath, args, env)
        return (0, Data(answer(args).utf8))
    }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        note("runCapturingDiagnostics", launchPath, args, env)
        return (0, "")
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        note("stream", launchPath, args, env)
        guard hangingStreams else {
            onExit(0)
            return NoProcess()
        }
        let child = HangingChild()
        lock.withLock { _handles.append(child) }
        return child
    }
}
