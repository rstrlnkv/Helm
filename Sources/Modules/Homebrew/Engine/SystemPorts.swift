import Foundation
import HelmRuntime

// MARK: - Locator

public struct FSBrewLocator: BrewLocator {
    public init() {}
    public func brewPath() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return nil
    }
}

// MARK: - Process runner

/// Splits streamed bytes into whole lines, thread-safely.
///
/// **Bytes, not text.** This used to decode each chunk with
/// `String(data:encoding:.utf8)` and `return` on nil. `availableData` splits on
/// byte boundaries, not character boundaries, so a multi-byte character
/// straddling two reads leaves the first chunk ending mid-sequence — and the
/// whole chunk went, not the one character. Everything ahead of the split was
/// plain ASCII and perfectly decodable, and it went too. Reachable with any
/// non-ASCII output past one read, which `brew` produces on every successful
/// install.
///
/// So the split happens on the newline *byte* and only complete lines are
/// decoded; an unfinished character simply stays in the buffer with the rest of
/// its unfinished line. `String(decoding:as:)` rather than the failable
/// initialiser, because bytes that are not UTF-8 at all are still somebody's
/// log: they come through as replacement characters instead of taking the lines
/// around them with them.
final class LineBuffer: @unchecked Sendable {
    private static let newline: UInt8 = 0x0A
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var partial = Data()
    init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

    func feed(_ data: Data) {
        lock.lock()
        partial.append(data)
        var complete: [Data] = []
        while let newline = partial.firstIndex(of: Self.newline) {
            complete.append(partial[partial.startIndex..<newline])
            partial = partial[partial.index(after: newline)...]
        }
        // Re-base: a slice keeps its parent's indices, so without this the
        // buffer's start walks forward for the life of the stream.
        partial = Data(partial)
        lock.unlock()
        for line in complete { onLine(String(decoding: line, as: UTF8.self)) }
    }

    /// The last line of a tool that did not end with a newline is still a line.
    func flush() {
        lock.lock(); let rest = partial; partial = Data(); lock.unlock()
        if !rest.isEmpty { onLine(String(decoding: rest, as: UTF8.self)) }
    }
}

/// Carries the exit status from the termination callback to whoever reports it.
private final class StatusBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int32 = -1
    func set(_ v: Int32) { lock.lock(); value = v; lock.unlock() }
    var status: Int32 { lock.lock(); defer { lock.unlock() }; return value }
}

public struct ShellProcessRunner: ProcessRunner {
    /// How long a *query* may go unanswered before it is a hang, not a wait.
    ///
    /// `run` serves only the read-only queries (list, outdated, desc, search);
    /// the long operations stream and are stopped by hand, never by a clock.
    /// Measured on the owner's log before choosing: warm queries answer in
    /// 0.3–0.6 s, and a cold `brew outdated` — which goes to the network —
    /// took 7.4 s (helm.log, 2026-08-15 16:09:35→42). Ninety seconds clears the
    /// slowest measured query more than tenfold and still ends a hung brew —
    /// another brew's lock never released, a stalled network read — inside the
    /// same sitting, with the Refresh button live again.
    public static let defaultQueryTimeout: TimeInterval = 90

    private let queryTimeout: TimeInterval

    public init(queryTimeout: TimeInterval = ShellProcessRunner.defaultQueryTimeout) {
        self.queryTimeout = queryTimeout
    }

    private func environment(_ extra: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        for (k, v) in extra { e[k] = v }
        return e
    }

