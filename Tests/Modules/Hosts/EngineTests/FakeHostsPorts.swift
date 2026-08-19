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

/// `~/.ssh`, as a fake that can be in the states the directory really reaches.
///
/// **It can be unreadable, and that is not an empty directory.** A Mac with no
/// keys yet and a directory this process may not search are different pages,
/// and a fake with only a list could represent one of them. It can also hand
/// back a key whose mode nobody could read, a `ssh-keygen -l` line this build
/// cannot parse, and a `chmod` that refuses — each of which is a branch in the
/// engine that would otherwise have nothing behind it.
final class FakeSSHKeys: SSHKeysPort, @unchecked Sendable {
    private let lock = NSLock()
    private var listing: [String]?
    private var modes: [String: mode_t]
    private var lines: [String: String]
    private var publics: [String: String]
    private var stamps: [String: Date]
    private var dirMode: mode_t?
    private var refuses = false
    private var recorded: [String] = []
    /// A directory that exists nowhere. Nothing here opens it — the paths this
    /// port composes are compared, not followed — and a fake pointing at a real
    /// `~/.ssh` is how a test starts writing to somebody's keys.
    let directory = URL(fileURLWithPath: "/nowhere/.ssh")

    init(names: [String]? = ["id_ed25519", "id_ed25519.pub"],
         modes: [String: mode_t] = ["id_ed25519": 0o600],
         lines: [String: String] = ["id_ed25519": "256 SHA256:abc123 me@mac (ED25519)"],
         publics: [String: String] = ["id_ed25519": "ssh-ed25519 AAAA me@mac\n"],
         stamps: [String: Date] = [:],
         directoryMode: mode_t? = 0o700) {
        self.listing = names
        self.modes = modes
        self.lines = lines
        self.publics = publics
        self.stamps = stamps
        self.dirMode = directoryMode
    }

    /// Every `chmod` this port was asked for, in order — read behind the lock
    /// like everything else here.
    var chmods: [String] { lock.withLock { recorded } }

    /// The directory stops being readable. Ejecting a FileVault volume, a
    /// permission taken away — ordinary, not contrived.
    func becomesUnreadable() { lock.withLock { listing = nil } }
    /// `chmod` refuses from now on: an immutable flag, a read-only volume.
    func refusesToChangeModes() { lock.withLock { refuses = true } }

    func names() -> [String]? { lock.withLock { listing } }

    func facts(for pair: KeyInventory.Pair) -> KeyFacts {
        lock.withLock {
            KeyFacts(pair: pair,
                     describeLine: pair.hasPublicHalf ? lines[pair.name] : nil,
                     mode: modes[pair.name],
                     modified: stamps[pair.name],
                     publicText: pair.hasPublicHalf ? publics[pair.name] : nil)
        }
    }

    func directoryMode() -> mode_t? { lock.withLock { dirMode } }

    func chmod(_ name: String, to mode: mode_t) -> Bool {
        lock.withLock {
            recorded.append(name)
            guard !refuses else { return false }
            modes[name] = mode
            return true
        }
    }

    func chmodDirectory(to mode: mode_t) -> Bool {
        lock.withLock {
            recorded.append(".")
            guard !refuses else { return false }
            dirMode = mode
            return true
        }
    }
}

/// The agent, in all three of its states — **and able to refuse a load.**
///
/// An encrypted key is the ordinary reason `ssh-add` says no: it wants a
/// passphrase, and the plain load path has no channel for one. A fake that
/// always succeeded would make the engine's refusal arm unreachable, and a fake
/// whose answer never changed after a load would make «the badge comes on»
/// untestable — so a load moves this one's own answer, the way the real agent's
/// does.
final class FakeSSHAgent: SSHAgentPort, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: AgentList
    private var refuses: Bool
    private var recorded: [String] = []
    /// What a successful load puts into the agent, keyed by name. A load of a
    /// key this does not know still succeeds and holds nothing new, which is
    /// the shape of a tool that reported success over something we cannot see.
    private var fingerprints: [String: String]

    init(_ answer: AgentList = .empty, refuses: Bool = false,
         fingerprints: [String: String] = ["id_ed25519": "SHA256:abc123"]) {
        self.answer = answer
        self.refuses = refuses
        self.fingerprints = fingerprints
    }

    var acts: [String] { lock.withLock { recorded } }

    /// The agent goes away under the app — the socket dies, the process is
    /// killed. A fact that stops being true on its own.
    func goesAway() { lock.withLock { answer = .unreachable } }

    func list() -> AgentList { lock.withLock { answer } }

    func load(_ name: String) -> Bool {
        lock.withLock {
            recorded.append("load \(name)")
            guard !refuses else { return false }
            if let print = fingerprints[name] {
                var held: [String] = []
                if case .holding(let existing) = answer { held = existing }
                answer = .holding(held.contains(print) ? held : held + [print])
            }
            return true
        }
    }

    func unload(_ name: String) -> Bool {
        lock.withLock {
            recorded.append("unload \(name)")
            guard !refuses else { return false }
            if let print = fingerprints[name], case .holding(let held) = answer {
                let left = held.filter { $0 != print }
                answer = left.isEmpty ? .empty : .holding(left)
            }
            return true
        }
    }
}

