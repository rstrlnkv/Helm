import Foundation
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Homebrew_Engine

// Fakes for the wait on Apple's Command Line Tools, shared by the files that
// drive it — `command grep -rlw WaitRig Tests` names them. They live beside the Homebrew engine tests and not in
// `Tests/Support`, which sees only the runtime and the shared UI target — the
// shape Keep Awake's own `Fakes.swift` has, for the same reason.

/// One ordered record that the tools fake and the privileges fake both write
/// into, so a test can say what came *directly before* the password dialog —
/// two records apart could only say each happened.
final class Journal: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [String] = []
    func note(_ entry: String) { lock.lock(); _entries.append(entry); lock.unlock() }
    var entries: [String] { lock.lock(); defer { lock.unlock() }; return _entries }
}

/// Apple's tools, as the engine can ask about them.
///
/// **Filing the request does not open the window**: on a real Mac Apple's
/// installer appears later and on its own, so `requestInstall` leaves
/// `installerRunning` as the test set it — a fake that started the installer
/// itself would make "the window was never seen" unrepresentable.
final class FakeCommandLineTools: CommandLineToolsPort, @unchecked Sendable {
    private let lock = NSLock()
    private let journal: Journal?
    private var _gitExecutable = false
    private var _selected: String?
    private var _executables: Set<String> = []
    private var _request: ToolsRequest = .filed
    private var _installerRunning = false
    private var _requests = 0
    private var _selectedAsked = 0
    private var _onRequest: (() -> Void)?
    private var _onInstallerRead: (() -> Void)?
    private var _onRead: (() -> Void)?

    init(journal: Journal? = nil) { self.journal = journal }

    /// The fixed `git` the installer looks for.
    var gitExecutable: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _gitExecutable }
        set { lock.lock(); _gitExecutable = newValue; lock.unlock() }
    }
    /// What `xcode-select -p` answers: nil is exit 2, the deadline or a failed
    /// launch, which the port does not tell apart.
    var selected: String? {
        get { lock.lock(); defer { lock.unlock() }; return _selected }
        set { lock.lock(); _selected = newValue; lock.unlock() }
    }
    /// Other executable files, for a developer directory `selected` names.
    var executables: Set<String> {
        get { lock.lock(); defer { lock.unlock() }; return _executables }
        set { lock.lock(); _executables = newValue; lock.unlock() }
    }
    var request: ToolsRequest {
        get { lock.lock(); defer { lock.unlock() }; return _request }
        set { lock.lock(); _request = newValue; lock.unlock() }
    }
    var installerRunning: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _installerRunning }
        set { lock.lock(); _installerRunning = newValue; lock.unlock() }
    }
    /// Runs inside `requestInstall`, before it answers: the world moving while
    /// the request is being filed.
    var onRequest: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRequest }
        set { lock.lock(); _onRequest = newValue; lock.unlock() }
    }
    /// Runs inside `installerIsRunning`, after the answer is fixed and before
    /// it is returned: what happens between one reading and the next.
    var onInstallerRead: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onInstallerRead }
        set { lock.lock(); _onInstallerRead = newValue; lock.unlock() }
    }
    /// Runs inside `isExecutable`, before it answers: the first thing the
    /// engine does after taking the busy gate.
    var onRead: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRead }
        set { lock.lock(); _onRead = newValue; lock.unlock() }
    }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return _requests }
    var selectedAsked: Int { lock.lock(); defer { lock.unlock() }; return _selectedAsked }

    func isExecutable(_ path: String) -> Bool {
        journal?.note("read")
        lock.lock(); let hook = _onRead; lock.unlock()
        hook?()
        lock.lock(); defer { lock.unlock() }
        return path == CommandLineTools.git ? _gitExecutable : _executables.contains(path)
    }

    func selectedDeveloperDirectory() -> String? {
        journal?.note("select")
        lock.lock(); defer { lock.unlock() }
        _selectedAsked += 1
        return _selected
    }

    func requestInstall() -> ToolsRequest {
        journal?.note("request")
        lock.lock(); _requests += 1; let hook = _onRequest; let answer = _request; lock.unlock()
        hook?()
        return answer
    }

    func installerIsRunning() -> Bool {
        journal?.note("running?")
        lock.lock(); let answer = _installerRunning; let hook = _onInstallerRead; lock.unlock()
        hook?()
        return answer
    }
}

/// Manual ticker, in the shape of Keep Awake's `FakeClock`: `schedule` records
/// the blocks, `fire()` runs the latest live one, releasing a token cancels its
/// entry. It never fires by itself.
final class FakeWaitTicker: WaitTicker, @unchecked Sendable {
    final class Token {
        private let onCancel: () -> Void
        init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        deinit { onCancel() }
    }
    private struct Entry { let block: @Sendable () -> Void; var cancelled = false; var fired = false }
    private let lock = NSLock()
    private var entries: [Entry] = []

