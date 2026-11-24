import Foundation
import HelmRuntime

/// Where `brew` is, read off the disk at every call. nil when there is no
/// executable `brew` at either prefix: never installed, or removed since.
public protocol BrewLocator: Sendable {
    func brewPath() -> String?
}

/// What a caller can still do to a process it started: end it. Terminating is
/// not finishing — the child dies, *then* the pipe closes and `onExit` lands,
/// exactly as when it exits on its own.
public protocol RunningProcess: Sendable {
    func terminate()
}

/// How far a Stop reaches from the process a stream launched.
///
/// **`.process` is `Process.terminate()`, and that is not "one TERM to the
/// child".** On Darwin it signals the child's whole process group, where
/// `kill(pid, SIGTERM)` leaves a member alive. It is what a `brew` operation
/// gets: a `curl` or `git` brew started in that group goes with it. A member
/// that moved into a group of its own is not reached. It is signalled once.
///
/// **`.wholeGroup` is the same reach, checked and repeated**: `killpg` on the
/// child's group, only while the child leads it, and again 0.1 s and 0.4 s
/// later while the child is still there. It is for a shell running programs
/// in the foreground: a TERM that lands between the shell's last check and the
/// `fork` of a program never sees the program, and the repeat finds it.
public enum StopReach: Sendable {
    case process
    case wholeGroup
}

/// A handle with nothing behind it: a stream that failed to spawn, or a fake
/// whose child has no process. Terminating it does nothing, which is all there
/// is to do.
struct NoProcess: RunningProcess {
    init() {}
    func terminate() {}
}

public protocol ProcessRunner: Sendable {
    /// Run to completion, capturing stdout (stderr goes to the null device). Blocking, and
    /// bounded: past the runner's deadline the answer is
    /// `HelmProcess.timedOutStatus`, never a wait without end.
    func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String)
    /// The same run, bytes untouched, for a parser that wants `Data`. A
    /// requirement, not only an extension: the engine holds the runner as an
    /// existential, and an extension-only method would dispatch every real call
    /// to the copying default below.
    func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data)
    /// Stream a long-running process: `onLine` per output line, `onExit` at the
    /// end. The handle is the only way to end a brew that will not — an
    /// operation has no deadline, because an install may honestly take an hour.
    @discardableResult
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess
    /// The same stream with the Stop's reach named. The default below ignores
    /// `reach`, which is right for a fake with no process. The real runner's
    /// unnamed form is `.wholeGroup`, the reach that leaves nothing behind.
    @discardableResult
    func stream(_ launchPath: String, _ args: [String], env: [String: String], reach: StopReach,
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess

    /// Standard output and standard error together, in the order the child
    /// wrote them, for `brew doctor`, whose whole answer is on standard error
    /// (`ShellProcessRunner.runCapturingDiagnostics`).
    ///
    /// **No default implementation.** One that fell back to `run` would let
    /// every fake pass while the live path went silent on the one query that
    /// needs the other stream.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String)
}

extension ProcessRunner {
    @discardableResult
    func stream(_ launchPath: String, _ args: [String], env: [String: String], reach: StopReach,
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        stream(launchPath, args, env: env, onLine: onLine, onExit: onExit)
    }

    /// Correct for any fake that only speaks String — it pays the copy the
    /// real runner exists to avoid, which a test does not feel.
    func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data) {
        let r = run(launchPath, args, env: env)
        return (r.status, Data(r.stdout.utf8))
    }
}

public protocol PrivilegedRunner: Sendable {
    /// Run a shell script with administrator privileges via the native macOS
    /// password dialog (the user types the password).
    ///
    /// **Three answers, not two**, because Cancel is an ordinary end and not a
    /// failed `mkdir`: `.done`, `.declined` (the dialog was answered no — nothing ran), and
    /// `.failed(status)` (root was asked and the script itself failed). Blocking
    /// for as long as the dialog is up, so the caller is off the cooperative pool.
    func runAdmin(_ script: String) -> PrivilegedOutcome
}

