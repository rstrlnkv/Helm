import Foundation
import HelmRuntime
@testable import Module_Hosts_Engine

/// A file that can also be missing, can change under the app, **and can be a
/// file that does not decode** — `nil` stands for both "not there" and "not
/// UTF-8", the two ways a real `/etc/hosts` refuses to be read. A fake that can
/// only be present or absent cannot represent the second, and the engine's
/// `hostsReadable` branch would have nothing behind it.
final class FakeHostsFile: HostsFilePort, @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?
    init(_ text: String? = "127.0.0.1\tlocalhost\n") { self.text = text }
    func read() -> String? { lock.withLock { text } }
    /// Something else edited the file. `/etc/hosts` is a file any admin
    /// program may rewrite, so this is an ordinary state, not a contrived one.
    func changeUnderTheApp(to newText: String?) { lock.withLock { text = newText } }
}

/// Root, asked.
///
/// **It can decline, it can fail, it can lie, it can lie destructively, and it
/// can still be thinking about it.** Each of those is a state the real dialog
/// reaches:
///
/// - `decline` is the *common* answer to a password prompt, not an edge case.
/// - `lie` is root reporting success over a file it never changed; without it
///   the read-back check in `applyHosts` has nothing behind it.
/// - `truncateAndLie` is the same lie over a file it **emptied**, which is the
///   shape `HostsWrite`'s three readings found: `>` truncates before the
///   pipeline runs, and a pipeline's status is its last command's, so a failed
///   `/bin/echo` leaves `base64 -D` writing nothing and exiting 0. Unchanged
///   and destroyed are different disasters and a fake with one `lie` can only
///   hold the cheaper one.
/// - `pausesUntilAnswered` is the dialog still being on screen. A fake that has
///   always already answered makes every test of the busy state vacuous — the
///   subject is over before the code under test is reached.
final class FakePrivileged: PrivilegedPort, @unchecked Sendable {
    enum Behaviour: Sendable { case succeed, decline, fail(Int32), lie, truncateAndLie }

    private let lock = NSLock()
    private var behaviour: Behaviour
    private var recorded: [String] = []
    private var pauses = false
    private let dialogAppeared = DispatchSemaphore(value: 0)
    private let dialogAnswered = DispatchSemaphore(value: 0)
    private let file: FakeHostsFile

    init(_ behaviour: Behaviour = .succeed, writingTo file: FakeHostsFile) {
        self.behaviour = behaviour
        self.file = file
    }

    /// Every field is read behind the lock, including this one. A lock taken on
    /// one side of a field guards nothing, and `@unchecked Sendable` is the
    /// compiler being told to trust the author for exactly this.
    var commands: [String] { lock.withLock { recorded } }

    /// The next `run` sits in the dialog until `answerTheDialog()`.
    func pausesUntilAnswered() { lock.withLock { pauses = true } }

    /// True once a `run` has reached the dialog and not yet returned.
    func waitForTheDialog(timeout: TimeInterval) -> Bool {
        dialogAppeared.wait(timeout: .now() + timeout) == .success
    }

    /// The person typed their password, or pressed Cancel — either way the
    /// dialog goes away and `run` gets to its answer.
    func answerTheDialog() { dialogAnswered.signal() }

    func run(_ command: String) -> PrivilegedOutcome {
        let (behaviour, waits): (Behaviour, Bool) = lock.withLock {
            recorded.append(command)
            return (self.behaviour, pauses)
        }
        if waits {
            dialogAppeared.signal()
            dialogAnswered.wait()
        }
        switch behaviour {
        case .succeed:
            // Do what the real command does, so a test can read the result back
            // the way the engine does. A payload this cannot find is a refusal
            // rather than a shrug: `.done` over an unread command would report
            // the drift between this fake and `HostsWrite` as a passing test.
            guard let text = Self.payload(of: command) else { return .failed(1) }
            file.changeUnderTheApp(to: text)
            return .done
        case .decline: return .declined
        case .fail(let status): return .failed(status)
        case .lie: return .done
        case .truncateAndLie:
            file.changeUnderTheApp(to: "")
            return .done
        }
    }

