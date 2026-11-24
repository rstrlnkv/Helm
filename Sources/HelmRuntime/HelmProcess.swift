import Foundation
import HelmLaunch

/// The one way Helm runs a command-line tool. Architecture/RunningOtherPrograms.md § Running other programs.
///
/// **Order.** Output is read to the end before the wait. A child whose output
/// exceeds the pipe buffer blocks on the write while a parent waiting first
/// blocks on the wait, and neither ever finishes.
///
/// **The wait itself.** `Process.waitUntilExit()` polls a run loop in 50 ms
/// steps, so every call pays tens of milliseconds whether or not the child has
/// finished. Reading to EOF already proves the child closed its output; the
/// termination handler supplies the status without the poll.
public enum HelmProcess {
    /// Where a tool's standard error goes. `discarded` for every parsed query;
    /// `merged` only for the one caller whose whole answer is a diagnostic
    /// (Homebrew's `brew doctor`).
    public enum StandardError: Sendable {
        case discarded
        case merged
    }

    public struct Result: Sendable {
        public let status: Int32
        public let output: String
        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }
    }

    /// **How many tools `run` and `runData` will have out at once.**
    ///
    /// A repeatedly pressable control can start tools faster than they finish
    /// (a Homebrew search is several Ruby processes of seconds each), and enough
    /// of them at once crash the launch itself. A screen should not ask
    /// (`SharedLatestRequest`); this is the floor under every screen that goes
    /// through `run` or `runData`: a caller asking for more gets a queue rather
    /// than more processes. **`start` takes no slot**, so a tool launched
    /// through it (Homebrew's streamed runs, the updater's swap) is not counted
    /// and not held back.
    ///
    /// A ceiling on *concurrency*, not a guess at what the machine can take:
    /// these tools wait on a network or a disk, so the core count is not the
    /// useful number. Small, fixed, and far below what a page can exhaust.
    static let launchCeiling = 8

    /// The slots, and the count for a test to read.
    ///
    /// A semaphore rather than a queue of work: `runData` already blocks its own
    /// thread for the life of the child, so waiting for a slot is the same kind
    /// of wait. It cannot deadlock on itself: a thread holding a slot is inside
    /// `readDataToEndOfFile`, not running code that could ask for a second one.
    private static let slots = DispatchSemaphore(value: launchCeiling)
    private static let live = LiveLaunches()

    /// The most tools that were out at once since the last reading. A test seam:
    /// a cap is a claim about what happens under load, and load is the only way
    /// to read it back.
    static func peakLaunchesForTesting() -> Int { live.peak() }

    /// The status of a run whose deadline passed before the tool answered.
    ///
    /// A named constant, because whoever reads it has to tell a timeout from a
    /// failure: "brew is hung" shown as "no packages installed" is a lie about
    /// the machine. Distinguishable from anything a child can produce: exit
    /// codes are 0…255, a signal death reports the signal number, and -1 means
    /// the spawn itself failed.
    public static let timedOutStatus: Int32 = -2

    /// The most arguments one launch takes, the executable path not counted.
    /// `NSTask` raises `NSInvalidArgumentException` ("too many arguments (N) --
    /// limit is 4096") past it, and `HelmLaunchTask` turns that into status -1.
    /// It is `NSTask`'s own count limit, not `ARG_MAX` bytes. Here because this
    /// type owns launching; a caller whose argv grows with the data cuts its
    /// list by it.
    public static let maxArguments = 4096

    /// A run with no `timeout` waits for the tool as long as it takes. With one,
    /// a tool that has not closed its output by then is terminated (TERM, then
    /// KILL after a two-second grace for tools that trap it) and the result is
    /// `timedOutStatus` with no output. Without one, a hung `brew` waiting on
    /// another brew's lock parks the calling thread for the life of the process.
    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil,
                           timeout: TimeInterval? = nil) -> Result {
        let r = runData(path, arguments, env: env, deadline: timeout)
        return Result(status: r.status, output: String(data: r.output, encoding: .utf8) ?? "")
    }

    /// The bytes themselves, for a caller whose parser wants `Data`: a JSON
    /// decode routed through `run` pays for a String it never reads, and the
    /// round-trip holds both copies at the peak.
    ///
    /// `standardError: .merged` points stderr at the same pipe as stdout, in
    /// write order; the deadline, TERM, grace and KILL are the same.
    public static func runData(_ path: String,
                               _ arguments: [String],
                               env: [String: String]? = nil,
                               timeout: TimeInterval,
                               standardError: StandardError = .discarded) -> (status: Int32, output: Data) {
        runData(path, arguments, env: env, deadline: timeout, standardError: standardError)
    }

    /// Stderr is discarded unless the one merged caller asks: a tool's
    /// diagnostics are not its output, and every other caller parses what it gets.
    ///
    /// `nullDevice`, not a `Pipe()`. A pipe nobody reads holds about 64 KB
    /// and then blocks the child in `write(2)`, so it never closes stdout and
    /// the read below never returns: the read-before-wait deadlock on the other
    /// side. A `brew` warning per formula reaches 64 KB easily.
    private static func runData(_ path: String,
                                _ arguments: [String],
                                env: [String: String]?,
                                deadline: TimeInterval?,
                                standardError: StandardError = .discarded) -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let env {
            var merged = ProcessInfo.processInfo.environment
            merged.merge(env) { _, new in new }
            process.environment = merged
        }

        let out = Pipe()
        process.standardOutput = out
        // Discarded unless merged into the same, read pipe: see the doc comment above.
        process.standardError = standardError == .merged ? out : FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        // The slot is taken around the whole run and given back on every way
        // out, the failed launch below included.
        slots.wait()
        live.entered()
        defer { live.left(); slots.signal() }

        guard start(process, path: path) else { return (-1, Data()) }

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
    /// `try process.run()` cannot guard every refusal: `NSTask` raises an
    /// Objective-C exception on some launch paths, which goes past a Swift
    /// `catch` into `std::terminate`. `HelmLaunch.h` says which paths raise.
    ///
    /// The refusal is **logged rather than swallowed**: a launch Helm's own
    /// arguments were refused for is a defect in Helm, and the log is the only
    /// place it shows. The path is redacted; the exception's name is a
    /// Foundation constant.
    ///
    /// Public for a caller whose child outlives the call (the updater's swap
    /// script, Homebrew's streaming port), which cannot use `run` or `runData`.
    /// False rather than a throw, because the refusal is already logged and the
    /// caller that owns the process owns what to do about it.
    public static func start(_ process: Process, path: String) -> Bool {
        var failure: NSError?
        if HelmLaunchTask(process, &failure) { return true }
        let name = failure?.userInfo[HelmLaunchExceptionNameKey] as? String
        HelmLog.shared.warn("process", "could not start \(Redact.path(path))"
            + (name.map { ": raised \($0)" } ?? ""))
        return false
    }

    /// How many runs are in flight, and the most there have ever been at once.
    ///
    /// Its own locked object rather than two `static var`s, because it is
    /// touched from every thread that runs a tool.
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