/// What filing Apple's request for the Command Line Tools came to.
///
/// Three cases, because the three are acted on alike but *said* differently in
/// the log: a request that was filed and whose window is Apple's from here on,
/// one the tool refused with a status, and one that did not answer in time.
public enum ToolsRequest: Equatable, Sendable {
    case filed
    case refused(Int32)
    case timedOut
}

/// Apple's Command Line Tools as Homebrew's `install.sh` looks for them, and
/// Apple's own installer for them.
///
/// **Four questions, one per thing the engine must never guess.** None of them
/// is called under the engine's lock: `installerIsRunning` hops to the main
/// thread on the real port, and the main thread may be waiting for that lock.
public protocol CommandLineToolsPort: Sendable {
    /// Whether an executable file is at `path` — the fixed `git` test.
    func isExecutable(_ path: String) -> Bool
    /// `xcode-select -p`, or nil: no developer directory selected (exit 2), the
    /// deadline, a failed launch. All three mean "not by this route" and are
    /// not told apart, because the answer that follows is the same: the fixed
    /// path is asked first and this only widens the search.
    func selectedDeveloperDirectory() -> String?
    /// `/usr/bin/xcode-select --install`, under a deadline. It files the
    /// request; the window that follows is Apple's and opens later, on its own.
    func requestInstall() -> ToolsRequest
    /// Whether Apple's installer is running now. nil-free on purpose: a reading
    /// that cannot be taken says false, and the wait rules treat "never seen"
    /// as no evidence (`CommandLineTools.next`).
    func installerIsRunning() -> Bool
}

/// The safe default for an engine built without naming the tools port: the
/// tools are there, so nothing is asked of Apple and no process is started. A
/// forgetful test construction must not become `xcode-select` on the owner's Mac.
public struct ToolsAlreadyInstalled: CommandLineToolsPort {
    public init() {}
    public func isExecutable(_ path: String) -> Bool { true }
    public func selectedDeveloperDirectory() -> String? { nil }
    public func requestInstall() -> ToolsRequest { .filed }
    public func installerIsRunning() -> Bool { false }
}

/// One tick of the wait for Apple's installer, off the main thread; releasing
/// the token cancels it. The shape of Keep Awake's clock, with a queue that is
/// not main: what a tick continues into is a blocking password dialog.
public protocol WaitTicker: Sendable {
    func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject
}

/// The safe default: nothing is ever scheduled, so a wait that starts under it
/// never ticks. Only reachable from a construction that also left
/// `CommandLineToolsPort` at its default, which never starts a wait.
public struct NoWaitTicker: WaitTicker {
    public init() {}
    public func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        NSObject()
    }
}

/// Both halves of a reading, as one value.
///
/// **One call, because a search is one act.** A refresh may land while
/// `search` ranks both lists; in two calls they could be ranked against two
/// different readings. One value makes that straddle unrepresentable.
public struct PopularityReadings: Sendable, Equatable {
    let formulae: InstallCounts
    let casks: InstallCounts
    init(formulae: InstallCounts, casks: InstallCounts) {
        self.formulae = formulae
        self.casks = casks
    }
    /// No reading of either kind: a first launch, a refused fetch, a Mac with
    /// no network. Search orders results exactly as it does with no counts at
    /// all, which is brew's own order.
    static let none = PopularityReadings(formulae: .none, casks: .none)
}

/// Homebrew's published install counts, as this process last managed to read
/// them.
///
/// Synchronous on purpose: `search` asks this between two `brew` runs, so it
/// answers from what is in hand. The asking that can block is `refreshIfDue`,
/// run once per activation, which answers nothing.
public protocol PopularityReading: Sendable {
    func readings() -> PopularityReadings
    /// Fetch if the stored readings are old enough to be worth replacing. Never
    /// fails loudly: a refusal leaves whatever was already there.
    func refreshIfDue() async
}

