import Foundation
@testable import Module_Hosts_Engine

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
    private var listing: KeyInventory.Listing?
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

    /// **`Listing`, not `[String]`, so a directory in the keyring is a state
    /// this fake can be in.** `~/.ssh` holds folders — `sockets` for a
    /// `ControlPath`, `config.d` for an `Include` — and a fake that could only
    /// hold file names could not fail the way the port does.
    init(names: KeyInventory.Listing? = ["id_ed25519", "id_ed25519.pub"],
         modes: [String: mode_t] = ["id_ed25519": 0o600],
         // With the ending `ssh-keygen -l` really writes. A fake tidier than
         // the port cannot fail the way the port does, and this one was: the
         // parser refused every real key on the machine while every test built
         // on this line stayed green.
         lines: [String: String] = ["id_ed25519": "256 SHA256:abc123 me@mac (ED25519)\n"],
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

    func names() -> KeyInventory.Listing? { lock.withLock { listing } }

    func facts(for pair: KeyInventory.Pair) -> KeyFacts {
        lock.withLock {
            KeyFacts(pair: pair,
                     describeLine: pair.hasPublicHalf ? lines[pair.name] : nil,
                     mode: modes[pair.name],
                     modified: stamps[pair.name],
                     publicText: pair.hasPublicHalf ? publics[pair.name] : nil,
                     isDirectory: listing?.directories.contains(pair.name) ?? false)
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

    /// `locked` names the keys that carry a passphrase and what it is. A key
    /// absent from it is one `ssh-add` takes without asking.
    private var locked: [String: Data]
    private var answered: [Data] = []

    init(_ answer: AgentList = .empty, refuses: Bool = false,
         fingerprints: [String: String] = ["id_ed25519": "SHA256:abc123"],
         locked: [String: Data] = [:]) {
        self.answer = answer
        self.refuses = refuses
        self.fingerprints = fingerprints
        self.locked = locked
    }

    /// What it was answered with, in order — a copy taken before the buffer is
    /// zeroed, so «the passphrase reached the tool» and «the caller's copy is
    /// gone» are two facts a test can hold apart.
    var passphrases: [Data] { lock.withLock { answered } }

    var acts: [String] { lock.withLock { recorded } }

    /// The agent goes away under the app — the socket dies, the process is
    /// killed. A fact that stops being true on its own.
    func goesAway() { lock.withLock { answer = .unreachable } }

    func list() -> AgentList { lock.withLock { answer } }

    /// **It can want a passphrase, and it can want the right one.**
    ///
    /// An encrypted key is the ordinary state of a key worth having, and until
    /// this fake could be in it the engine's `needsPassphrase` arm had nothing
    /// behind it — a fake simpler than the port cannot fail the way the port
    /// does. It also zeroes what it was handed, as the real one does, so «the
    /// caller's buffer is empty afterwards» is a thing a test can assert.
    func load(_ name: String, answering secret: inout Data) -> AgentLoad {
        let given = secret
        secret.resetBytes(in: 0..<secret.count)
        secret = Data()
        return lock.withLock {
            recorded.append("load \(name)")
            answered.append(given)
            guard !refuses else { return .failed }
            if let wanted = locked[name] {
                guard given == wanted else { return .needsPassphrase }
            }
            if let print = fingerprints[name] {
                var held: [String] = []
                if case .holding(let existing) = answer { held = existing }
                answer = .holding(held.contains(print) ? held : held + [print])
            }
            return .loaded
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
