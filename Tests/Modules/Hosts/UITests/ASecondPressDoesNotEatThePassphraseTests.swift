import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **A refusal the row cannot see is a refusal that costs the typed
/// passphrase.**
///
/// `KeyCard.unlock()` empties its `SecureField` and *then* sends, and
/// `HostsViewModel.load` opens with `guard busyKey == nil else { return }` —
/// so a second press while the first is in flight is dropped after the field
/// has already been cleared. What the person typed is gone, the row says
/// nothing, and the state it is left in is «this key is locked» with an empty
/// box.
///
/// The press is reachable: the button is `.disabled(… || anyBusy)`, but the
/// field's `.onSubmit` is not, so two quick Returns are two presses.
///
/// The repair is that the act answers whether it ran, and the row keeps the
/// text until it did. This holds the answering half — the half that can be
/// asked of a value rather than of a rendered view — and a `false` here is
/// what the row now reads before it clears anything.
@MainActor
final class ASecondPressDoesNotEatThePassphraseTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-second-press")
    /// Held: the transport's handler holds the engine weakly.
    private var engines: [HostsEngine] = []

    /// An agent that is in the middle of a load — the state the second press
    /// arrives in. **A fake that answers on the spot makes this vacuous**: the
    /// first act would be over before the second was made, and the gate would
    /// never be closed.
    private final class SittingAgent: SSHAgentPort, @unchecked Sendable {
        private let released = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var loads = 0
        private var inFlight = false

        var loadCount: Int { lock.withLock { loads } }
        /// Read by an `await waitUntil`, never by a semaphore the test blocks
        /// on: the model is `@MainActor`, and a main thread parked in `wait()`
        /// is a main thread the first load cannot get past — which would make
        /// the second press arrive with the gate still open.
        var isLoading: Bool { lock.withLock { inFlight } }
        func release() { for _ in 0..<8 { released.signal() } }

        func list() -> AgentList { .empty }
        func load(_ name: String, answering secret: inout Data) -> AgentLoad {
            lock.withLock { loads += 1; inFlight = true }
            secret.resetBytes(in: secret.startIndex..<secret.endIndex)
            secret = Data()
            // The pool thread waits here, never the caller's — the engine runs
            // this through `offTheCooperativePool`.
            _ = released.wait(timeout: .now() + 5)
            lock.withLock { inFlight = false }
            return .loaded
        }
        func unload(_ name: String) -> Bool { true }
    }

    private func model(_ agent: SSHAgentPort) async -> HostsViewModel {
        let transport = LocalTransport()
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: WireSSHConfig(),
                                 knownHosts: WireKnownHosts(), keys: WireKeys(),
                                 agent: agent, generator: WireKeyGenerator(),
                                 home: URL(fileURLWithPath: "/nowhere"),
                                 transport: transport)
        engines.append(engine)
        let model = HostsViewModel(vm: ModuleViewModel(transport: engine.transport))
        addTeardownBlock { await MainActor.run { model.stop() } }
        await model.firstLoad?.value
        await waitUntil("the first snapshot arrived") { !model.keys.isEmpty }
        return model
    }

    /// The control, on the same model and the same wire: a load nobody is
    /// racing answers «taken», so a `false` below is about the gate rather than
    /// about loads never being taken at all.
    func testALoadNobodyIsRacingSaysItWasTaken() async {
        let agent = SittingAgent()
        agent.release()
        let hvm = await model(agent)

        let taken = await hvm.load("id_ed25519", passphrase: "open")

        XCTAssertTrue(taken, "no load is ever reported as taken, so the reading below is vacuous")
        XCTAssertEqual(agent.loadCount, 1, "precondition: the agent really was asked")
    }

    /// **The finding.** The second press is refused, and the row has to be able
    /// to know so — otherwise it has already thrown the passphrase away.
    func testASecondPressWhileTheFirstIsInFlightSaysItWasNotTaken() async {
        let agent = SittingAgent()
        let hvm = await model(agent)

        let first = Task { await hvm.load("id_ed25519", passphrase: "open") }
        await waitUntil("the first load is in flight") { agent.isLoading }

        let second = await hvm.load("id_ed25519", passphrase: "open-again")

        XCTAssertFalse(second, """
            a load refused by the busy gate reported itself as done. The row empties its \
            SecureField before it sends, so a second press — two quick Returns, which the \
            field's `onSubmit` does not disable — loses what was typed with nothing said, and \
            leaves «this key is locked» over an empty box.
            """)
        XCTAssertEqual(agent.loadCount, 1, "the gate let a second load through")
        agent.release()
        _ = await first.value
    }
}