/// The safe default for an engine built without naming a store: no readings and
/// no network. A forgetful construction must not reach outside this process.
public struct NoPopularity: PopularityReading {
    public init() {}
    public func readings() -> PopularityReadings { .none }
    public func refreshIfDue() async {}
}

/// Remembers the operation that is running, across a quit.
///
/// A child brew survives Helm, and killing it would be worse: a build
/// interrupted halfway is how broken Cellar state is made. So the running
/// operation writes its label, a finished one clears it, and whatever is still
/// written at the next launch is the report.
public protocol OpMarker: Sendable {
    func write(_ label: String)
    func clear()
    /// The label an unfinished operation left, cleared by the read — the
    /// report is made once, not on every status query.
    func take() -> String?
}

/// The safe default for an engine built without naming a marker: it remembers
/// for the object's life and touches no file — a forgetful test construction
/// must not become an integration test against somebody's Application Support.
public final class InMemoryOpMarker: OpMarker, @unchecked Sendable {
    private let lock = NSLock()
    private var label: String?
    public init() {}
    public func write(_ label: String) { lock.lock(); self.label = label; lock.unlock() }
    public func clear() { lock.lock(); label = nil; lock.unlock() }
    public func take() -> String? {
        lock.lock(); defer { lock.unlock() }
        defer { label = nil }
        return label
    }
}

/// What one installed package occupies on disk.
///
/// A port of its own, because **`brew info --json=v2` carries no size**: a
/// figure is a directory walk or nothing, so it is not an optional on
/// `PackageInfo`, and its row is the one that lands late.
///
/// **nil is the careful half of the contract, and it means «nothing was
/// measured».** No Cellar directory, a directory that would not open, a name
/// that could not be one — and a cask, which has no Cellar at all. None of
/// those may be folded to 0 anywhere downstream: a zero in a row is not a gap,
/// it is a measurement, and it says a package occupies nothing.
public protocol PackageWeight: Sendable {
    /// Bytes allocated to the package's own directory, or nil when there is
    /// nothing this could have measured.
    ///
    /// Allocated rather than logical (`FileWeight`): what the disk would get back.
    func bytes(ofPackage name: String, isCask: Bool) -> Int?
}

/// The safe default for an engine built without naming one: nothing is
/// measured, and no directory on this Mac is read (as `NoPopularity`).
public struct NoPackageWeight: PackageWeight {
    public init() {}
    public func bytes(ofPackage name: String, isCask: Bool) -> Int? { nil }
}

/// **One brew operation at a time for the whole process**, not per engine.
///
/// The host builds a new `HomebrewEngine` on every enable, and a package
/// operation runs to its end through a switch-off, so two engines can exist
/// together while the first one's `brew` still changes the Cellar. They share
/// one gate: taken in `beginBusy`, given back in `endBusy` after the marker is
/// cleared (so a late clear never deletes the next operation's marker), and
/// `status()` takes no marker while anyone holds it.
///
/// The app passes `.process`; every other construction gets a gate of its own,
/// so tests share no state (`HomebrewEngine.init`).
public final class OperationGate: @unchecked Sendable {
    public static let process = OperationGate()

    private let lock = NSLock()
    private var holder: ObjectIdentifier?

    public init() {}

    /// Whether `owner` now holds the gate: false when another one does.
    func take(_ owner: AnyObject) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if holder != nil { return false }
        holder = ObjectIdentifier(owner)
        return true
    }

    /// Gives the gate back — only if `owner` is the one holding it.
    func release(_ owner: AnyObject) {
        lock.lock(); defer { lock.unlock() }
        if holder == ObjectIdentifier(owner) { holder = nil }
    }

    /// Takes the marker only while nobody holds the gate, in one step: an
    /// operation that starts after the check cannot lose its marker to it.
    func takeMarkerIfFree(_ marker: OpMarker) -> String? { lock.withLock { holder == nil ? marker.take() : nil } }

    var isHeld: Bool { lock.withLock { holder != nil } }
}