    /// The payload `HostsWrite` handed `/bin/echo`, decoded.
    ///
    /// This reads the shell sentence the other side writes, which is a name
    /// spelled on both sides of a boundary — so the tie is a test:
    /// `FakePrivilegedTests` builds its command from `HostsWrite.command(base64:)`
    /// itself, and a change to the sentence that this cannot follow turns up
    /// there rather than as a silently inert `.succeed`.
    private static func payload(of command: String) -> String? {
        let words = command.split(separator: " ")
        guard let echo = words.firstIndex(of: "/bin/echo") else { return nil }
        let payload = words.index(after: echo)
        guard payload < words.endIndex,
              let data = Data(base64Encoded: String(words[payload])) else { return nil }
        // Failable, not `String(decoding:as:)`: bytes that are not UTF-8 would
        // come back as U+FFFD, and a fake that quietly substitutes characters
        // is the very defect `SystemHostsFile`'s strict decode exists to stop.
        return String(bytes: data, encoding: .utf8)
    }
}

/// Backups that can be a folder that cannot be written to, that can hold
/// somebody else's files, and that can list a copy which will not read back.
///
/// The last one is the state a dictionary hides: a real folder can lose a file
/// between the listing and the restore, or hold one whose bytes are not UTF-8,
/// and `SystemBackups.read` answers nil for both. A restore has a branch for
/// that; without this it has nothing behind it.
final class FakeBackups: BackupPort, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String] = [:]
    private var unreadable: Set<String> = []
    private var refuses = false

    /// Behind the lock like everything else here — a fake read from a test's
    /// thread and written from a view model's task is two threads whatever the
    /// field looks like.
    var refusesToSave: Bool {
        get { lock.withLock { refuses } }
        set { lock.withLock { refuses = newValue } }
    }

    func save(_ text: String, name: String) -> Bool {
        lock.withLock {
            guard !refuses, BackupName.isOurs(name) else { return false }
            files[name] = text
            return true
        }
    }

    /// Filtered and sorted exactly as `SystemBackups.list()` is. A fake free to
    /// list a name the port never could is a fake free to plant a state that is
    /// not one — the same defect as being simpler than the port, read from the
    /// other side.
    func list() -> [String] { lock.withLock { files.keys.filter(BackupName.isOurs).sorted() } }

    func read(_ name: String) -> String? {
        lock.withLock {
            guard BackupName.isOurs(name), !unreadable.contains(name) else { return nil }
            return files[name]
        }
    }

    func delete(_ names: [String]) {
        lock.withLock { for name in names where BackupName.isOurs(name) { files[name] = nil } }
    }

    /// Something in the folder that Helm did not put there — `.DS_Store` is the
    /// one macOS leaves without being asked, and it sorts *before* every name
    /// `BackupName` generates, which is what makes it a stranger a pruning bug
    /// could actually reach.
    func plantForeignFile(_ name: String) {
        lock.withLock { files[name] = "" }
    }

    /// Listed, and gone or unreadable by the time somebody asks for it.
    func makeUnreadable(_ name: String) { lock.withLock { _ = unreadable.insert(name) } }
}

/// `~/.ssh/config`, as a port that can be what the real one can.
///
/// **It can lie**, which is the capability the read-back exists for: a write
/// that returns success over a file it did not change. A fake that always wrote
/// what it was given would make `notVerified` a branch no test could reach —
/// the shape CLAUDE.md calls a fake simpler than the thing it stands for. It can
/// also refuse outright, and it counts its writes, so «refused before writing»
/// is a fact a test can assert rather than infer.
final class FakeSSHConfig: SSHConfigPort, @unchecked Sendable {

    enum Behaviour: Sendable {
        case ordinary
        /// The write reports success and the file stays as it was.
        case lie
        case refuse
    }

    let url: URL
    private let lock = NSLock()
    private var text: String?
    private let behaviour: Behaviour
    private var written = 0

    init(url: URL, text: String?, behaviour: Behaviour = .ordinary) {
        self.url = url
        self.text = text
        self.behaviour = behaviour
    }

    /// How many times a write was attempted, whatever it came to.
    var writes: Int { lock.withLock { written } }

    func read() -> String? { lock.withLock { text } }

    func write(_ newText: String) -> Bool {
        lock.withLock {
            written += 1
            switch behaviour {
            case .ordinary: text = newText; return true
            case .lie: return true
            case .refuse: return false
            }
        }
    }

    /// Somebody edited the file in an editor, or it went away. An ordinary
    /// state for a file that belongs to the person, not a contrived one.
    func changeUnderTheApp(to newText: String?) { lock.withLock { text = newText } }
}