    func schedule(after interval: TimeInterval, _ block: @escaping @Sendable () -> Void) -> AnyObject {
        lock.lock()
        let index = entries.count
        entries.append(Entry(block: block))
        lock.unlock()
        return Token { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.entries[index].cancelled = true; self.lock.unlock()
        }
    }

    /// Ticks armed and neither cancelled nor run: what would still land.
    var live: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.filter { !$0.cancelled && !$0.fired }.count
    }
    /// Every tick ever armed, including the ones since cancelled.
    var scheduled: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// Runs the latest tick that is still live. False when there was none.
    @discardableResult
    func fire() -> Bool {
        lock.lock()
        guard let index = entries.lastIndex(where: { !$0.cancelled && !$0.fired }) else {
            lock.unlock(); return false
        }
        entries[index].fired = true
        let block = entries[index].block
        lock.unlock()
        block()
        return true
    }

    /// Runs one tick whether or not it was cancelled: a tick that was already
    /// on its way when its token was released, which cancelling a work item
    /// cannot recall.
    func fireInFlight(_ index: Int) {
        lock.lock(); let block = entries[index].block; lock.unlock()
        block()
    }
}

/// Answers the password dialog as the test says, records what root was asked
/// for, and can hold the dialog on screen until the test answers it — the
/// engine's thread blocks inside `runAdmin` exactly as it does behind
/// `osascript`.
final class ScriptedPrivileged: PrivilegedRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let journal: Journal?
    private var _scripts: [String] = []
    private let reply: PrivilegedOutcome
    private let appeared = DispatchSemaphore(value: 0)
    private let answered = DispatchSemaphore(value: 0)
    private let holds: Bool

    init(reply: PrivilegedOutcome, holds: Bool = false, journal: Journal? = nil) {
        self.reply = reply
        self.holds = holds
        self.journal = journal
    }

    var scripts: [String] { lock.lock(); defer { lock.unlock() }; return _scripts }

    func runAdmin(_ script: String) -> PrivilegedOutcome {
        journal?.note("admin")
        lock.lock(); _scripts.append(script); lock.unlock()
        appeared.signal()
        // A dialog nobody holds is answered at once, however many times it is
        // asked: one permit consumed by the first call would park the second.
        if holds { answered.wait() }
        return reply
    }

    func waitUntilOnScreen(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(appeared.wait(timeout: .now() + 5), .success,
                       "the administrator dialog was never asked for", file: file, line: line)
    }
    func answer() { answered.signal() }
}

/// Records what it was asked to stream and finishes only when told: a stream
/// that answered at once would release the busy gate before the call returned.
final class RecordingStreamRunner: ProcessRunner, @unchecked Sendable {
    struct Call { let launch: String; let args: [String]; let env: [String: String] }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _exits: [@Sendable (Int32) -> Void] = []

    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    func run(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String], env: [String: String]) -> (status: Int32, output: String) { (0, "") }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        lock.lock(); _calls.append(Call(launch: launchPath, args: args, env: env)); _exits.append(onExit); lock.unlock()
        return NoProcess()
    }

    func finishAll(code: Int32 = 0) {
        lock.lock(); let exits = _exits; _exits = []; lock.unlock()
        for exit in exits { exit(code) }
    }
}

/// An engine wired to the three fakes for the three sides of its boundary —
/// Apple's tools, time, root — plus a runner, each named at construction.
final class WaitRig {
    struct FixedLocator: BrewLocator { func brewPath() -> String? { "/opt/homebrew/bin/brew" } }

    let journal = Journal()
    let tools: FakeCommandLineTools
    let ticker = FakeWaitTicker()
    let privileged: ScriptedPrivileged
    let runner = RecordingStreamRunner()
    let transport = LocalTransport()
    let engine: HomebrewEngine

    init(reply: PrivilegedOutcome = .done, holdsDialog: Bool = false, user: String = "tester") {
        tools = FakeCommandLineTools(journal: journal)
        privileged = ScriptedPrivileged(reply: reply, holds: holdsDialog, journal: journal)
        engine = HomebrewEngine(locator: FixedLocator(), runner: runner, privileged: privileged,
                                user: user, transport: transport, marker: InMemoryOpMarker(),
                                tools: tools, ticker: ticker)
    }

    /// The latest `opState` and `opLog` the transport would replay to a page
    /// opened now. A sentinel emitted before subscribing marks where the replay
    /// ends, so the read is deterministic.
    func replayed() async -> (state: OpState?, log: String?) {
        transport.emit(EngineEvent(name: "test.sentinel", payload: Data()))
        var state: OpState?
        var log: String?
        for await event in transport.events {
            if event.name == "test.sentinel" { break }
            switch HomebrewEvent(rawValue: event.name) {
            case .opState: state = try? JSONDecoder().decode(OpState.self, from: event.payload)
            case .opLog: log = String(bytes: event.payload, encoding: .utf8)
            case .none: break
            }
        }
        return (state, log)
    }
}
