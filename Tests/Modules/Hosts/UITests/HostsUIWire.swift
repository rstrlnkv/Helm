import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Hosts_Engine

/// The wire the pages in this target are drawn against.
///
/// **A test target cannot see another test target's files** — `FakeHostsPorts.swift`
/// lives in `EngineTests` and is invisible from here, so these are this
/// target's own. They are deliberately less capable than the engine-side fakes:
/// the port behaviours belong to the engine's tests, and what is under test
/// here is the view model.
///
/// Each is still free to be in the states the real port can be in, because a
/// fake simpler than the thing it stands for cannot fail the way the thing can:
/// the file can be unreadable, the dialog can be declined, and the folder can
/// already hold copies from a previous run.
struct HostsUIWire {
    let engine: HostsEngine
    let transport: LocalTransport
    let privileged: FixedPrivileged
    let vm: ModuleViewModel

    /// **Every port named at every construction.** A default argument reaches
    /// this machine's real `/etc/hosts` and the real support folder, which is
    /// how eleven Autopilot tests took the Mac's own keychain — and how a
    /// mutation in the engine's own tests reported «274 bytes is not equal to 0
    /// bytes», those bytes being this machine's file.
    ///
    /// Nothing calls `engine.activate()`: the transport replays the last event
    /// per name, so an activated engine would fill a model whether or not it
    /// ever sent a `load`, and every test here would be measuring the replay.
    @MainActor
    static func make(file: String?, privileged: PrivilegedOutcome,
                     backups: [String: String] = [:]) -> HostsUIWire {
        let transport = LocalTransport()
        let root = FixedPrivileged(privileged)
        let engine = HostsEngine(file: FixedFile(file),
                                 privileged: root,
                                 backups: MemoryBackups(backups),
                                 keys: WireKeys(), agent: WireAgent(),
                                 now: { Date(timeIntervalSince1970: 0) },
                                 transport: transport)
        return HostsUIWire(engine: engine, transport: transport, privileged: root,
                           vm: ModuleViewModel(transport: engine.transport))
    }
}

final class FixedFile: HostsFilePort, @unchecked Sendable {
    private let stored: String?
    /// `nil` is «could not be read at all», which is not an empty file.
    init(_ text: String?) { stored = text }
    func read() -> String? { stored }
}

/// Records what it was asked to run, so «the apply carried what is on screen»
/// can be read off the sentence rather than inferred from an outcome.
final class FixedPrivileged: PrivilegedPort, @unchecked Sendable {
    private let lock = NSLock()
    private let outcome: PrivilegedOutcome
    private var ran: [String] = []
    var commands: [String] { lock.withLock { ran } }
    init(_ outcome: PrivilegedOutcome) { self.outcome = outcome }
    func run(_ command: String) -> PrivilegedOutcome {
        lock.withLock { ran.append(command) }
        return outcome
    }
}

final class MemoryBackups: BackupPort, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String]
    init(_ files: [String: String] = [:]) { self.files = files }
    func save(_ text: String, name: String) -> Bool { lock.withLock { files[name] = text }; return true }
    func list() -> [String] { lock.withLock { files.keys.sorted() } }
    func read(_ name: String) -> String? { lock.withLock { files[name] } }
    func delete(_ names: [String]) { lock.withLock { for name in names { files[name] = nil } } }
}

/// `~/.ssh` for the pages in this target: one key, at a mode `ssh` accepts.
///
/// Deliberately fixed. What the ports can do to the engine is the engine
/// tests' subject; what is under test here is the page, and a page needs a
/// keyring that is the same on every run. It is still a keyring a real Mac can
/// have — one key, its public half beside it, the directory at 0700 — rather
/// than an empty one, so the table has a row to draw.
struct WireKeys: SSHKeysPort {
    let directory = URL(fileURLWithPath: "/nowhere/.ssh")
    func names() -> [String]? { ["id_ed25519", "id_ed25519.pub", "known_hosts"] }
    func facts(for pair: KeyInventory.Pair) -> KeyFacts {
        KeyFacts(pair: pair,
                 describeLine: "256 SHA256:abc123 me@mac (ED25519)",
                 mode: 0o600,
                 modified: Date(timeIntervalSince1970: 1_700_000_000),
                 publicText: "ssh-ed25519 AAAA me@mac\n")
    }
    func directoryMode() -> mode_t? { 0o700 }
    func chmod(_ name: String, to mode: mode_t) -> Bool { true }
    func chmodDirectory(to mode: mode_t) -> Bool { true }
}

/// An agent that is running and holding nothing — the state a Mac is in after a
/// restart, and the one where the load buttons are the point.
struct WireAgent: SSHAgentPort {
    func list() -> AgentList { .empty }
    func load(_ name: String) -> Bool { true }
    func unload(_ name: String) -> Bool { true }
}