/// `ssh-keygen`, faked — **and able to sit at the prompt for as long as a test
/// needs.**
///
/// A generator that has always already finished makes «does a second press start
/// a second generation?» vacuous: the subject is over before the code under test
/// is reached. So this one can be held at the prompt and released, which is the
/// state a real `ssh-keygen` is in for every second it spends making an RSA key.
///
/// It also records the arguments it was given, so «the passphrase is not in the
/// sentence» can be asserted about the sentence rather than believed about the
/// design.
final class FakeGenerator: KeyGeneratorPort, @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32
    private var runs: [[String]] = []
    private var answers: [Data] = []
    private var holds = false
    private let atThePrompt = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    init(status: Int32 = 0) { self.status = status }

    var sentences: [[String]] { lock.withLock { runs } }
    /// What it was answered with — a copy taken before the buffer is zeroed, so
    /// a test can say «the passphrase reached the tool» and «the caller's copy
    /// is gone» as two separate facts.
    var answered: [Data] { lock.withLock { answers } }

    /// The next run stops at the prompt until `finish()`.
    func sitsAtThePrompt() { lock.withLock { holds = true } }
    /// Wait until a run is actually sitting there. Without this a test races
    /// the thread it is trying to hold still.
    func waitUntilAsked() { atThePrompt.wait() }
    /// Releases **every** run sitting at the prompt, not one.
    ///
    /// Measured, by deleting the engine's gate: with one signal the second run
    /// sat there for ever and the test hung instead of failing. A hang is not a
    /// failing guard — it is a suite that has to be killed by hand and a result
    /// nobody can read. Released generously, the second run finishes and the
    /// count assertion says plainly that two generations happened.
    func finish() { for _ in 0..<8 { released.signal() } }

    func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
        let waiting: Bool = lock.withLock {
            runs.append(arguments)
            answers.append(secret)
            // **The hold is consumed, so it belongs to one run.** Held for
            // every run instead, a second generation would sit at the prompt
            // too — and a test whose gate has been deleted would then hang
            // rather than fail, which is a suite somebody has to kill by hand.
            // Measured that way first.
            defer { holds = false }
            return holds
        }
        // Zeroed here, as the real port does: what the caller handed over is
        // gone by the time this returns, whatever else happens.
        secret.resetBytes(in: 0..<secret.count)
        secret = Data()
        if waiting {
            atThePrompt.signal()
            released.wait()
        }
        return lock.withLock { status }
    }
}

/// `~/.ssh/known_hosts`, faked — **and able to be absent, unreadable, and a
/// file that refuses the write.**
///
/// A Mac that has never connected anywhere has no such file at all, which is
/// not an empty one; a file can stop being readable between two refreshes; and
/// a write can fail or report success over bytes it did not store. The last is
/// what the engine's read-back exists for, and without it here that branch
/// would have nothing behind it.
final class FakeKnownHosts: KnownHostsPort, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var behaviour: Behaviour
    private var writes = 0

    enum Behaviour: Sendable { case ordinary, refuse, lie }

    let url: URL

    init(url: URL = URL(fileURLWithPath: "/nowhere/.ssh/known_hosts"),
         text: String? = "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 me@mac\n",
         behaviour: Behaviour = .ordinary) {
        self.url = url
        self.stored = text
        self.behaviour = behaviour
    }

    var writeCount: Int { lock.withLock { writes } }

    func read() -> String? { lock.withLock { stored } }

    func write(_ text: String) -> Bool {
        lock.withLock {
            writes += 1
            switch behaviour {
            case .ordinary: stored = text; return true
            case .refuse: return false
            // Success over a file that did not change — the shape the read-back
            // is the only defence against.
            case .lie: return true
            }
        }
    }
}
