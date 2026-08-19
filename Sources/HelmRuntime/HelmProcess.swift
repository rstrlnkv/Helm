import Foundation
import HelmLaunch

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

    /// **How many tools Helm will have out at once.**
    ///
    /// Nothing bounded this, and nothing in the app asked to: the bound existed
    /// because no screen had ever started more than a few. Homebrew's search
    /// field put every press of Return on its own unbounded `Task`, and each
    /// press is two `brew search` runs of about nine seconds followed by a
    /// `brew desc` per kind — so ten presses were twenty-odd Ruby processes and
    /// the thread that started the twenty-first is the one in the crash report.
    ///
    /// The `LatestRequest` that now sits in `HomebrewViewModel` stops that
    /// particular screen from asking. This is the floor under every screen that
    /// has not been written yet: a caller may still ask for more than eight, and
    /// what it gets is a queue rather than eight more processes.
    ///
    /// Eight, and it is a ceiling on *concurrency* rather than a guess at what
    /// the machine can take. These are subprocesses that spend their time
    /// waiting on a network or a disk, so the useful number is not the core
    /// count; what matters is that it is small, fixed, and far below the point
    /// where a page can exhaust anything.
    public static let launchCeiling = 8

    /// The slots, and the count for a test to read.
    ///
    /// A semaphore rather than a queue of work: `runData` already blocks its own
    /// thread for the life of the child by design — every caller is on a queue
    /// of its own that expects to wait — so waiting for a slot is the same kind
    /// of wait it was already doing. Nothing here can deadlock on itself: a
    /// thread holding a slot is inside `readDataToEndOfFile`, not running code
    /// that could ask for a second one.
    private static let slots = DispatchSemaphore(value: launchCeiling)
    private static let live = LiveLaunches()

    /// The most tools that were out at once since the last reading. A test seam:
    /// a cap is a claim about what happens under load, and load is the only way
    /// to read it back.
    static func peakLaunchesForTesting() -> Int { live.peak() }

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

        // The slot is taken around the whole run and given back on every way
        // out — the failed launch below included, which is the one path a
        // `defer` written next to `wait()` would still have covered and a
        // hand-balanced release would not.
        slots.wait()
        live.entered()
        defer { live.left(); slots.signal() }

        guard launched(process, path) else { return (-1, Data()) }

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

    /// **Starting the child, through the one door that cannot kill the app.**
    ///
    /// This was `do { try process.run() } catch { … }`, and for one class of
    /// refusal that guard could not fire: `NSTask` raises an Objective-C
    /// exception on some launch paths, which goes past a Swift `catch` into
    /// `std::terminate`. A build shipped and died with SIGABRT inside
    /// `-[NSConcreteTask launchWithDictionary:error:]`, from a Homebrew page
    /// that had twenty tools out at once. `HelmLaunch.h` carries what was
    /// measured about which paths raise and which return.
    ///
    /// The refusal is **logged rather than swallowed**. `-1` was already the
    /// answer for a spawn that failed and stays it — every caller reads a status
    /// — but a launch Helm's own arguments were refused for is a defect in Helm,
    /// and the only place it could be seen is the log. The path is redacted for
    /// the same reason every path in this log is; the exception's name is a
    /// Foundation constant and carries nothing of anybody's.
    private static func launched(_ process: Process, _ path: String) -> Bool {
        var failure: NSError?
        if HelmLaunchTask(process, &failure) { return true }
        let name = failure?.userInfo[HelmLaunchExceptionNameKey] as? String
        HelmLog.shared.warn("process", "could not start \(Redact.path(path))"
            + (name.map { ": raised \($0)" } ?? ""))
        return false
    }

    /// How many runs are in flight, and the most there have ever been at once.
    ///
    /// Its own object rather than two `static var`s because it is touched from
    /// every thread that runs a tool: an unguarded pair would be the race this
    /// class of code exists to avoid, in the counter that measures it.
    private final class LiveLaunches: @unchecked Sendable {
        private let lock = NSLock()
        private var now = 0
        private var most = 0

        func entered() {
            lock.lock(); now += 1; most = max(most, now); lock.unlock()
        }
        func left() { lock.lock(); now -= 1; lock.unlock() }
        /// Reads the peak **and clears it**, so one test's load cannot be read
        /// back by the next one as its own.
        func peak() -> Int {
            lock.lock(); defer { most = 0; lock.unlock() }; return most
        }
    }

    /// Carries the read bytes from the helper thread to whoever reports them.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func take() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
