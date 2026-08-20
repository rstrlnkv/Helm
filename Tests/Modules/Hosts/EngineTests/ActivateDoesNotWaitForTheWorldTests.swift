import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// **`activate()` is called on the thread that draws, and this one reads
/// `~/.ssh` and spawns a child per key before it returns.**
///
/// `ModuleHost` is `@MainActor` (`Sources/HelmApp/ModuleHost.swift`, line 8) and
/// calls `engine.activate()` from `enable(_:)` (line 104), which runs at
/// bootstrap for every enabled module and again whenever somebody flips a
/// module's switch. Every other engine's `activate()` is empty or a store read.
/// This one is `emitState()`, and `emitState()` is:
///
/// - `/etc/hosts` and `~/.ssh/config` read;
/// - `ssh-add -l` — a round trip to a socket, through `HelmProcess`, bounded at
///   **5 seconds**;
/// - `ssh-keygen -l` **per key**, each bounded at 5 seconds;
/// - `~/.ssh/known_hosts` read, and two `stat`-and-resolve passes for the gate.
///
/// A Mac whose `SSH_AUTH_SOCK` points at a socket nobody is answering, or whose
/// `~/.ssh` is on a stalled network mount, therefore holds the main thread for
/// as long as those deadlines allow — with the menu bar not yet drawn. The
/// deadlines are the *proof* that these calls can sit: they were chosen
/// («both tools can sit», `SystemSSHKeys`) because they can.
///
/// The reading below cannot be satisfied by luck. The port sits until it is
/// released, so a synchronous `activate()` cannot return before it — no load on
/// this machine can make a blocking call fast — and a green result means the
/// call really did hand the work to somebody else.
@MainActor
final class ActivateDoesNotWaitForTheWorldTests: XCTestCase {

    /// A port that is in the state a real one reaches: asked, and not yet
    /// answering. **A fake that has always already answered makes this
    /// vacuous** — the subject would be over before the code under test runs.
    private final class SittingAgent: SSHAgentPort, @unchecked Sendable {
        private let asked = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var entered = false
        private var returned = false

        /// True once `list()` has been reached — so «it returned quickly»
        /// cannot be green because nothing was ever called.
        var wasAsked: Bool { lock.withLock { entered } }
        var hasReturned: Bool { lock.withLock { returned } }

        func waitUntilAsked(_ seconds: TimeInterval) -> Bool {
            asked.wait(timeout: .now() + seconds) == .success
        }

        /// The socket answers at last. Generously, so a second reading — an
        /// emission from another path — cannot leave a thread parked here.
        func release() { for _ in 0..<8 { released.signal() } }

        func list() -> AgentList {
            lock.withLock { entered = true }
            asked.signal()
            // Bounded, so a blocking `activate()` fails this test rather than
            // hanging the suite: a hang is not a failing guard.
            _ = released.wait(timeout: .now() + 5)
            lock.withLock { returned = true }
            return .empty
        }

        func load(_ name: String, answering secret: inout Data) -> AgentLoad {
            secret = Data()
            return .failed
        }

        func unload(_ name: String) -> Bool { false }
    }

    private lazy var home: URL = scratchDirectory("hosts-activate")

    func testActivateReturnsBeforeTheAgentHasAnswered() {
        let agent = SittingAgent()
        let hosts = FakeHostsFile()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/c"),
                                                          text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(),
                                 agent: agent, generator: FakeGenerator(),
                                 home: home, transport: LocalTransport())
        addTeardownBlock {
            agent.release()
            engine.deactivate()
        }

        let started = Date()
        engine.activate()
        let took = Date().timeIntervalSince(started)
        agent.release()

        // `waitUntilAsked` rather than `wasAsked`, and the difference is the
        // repair. The control has to prove the reading really happened; it must
        // not also require it to have *started* before `activate()` returned,
        // which is a fact about queue latency that no correct repair can
        // promise — an `activate()` that waited for its worker to pick the work
        // up would be blocking the drawing thread again, on something with no
        // deadline at all. The bound below is what holds the other half.
        XCTAssertTrue(agent.waitUntilAsked(2), """
            the agent was never asked, so «activate returned quickly» is green because nothing \
            happened — the reading below would be taken over a call that did no work
            """)
        XCTAssertLessThan(took, 1, """
            `activate()` took \(took) s and did not return until the agent answered. It is called \
            from `ModuleHost.enable`, which is `@MainActor`, at every launch: on a Mac whose \
            `SSH_AUTH_SOCK` is a dead socket that is `ssh-add -l`'s whole 5 s deadline with the \
            window not yet drawn — and one `ssh-keygen -l` per key after it, each with 5 s of \
            its own. The state has to go out; the main thread does not have to wait for it.
            """)
    }

    /// The other half, and the reason the first is not «make `activate` do
    /// nothing»: whatever it hands the work to, the state still has to arrive.
    /// A subscriber that never receives one is a page stuck on its defaults.
    func testTheStateStillArrives() async {
        let agent = SittingAgent()
        let hosts = FakeHostsFile("127.0.0.1\tlocalhost\n")
        let transport = LocalTransport()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/c"),
                                                          text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(),
                                 agent: agent, generator: FakeGenerator(),
                                 home: home, transport: transport)
        addTeardownBlock { engine.deactivate() }

        engine.activate()
        agent.release()

        let states = ProgressBox()
        let events = Task {
            for await event in transport.events where event.name == HostsEvent.state.rawValue {
                states.record(1)
                break
            }
        }
        await waitUntil("the state was emitted") { states.value > 0 }
        events.cancel()
    }
}
