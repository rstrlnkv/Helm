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
        /// The tool's own status, or `timedOutStatus` or -1 when it never
        /// answered. A tool that exits 0 stays 0 whatever it wrote.
        public let status: Int32
        /// What the tool wrote to stdout. Bytes that are not UTF-8 arrive as
        /// U+FFFD and the rest of the text is kept: the output is never replaced
        /// by `""` because of one bad byte, and the status never says the bytes
        /// were unreadable.
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
    ///
    /// It bounds the tools `run` and `runData` have out. `start` takes no slot:
    /// the child it launches belongs to its caller and outlives the call, so a
    /// slot taken there would have nobody to give it back. A slot is held until
    /// the tool *and* whatever else holds its pipe are gone; a run that timed
    /// out also gives it back as it returns if the tool is reaped by then and
    /// its group empty, and otherwise the slot outlives the moment `run`
    /// returns.
    public static let launchCeiling = 8

    /// The slots, and the count for a test to read.
    ///
    /// A bounded run waits for its slot only until its own deadline. Nothing
    /// here can deadlock on itself: a thread holding a slot is reading a tool's
    /// output, waiting for that read, signalling the tool's group or waiting for
    /// the tool to be reaped, not running code that could ask for a second one.
    private static let slots = DispatchSemaphore(value: launchCeiling)
    private static let live = LiveLaunches()
    private static let sent = SignalLog()

    /// The most tools that were out at once since the last reading. A test seam:
    /// a cap is a claim about what happens under load, and load is the only way
    /// to read it back.
    static func peakLaunchesForTesting() -> Int { live.peak() }

    /// The signals this file sent to a timed-out tool since the last reading,
    /// no more than the last `SignalLog` keeps, as the process group each was
    /// addressed to and the signal. A test seam: a signal sent to a pid that is
    /// not the tool's leaves no trace in the tool.
    static func signalsSentForTesting() -> [(group: pid_t, signal: Int32)] { sent.take() }

    /// The status of a run whose deadline passed before the tool answered.
    ///
    /// A named constant, because whoever reads it has to tell a timeout from a
    /// failure: every Homebrew query turns an empty answer into an empty list,
    /// and "brew is hung" shown as "no packages installed" is a lie about the
    /// machine. Distinguishable from anything a child can produce — exit codes
    /// are 0…255, a signal death reports the signal number, and -1 here already
    /// means the spawn itself failed.
    public static let timedOutStatus: Int32 = -2

    /// How long a bounded run waits for the reap after it sent KILL, so that
    /// it can tell a group that is empty from one that is only dying.
    private static let settleAfterKill: TimeInterval = 0.1

    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil) -> Result {
        let r = runData(path, arguments, env: env, deadline: nil)
        return Result(status: r.status, output: text(r.output))
    }

    /// The bytes as text, with U+FFFD where they are not UTF-8.
    ///
    /// The failable `String(data:encoding:)` answers nil for the whole of the
    /// output because of one bad byte, and the `?? ""` it needed made a tool
    /// that said something read as a tool that said nothing — which a caller
    /// turns into "no packages" or "no extensions". The decoding initializer
    /// never fails, so the rule that warns about it is switched off here.
    private static func text(_ data: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)
    }

    /// The same run, bounded. The `timeout` counts from the call, the wait for
    /// a slot included: a run that has no slot by then answers `timedOutStatus`
    /// without starting the tool, and one that does start gets what is left. A
    /// tool that has not closed its output and exited by then is terminated with
    /// its process group — TERM to the group, then KILL to it after a two-second
    /// grace if the output is still held or the tool not yet reaped — and the
    /// result is `timedOutStatus` with no output, even when the tool had
    /// already closed its output: it has no status of its own to report until it
    /// exits, and what it wrote is the answer of a tool that did not finish. A
    /// hung `brew` waiting on another brew's lock otherwise parks the calling
    /// thread for the life of the process, and everything behind it queues. A
    /// process the tool started
    /// in a group of its own is not reached; `signalTree` says what that leaves.
    /// The caller is back within the timeout and the grace, and within
    /// `settleAfterKill` more when a KILL was sent; the slot comes back when the
    /// tool and whatever else holds its pipe are gone, or as the run returns if
    /// the tool is then reaped and its group empty.
    @discardableResult
    public static func run(_ path: String,
                           _ arguments: [String],
                           env: [String: String]? = nil,
                           timeout: TimeInterval) -> Result {
        let r = runData(path, arguments, env: env, deadline: timeout)
        return Result(status: r.status, output: text(r.output))
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

    /// Stderr is discarded, not merged: a tool's diagnostics are not its output,
    /// and every caller here parses what it gets.
    ///
    /// `nullDevice`, not a `Pipe()`. A pipe nobody reads holds about 64 KB
    /// and then blocks the child in `write(2)` — so it never exits, never
    /// closes stdout, and the read below never returns. That is the same
    /// deadlock this function reads-before-waiting to avoid on the stdout
    /// side, reintroduced on the other one. A `brew` command with a
    /// deprecation warning per formula reaches 64 KB easily, and the caller
    /// is parked for the life of the process with an orphan child blocked
    /// behind it. Discarding means sending it nowhere, not sending it
    /// somewhere with no reader.
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
        // Discarded: see the doc comment above.
        process.standardError = FileHandle.nullDevice

        // Counted down by the termination handler, which Foundation runs once
        // the child is reaped, or by the failed launch below; the caller and
        // the helper thread below both wait for it.
        let reaped = Reaped()
        process.terminationHandler = { _ in reaped.leave() }

        // The deadline counts from here: waiting for a slot is waiting, and a
        // caller that said "no more than ten seconds" is owed an answer in ten.
        let asked = DispatchTime.now()
        let cutoff = deadline.map { asked + $0 }

        // The slot is taken around the whole run and given back on every way
        // out — the failed launch below included, which is the one path a
        // `defer` written next to `wait()` would still have covered and a
        // hand-balanced release would not. The one way out that does not give
        // it is a timeout, which hands it to the helper thread below unless the
        // tool is then reaped and its group empty.
        if let cutoff {
            guard slots.wait(timeout: cutoff) == .success else { return (timedOutStatus, Data()) }
        } else {
            slots.wait()
        }
        live.entered()
        let slot = Slot()
        var slotIsTheHelpers = false
        defer { if !slotIsTheHelpers { slot.give() } }

        guard launched(process, path) else {
            reaped.leave()
            return (-1, Data())
        }

        guard let cutoff else {
            // Read first. This returns when the child closes stdout, which is
            // what makes the wait below immediate rather than a poll.
            let data = out.fileHandleForReading.readDataToEndOfFile()
            reaped.wait()
            return (process.terminationStatus, data)
        }

        // Bounded: the read happens on a helper thread so this one can stop
        // waiting for it. The same read-then-wait order as above — EOF first,
        // the wait for the reap after, which has the deadline too: a tool can
        // close its output and keep running. The helper is also who gives the slot back
        // after a timeout, once the pipe is closed and the child is reaped:
        // until then a tool of the tree is still out. What holds the pipe
        // outside the group is not a tool Helm can end, so the run itself gives
        // the slot back as it returns if by then the tool is reaped and nothing
        // of the group is left.
        let box = DataBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(out.fileHandleForReading.readDataToEndOfFile())
            readDone.signal()
            reaped.wait()
            slot.give()
        }
        let read = readDone.wait(timeout: cutoff) == .success
        if !(read && reaped.wait(timeout: cutoff) == .success) {
            slotIsTheHelpers = true
            // Something of the tree is alive: the pipe is still held, or the
            // tool closed it and has not exited. TERM goes to the whole group;
            // a tool that traps it to clean up gets its grace, and one that
            // ignores it, or leaves a child that does, does not get to keep the
            // machine.
            let group = process.processIdentifier
            signalTree(group, SIGTERM, reaped: reaped.isDone)
            let graceEnd = DispatchTime.now() + 2
            let pipeClosed = read || readDone.wait(timeout: graceEnd) == .success
            var childGone = reaped.wait(timeout: graceEnd) == .success
            if !(pipeClosed && childGone) {
                signalTree(group, SIGKILL, reaped: childGone)
                childGone = childGone || reaped.wait(timeout: .now() + settleAfterKill) == .success
            }
            if childGone && groupIsEmpty(group) { slot.give() }
            return (timedOutStatus, Data())
        }
        return (process.terminationStatus, box.take())
    }

    /// **Ending a timed-out tool and what it started, without a stray signal.**
    ///
    /// The tool's process group, not its pid. Foundation spawns each child as
    /// the leader of a group of its own — measured on this macOS: the child's
    /// group id was its pid, in the parent's session, and a grandchild had the
    /// same group id — so a signal to the group reaches the child and
    /// everything it forked, including the grandchild that holds the pipe
    /// after the child is dead. A pid is another matter: Foundation reaps the
    /// child on its own schedule and tells this code afterwards, so the
    /// number may be free, and given to somebody else's process, by the time
    /// a `kill` to it is made. A group id is not given out while any process
    /// is still in the group, so a signal to a group that still has a member
    /// lands on the tool's tree.
    ///
    /// Once the child is reaped, a process numbered like the group means the
    /// number has been issued again, which happens only after the original
    /// group emptied: any group with that number is then someone else's, so
    /// nothing is sent and the log says so. That line is not expected on an
    /// ordinary machine: it needs the pid counter to go round while the pipe is
    /// held for the length of a timeout and a grace.
    ///
    /// What is left. A signal reaches somebody else's group only if this number
    /// has been given out again: macOS hands out pids in order and skips a
    /// number still in use as a group id (recalled from the kernel source, not
    /// measured), so that needs the group emptied and the counter gone through
    /// every other number since the child was spawned, within the timeout and
    /// the grace. A process of the tree that left the group (`setsid`,
    /// `setpgid`) is not reached; while it holds the pipe the group may already
    /// be empty when TERM and KILL are sent, which then find nobody (`ESRCH`).
    /// If a future Foundation stops making the child a group leader, the group
    /// does not exist and the call finds nobody (`ESRCH`); it never reaches
    /// Helm's own group, because a group id equal to a live process's pid is
    /// that process's own group.
    private static func signalTree(_ group: pid_t, _ signal: Int32, reaped: Bool) {
        guard group > 1 else { return }
        if reaped && (kill(group, 0) == 0 || errno == EPERM) {
            HelmLog.shared.warn("process", "no signal sent: the number of a timed-out tool's group is in use again")
            return
        }
        sent.add(group, signal)
        killpg(group, signal)
    }

    /// Whether nothing is left in the group: `killpg` with signal 0 sends
    /// nothing and answers `ESRCH` for a group with no member. A group that
    /// still answers is left to the helper thread, which gives the slot back
    /// once the pipe is closed.
    private static func groupIsEmpty(_ group: pid_t) -> Bool {
        group > 1 && killpg(group, 0) == -1 && errno == ESRCH
    }

    /// Start a child this caller owns, through the same door.
    ///
    /// **It takes no slot of `launchCeiling`**, and it has no deadline: it
    /// returns once the child is launched and never learns when the child
    /// ends, so a slot taken here would have no owner to give it back.
    ///
    /// `run` and `runData` read a child to EOF, discard its stderr and wait for
    /// its status, and the callers of `start` cannot use that: the updater's
    /// swap script waits for *this* process to exit before it does any work,
    /// Homebrew's `stream` hands its child's output to a console line by line
    /// and returns while the child runs, and `runCapturingDiagnostics` wants
    /// stderr and stdout on one pipe. A bare `try process.run()` in any of them
    /// is the spelling that aborts the app: `NSTask` raises an Objective-C
    /// exception on some launch paths and a Swift `catch` cannot see it.
    ///
    /// False rather than a throw, because the refusal is already logged here
    /// and a caller that owns the process owns what to do about it — the
    /// updater has a hand-over note to take back, the streaming port has a
    /// page to tell, and the diagnostics capture answers `-1`.
    public static func start(_ process: Process, path: String) -> Bool {
        launched(process, path)
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

    /// A slot is held from the moment a run takes it until it is given back,
    /// which for a run that timed out may be after the run returned.
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

    /// One slot, given back at most once: the run gives it on every way out but
    /// a timeout, and on a timeout only when the tool is reaped and its group
    /// empty; on a bounded run the helper thread gives it once the pipe is
    /// closed and the child reaped, so on a bounded run that answers in time
    /// both are there to do it.
    private final class Slot: @unchecked Sendable {
        private let lock = NSLock()
        private var held = true

        func give() {
            lock.lock(); let wasHeld = held; held = false; lock.unlock()
            guard wasHeld else { return }
            live.left()
            slots.signal()
        }
    }

    /// What `signalsSentForTesting` reads back. Nothing but a test reads it, so
    /// it keeps only the last `kept` entries: the shipping app adds one for
    /// every signal it sends to a timed-out tool, for as long as it runs.
    private final class SignalLog: @unchecked Sendable {
        private static let kept = 16
        private let lock = NSLock()
        private var list: [(group: pid_t, signal: Int32)] = []

        func add(_ group: pid_t, _ signal: Int32) {
            lock.lock()
            list.append((group, signal))
            if list.count > Self.kept { list.removeFirst(list.count - Self.kept) }
            lock.unlock()
        }
        /// Reads and clears, as `LiveLaunches.peak` does.
        func take() -> [(group: pid_t, signal: Int32)] {
            lock.lock(); defer { list = []; lock.unlock() }; return list
        }
    }

    /// The child's reaping, counted down once whichever of the termination
    /// handler and the failed launch gets there first: a second `leave` on a
    /// `DispatchGroup` traps.
    private final class Reaped: @unchecked Sendable {
        private let group = DispatchGroup()
        private let lock = NSLock()
        private var pending = true

        init() { group.enter() }

        func leave() {
            lock.lock(); let wasPending = pending; pending = false; lock.unlock()
            if wasPending { group.leave() }
        }
        func wait() { group.wait() }
        func wait(timeout: DispatchTime) -> DispatchTimeoutResult { group.wait(timeout: timeout) }
        var isDone: Bool { group.wait(timeout: .now()) == .success }
    }

    /// Carries the read bytes from the helper thread to whoever reports them.
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func take() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