    /// The port stays — it is what makes the engine testable — but the body is
    /// `HelmProcess`, like every other module's.
    ///
    /// Two things were different here, and both were wrong in the same
    /// direction. This copy merged stderr into stdout, and all four of its
    /// callers parse what they get: `BrewListParser` takes the first word of
    /// every line as a package name, so a version-support warning from `brew`
    /// became a row with an Uninstall button beside it. And it waited with
    /// `waitUntilExit`, the 50 ms run-loop poll `HelmProcess` was written to
    /// remove, paid twice per query.
    ///
    /// `stream` keeps stderr: a console should show what the tool says. It is
    /// output that gets parsed that must not carry diagnostics.
    public func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) {
        let result = HelmProcess.run(launchPath, args, env: environment(env),
                                     timeout: queryTimeout)
        return (result.status, result.output)
    }

    /// The bytes without the String round-trip — `HelmProcess.runData`'s doc
    /// comment carries the measured difference.
    public func runData(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: Data) {
        let r = HelmProcess.runData(launchPath, args, env: environment(env), timeout: queryTimeout)
        return (r.status, r.output)
    }

    /// **The exit is reported at end of pipe, not at end of process.** These are
    /// two different moments and the process is the earlier one: the child
    /// exits, the termination callback fires, and whatever it had written that
    /// the reader had not picked up yet is still sitting in the pipe. Clearing
    /// the readability handler there threw that away — so the tail of a
    /// `brew install`, which is the part that says where it put things, was
    /// missing from the console whenever the reader ran behind the writer. It
    /// always does: `onLine` hops to the main actor and redraws a console.
    /// Measured at 5000 lines with a 2 ms consumer, five runs out of five lost
    /// between 396 and 4200 of them.
    ///
    /// Reading to the end first is the same order `HelmProcess.run` uses, and
    /// for the same reason. EOF arrives only when every writer has closed, so
    /// by then the child has finished; the wait below is immediate rather than
    /// a poll.
    @discardableResult
    public func stream(_ launchPath: String, _ args: [String], env: [String: String],
                       onLine: @escaping @Sendable (String) -> Void,
                       onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        p.environment = environment(env)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let buffer = LineBuffer(onLine: onLine)
        let status = StatusBox()
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { proc in
            status.set(proc.terminationStatus)
            exited.signal()
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty else {
                // Empty means end of file: everything written has been read.
                handle.readabilityHandler = nil
                buffer.flush()
                exited.wait()
                onExit(status.status)
                return
            }
            buffer.feed(d)
        }
        // `HelmProcess.start`, never `try p.run()`. The five operations that
        // reach this line are the ones that change the machine, and every one
        // of them carries a package name parsed out of brew's own stdout: a
        // launch `NSTask` *raises* on takes the whole app down, because the
        // exception has no Swift frame to land on. `run` and `runData` moved
        // behind that door when it was written and this one did not.
        guard HelmProcess.start(p, path: launchPath) else {
            // No child, so no EOF is ever coming — the page would keep its
            // spinner forever waiting for one.
            pipe.fileHandleForReading.readabilityHandler = nil
            onExit(-1)
            return NoProcess()
        }
        // The handle retains the `Process`: it used to be a local nobody kept,
        // leaving the running child with no way to be addressed again.
        return LiveProcess(p)
    }
}

/// The real handle: SIGTERM, so a brew mid-operation gets to clean up after
/// itself — never KILL, which is how half-written Cellar state is made. The
/// exit still arrives through the pipe's EOF, the same way an honest exit does.
private struct LiveProcess: RunningProcess, @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

// MARK: - Privileged runner

public struct OSAPrivilegedRunner: PrivilegedRunner {
    public init() {}
    public func runAdmin(_ script: String) -> Bool {
        // `AppleScript` in HelmRuntime — the escaping was written out here and
        // in `SudoersRule`, and Keep Awake's copy carried the comment saying so.
        let osa = AppleScript.administratorShellScript(script)
        return HelmProcess.run("/usr/bin/osascript", ["-e", osa]).status == 0
    }
}

// MARK: - Operation marker

/// The marker as a file, so it survives the quit it exists to report.
///
/// The label an operation writes is a brew command with a package name in it —
/// a fact about the person's machine, so the file goes through `PrivateFile`
/// like every other file that names somebody's things. It lives in Helm's own
/// Application Support folder, which `HelmSupport.directory` already redirects
/// into scratch under a test runner.
public struct FileOpMarker: OpMarker {
    private let url: URL

    public init(directory: URL = HelmSupport.directory) {
        url = directory.appendingPathComponent("homebrew-operation")
    }

    /// A marker that does not land is the calm the protocol above exists to
    /// prevent: brew goes on changing the Cellar after Helm quits, and the next
    /// launch has nothing to report it with. Nothing can be done about it here —
    /// the write is the whole mechanism — so it is said, and the label is not,
    /// because the label is a brew command with a package name in it.
    public func write(_ label: String) {
        if !PrivateFile.writeMakingTheFolder(Data(label.utf8), at: url) {
            HelmLog.shared.warn(HomebrewEngine.moduleID,
                                "the running operation could not be written down — a quit before "
                                + "it finishes will not be reported at the next launch")
        }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    public func take() -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        clear()
        return String(bytes: data, encoding: .utf8)
    }
}

// MARK: - Factory

public struct HomebrewSystemPorts {
    public let locator = FSBrewLocator()
    public let runner = ShellProcessRunner()
    public let privileged = OSAPrivilegedRunner()
    public let marker = FileOpMarker()
    public init() {}
}
