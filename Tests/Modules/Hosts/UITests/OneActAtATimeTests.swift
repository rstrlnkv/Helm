import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **The gate on the acts, against a port that has not finished.**
///
/// `HostsViewModel.busy(_:)` takes one row and refuses everything else until it
/// returns. The reason is written where it is taken: two presses of the agent
/// control land a load and an unload whose order nobody controls, and the badge
/// then disagrees with the agent until somebody presses Check.
///
/// **A gate can only be tested against a port that is still working.** Every
/// agent fake in this module answers before it returns — `WireAgent` decides on
/// the spot — so a second press would arrive after the first act was already
/// over, and the test would pass with the gate deleted. `ssh-add` on a key with
/// a passphrase sits for as long as a person takes to type, and the real port
/// waits on the pty for all of it; that is the state this file's agent is in.
///
/// The gate opening again is asserted in the same test as the gate holding. A
/// gate that never opens would satisfy «the second act did not run» just as
/// well, and it is the worse defect of the two — a page where nothing can be
/// pressed again.
@MainActor
final class OneActAtATimeTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-one-act")
    private var engines: [HostsEngine] = []

    /// An agent in the middle of a load, which is where a real one spends the
    /// time somebody is typing a passphrase.
    private final class SittingAgent: SSHAgentPort, @unchecked Sendable {
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var loading = false
        private var acts: [String] = []

        var isLoading: Bool { lock.withLock { loading } }
        var recorded: [String] { lock.withLock { acts } }
        func release() { for _ in 0..<8 { released.signal() } }

        func list() -> AgentList { .empty }

        func load(_ name: String, answering secret: inout Data) -> AgentLoad {
            secret = Data()
            lock.withLock { loading = true; acts.append("load \(name)") }
            _ = released.wait(timeout: .now() + 10)
            lock.withLock { loading = false }
            return .loaded
        }

        func unload(_ name: String) -> Bool {
            lock.withLock { acts.append("unload \(name)") }
            return true
        }
    }

    /// `~/.ssh` with one key at a mode `ssh` refuses — so there is a `chmod` to
    /// run — and a record of every one that was asked for.
    private final class RecordingKeys: SSHKeysPort, @unchecked Sendable {
        let directory = URL(fileURLWithPath: "/nowhere/.ssh")
        private let lock = NSLock()
        private var mode: mode_t = 0o644
        private var asked: [String] = []

        var chmods: [String] { lock.withLock { asked } }

        func names() -> KeyInventory.Listing? { ["id_ed25519", "id_ed25519.pub"] }
        func facts(for pair: KeyInventory.Pair) -> KeyFacts {
            // With the ending the tool really writes; see `FakeSSHKeys.init`.
            KeyFacts(pair: pair, describeLine: "256 SHA256:abc123 me@mac (ED25519)\n",
                     mode: lock.withLock { mode }, modified: nil,
                     publicText: "ssh-ed25519 AAAA me@mac\n")
        }
        func directoryMode() -> mode_t? { 0o700 }
        func chmod(_ name: String, to newMode: mode_t) -> Bool {
            lock.withLock { asked.append(name); mode = newMode }
            return true
        }
        func chmodDirectory(to mode: mode_t) -> Bool { true }
    }

    private struct RefusingGenerator: KeyGeneratorPort {
        func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
            secret = Data()
            return 1
        }
    }

    func testASecondActWaitsForTheFirstAndThenRuns() async {
        let agent = SittingAgent()
        let keys = RecordingKeys()
        let transport = LocalTransport()
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: WireSSHConfig(),
                                 knownHosts: WireKnownHosts(), keys: keys, agent: agent,
                                 generator: RefusingGenerator(), home: home, transport: transport)
        engines.append(engine)
        let hvm = HostsViewModel(vm: ModuleViewModel(transport: engine.transport))
        addTeardownBlock { await MainActor.run { hvm.stop() } }
        await hvm.firstLoad?.value
        await waitUntil("the first snapshot arrived") { !hvm.keys.isEmpty }
        XCTAssertEqual(hvm.keys.first?.permission, .tooOpen(fix: 0o600),
                       "precondition: there is a `chmod` for the second act to run")

        let loading = Task { await hvm.load("id_ed25519", passphrase: "open") }
        await waitUntil("the agent is in the middle of a load") { agent.isLoading }
        XCTAssertEqual(hvm.busyKey, "id_ed25519", "precondition: the row is marked busy")

        // The second press, while the first act is still inside the port.
        await hvm.fixPermissions(of: "id_ed25519")
        XCTAssertEqual(keys.chmods, [], """
            a second act ran while the first was still inside its port. On the agent control \
            that is a load and an unload landing in an order nobody chose, and the badge \
            disagreeing with the agent until somebody presses Check.
            """)

        agent.release()
        await loading.value
        XCTAssertNil(hvm.busyKey, "the row was left busy after the act returned")

        // And the gate opens again — a gate that never does would pass the
        // assertion above and leave a page where nothing can be pressed twice.
        await hvm.fixPermissions(of: "id_ed25519")
        XCTAssertEqual(keys.chmods, ["id_ed25519"],
                       "the act refused while the page was busy never ran afterwards either")
    }
}
