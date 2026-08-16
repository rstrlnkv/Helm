import Foundation

/// The one way Helm runs a command-line tool.
///
/// There were five of these, and they disagreed on the two things that matter.
///
/// **Order.** Two of them called `waitUntilExit()` *before* reading the pipe. A
/// child whose output exceeds the pipe buffer blocks on the write while the
/// parent blocks on the wait, and neither ever finishes. The outputs happen to
/// be short today; the pattern was there to be copied.
///
/// **The wait itself.** `Process.waitUntilExit()` polls a run loop in 50 ms
/// steps, so every call paid about 67 ms whether or not the child had already
/// finished — measured at 70.6 ms for `/usr/bin/true` against 1.3 ms for a bare
/// spawn. `Leftovers` ran three tools per scan and spent two thirds of the scan
/// inside that poll. Reading to EOF already proves the child closed its output;
/// the termination handler supplies the status without the poll.
public enum HelmProcess {
    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// The status of a run whose deadline passed before the tool answered.
    ///
    /// A named constant, because whoever reads it has to tell a timeout from a
    /// failure: every Homebrew query turns an empty answer into an empty list,
    /// and "brew is hung" shown as "no packages installed" is a lie about the
    /// machine. Distinguishable from anything a child can produce — exit codes
    /// are 0…255, a signal death reports the signal number, and -1 here already
    /// means the spawn itself failed.
    public static let timedOutStatus: Int32 = -2

    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil) -> Result {
        let r = runData(path, arguments, env: env, deadline: nil)
        return Result(status: r.status, output: String(data: r.output, encoding: .utf8) ?? "")
    }

    /// The same run, bounded. A tool that has not closed its output by
    /// `timeout` is terminated (TERM, then KILL after a two-second grace for
    /// tools that trap it) and the result is `timedOutStatus` with no output —
    /// a hung `brew` waiting on another brew's lock otherwise parks the calling
    /// thread for the life of the process, and everything behind it queues.
    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil,
                           timeout: TimeInterval) -> Result {
        let r = runData(path, arguments, env: env, deadline: timeout)
        return Result(status: r.status, output: String(data: r.output, encoding: .utf8) ?? "")
    }

    /// The bytes themselves, for a caller whose parser wants `Data` — a JSON
    /// decode routed through `run` pays a String it never reads: the bytes were
    /// already here, became a String on return, and were copied straight back
    /// into `Data` at the call site. Measured on `outdated()` at 13 MB of
    /// payload: 79–80 MB held at peak through the String round-trip, 50–51 MB
    /// handing the bytes through (`OutdatedQueryAllocationBenchmark`).
    public static func runData(_ path: String,
                               _ arguments: [String],
                               env: [String: String]? = nil,
                               timeout: TimeInterval) -> (status: Int32, output: Data) {
        runData(path, arguments, env: env, deadline: timeout)
    }

    private static func runData(_ path: String,
                                _ arguments: [String],
                                env: [String: String]?,
                                deadline: TimeInterval?) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in env { merged[key] = value }
            process.environment = merged
        }

        let out = Pipe()
        process.standardOutput = out
        // Discarded, not merged: a tool's diagnostics are not its output, and
        // every caller here parses what it gets.
        //
        // `nullDevice`, not a `Pipe()`. A pipe nobody reads holds about 64 KB
        // and then blocks the child in `write(2)` — so it never exits, never
        // closes stdout, and the read below never returns. That is the same
        // deadlock this function reads-before-waiting to avoid on the stdout
        // side, reintroduced on the other one. A `brew` command with a
        // deprecation warning per formula reaches 64 KB easily, and the caller
        // is parked for the life of the process with an orphan child blocked
        // behind it. Discarding means sending it nowhere, not sending it
        // somewhere with no reader.
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do { try process.run() } catch { return (-1, Data()) }

        guard let deadline else {
            // Read first. This returns when the child closes stdout, which is
            // what makes the wait below immediate rather than a poll.
            let data = out.fileHandleForReading.readDataToEndOfFile()
            finished.wait()
            return (process.terminationStatus, data)
        }

        // Bounded: the read happens on a helper thread so this one can stop
        // waiting for it. The same read-then-wait order as above — EOF first,
        // immediate wait after.
        let box = DataBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(out.fileHandleForReading.readDataToEndOfFile())
            readDone.signal()
        }
        if readDone.wait(timeout: .now() + deadline) == .timedOut {
            process.terminate()
            // A tool that traps TERM to clean up gets its grace; one that
            // ignores it does not get to keep the machine.
            if readDone.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            // The helper thread unblocks when the dead child's pipe closes; a
            // grandchild still holding the write end can delay that, which
            // parks the helper, not this caller.
            return (timedOutStatus, Data())
        }
        finished.wait()
        return (process.terminationStatus, box.take())
    }

    /// Carries the read bytes from the helper thread to whoever reports them.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func take() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
