import Foundation

public protocol BrewLocator: Sendable {
    func brewPath() -> String?
}

/// What a caller can still do to a process it started: end it. Terminating is
/// not finishing — the child dies, *then* the pipe closes and `onExit` lands,
/// exactly as when it exits on its own.
public protocol RunningProcess: Sendable {
    func terminate()
}

/// A handle with nothing behind it: a stream that failed to spawn, or a fake
/// whose child has no process. Terminating it does nothing, which is all there
/// is to do.
struct NoProcess: RunningProcess {
    init() {}
    func terminate() {}
}

public protocol ProcessRunner: Sendable {
    /// Run to completion, capturing stdout (stderr merged). Blocking, and
    /// bounded: past the runner's deadline the answer is
    /// `HelmProcess.timedOutStatus`, never a wait without end.
    func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String)
    /// The same run, bytes untouched — for a parser that wants `Data`. Routing
    /// a JSON payload through `run` pays a String nobody reads plus a copy
    /// straight back to `Data` (`OutdatedQueryAllocationBenchmark` has the
    /// figures). A protocol requirement, not only an extension: the engine
    /// holds the runner as an existential, and an extension-only method would
    /// dispatch every real call to the copying default below.
    func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data)
    /// Stream a long-running process: `onLine` per output line, `onExit` at the
    /// end. The handle is the only way to end a brew that will not — an
    /// operation has no deadline, because an install may honestly take an hour.
    @discardableResult
    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess
}

public extension ProcessRunner {
    /// Correct for any fake that only speaks String — it pays the copy the
    /// real runner exists to avoid, which a test does not feel.
    func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data) {
        let r = run(launchPath, args, env: env)
        return (r.status, Data(r.stdout.utf8))
    }
}

public protocol PrivilegedRunner: Sendable {
    /// Run a shell script with administrator privileges via the native macOS
    /// password dialog (the user types the password). Returns success.
    func runAdmin(_ script: String) -> Bool
}

/// Remembers the operation that is running, across a quit.
///
/// A child brew survives Helm — quitting mid-install leaves it changing the
/// Cellar with no observer, and the next launch used to look calm over a
/// machine that had moved. Killing the child instead would be worse: a build
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
