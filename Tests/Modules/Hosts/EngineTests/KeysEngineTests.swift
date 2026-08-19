import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Tab 3's acts: the reading, the `chmod`, and the two the agent answers.
///
/// Every port is named at every construction. A default here reaches the
/// owner's own `~/.ssh` — and `agentUnload` against it would take their key out
/// of their running agent, which is the Autopilot lesson with somebody's live
/// SSH session in the blast radius.
final class KeysEngineTests: XCTestCase {

    private struct Bench {
        let engine: HostsEngine
        let keys: FakeSSHKeys
        let agent: FakeSSHAgent
        let transport: LocalTransport
    }

    private func bench(keys: FakeSSHKeys = FakeSSHKeys(),
                       agent: FakeSSHAgent = FakeSSHAgent()) -> Bench {
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let home = scratchDirectory("keys-engine")
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(
                                    url: home.appendingPathComponent(".ssh/config"),
                                    text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(),
                                 keys: keys, agent: agent,
                                 home: home,
                                 transport: transport)
        return Bench(engine: engine, keys: keys, agent: agent, transport: transport)
    }

    private func state(_ transport: LocalTransport) async throws -> HostsState {
        let reply = try await transport.send(EngineCommand(name: HostsCommand.load.rawValue,
                                                           payload: Data()))
        return try JSONDecoder().decode(HostsState.self, from: reply)
    }

    private func act(_ transport: LocalTransport, _ command: HostsCommand,
                     _ name: String = "id_ed25519") async throws -> KeyOutcome {
        let payload = command == .fixDirectoryPermissions
            ? Data() : try JSONEncoder().encode(KeyName(name: name))
        let reply = try await transport.send(EngineCommand(name: command.rawValue,
                                                           payload: payload))
        return try JSONDecoder().decode(KeyOutcome.self, from: reply)
    }

    // MARK: - The reading

    func testTheStateCarriesARowPerPairWithItsBadge() async throws {
        let b = bench(agent: FakeSSHAgent(.holding(["SHA256:abc123"])))
        let state = try await state(b.transport)
        XCTAssertTrue(state.keysReadable)
        XCTAssertEqual(state.keys.map(\.name), ["id_ed25519"], "known_hosts is not a key")
        XCTAssertEqual(state.keys.first?.described?.type, "ED25519")
        XCTAssertTrue(state.keys.first?.inAgent ?? false)
        XCTAssertEqual(state.directoryPermission, .ok)
    }

    /// **A directory nobody could read is not a Mac with no keys.** The page
    /// says a different sentence for each, and folding them would have Helm
    /// claim somebody has no keys on the strength of a failed `readdir`.
    func testADirectoryThatCannotBeReadIsNotAnEmptyOne() async throws {
        let keys = FakeSSHKeys()
        let b = bench(keys: keys)
        let before = try await state(b.transport)
        XCTAssertTrue(before.keysReadable, "precondition: it was readable")

        keys.becomesUnreadable()
        let state = try await state(b.transport)
        XCTAssertFalse(state.keysReadable)
        XCTAssertTrue(state.keys.isEmpty)
        XCTAssertEqual(state.directoryPermission, .unknown,
                       "a directory nobody could read has no verdict, and «ok» is a verdict")
    }

    // MARK: - The fix

    func testTooOpenIsFixedAndTheNextReadingSaysSo() async throws {
        let b = bench(keys: FakeSSHKeys(modes: ["id_ed25519": 0o644]))
        let before = try await state(b.transport)
        XCTAssertEqual(before.keys.first?.permission, .tooOpen(fix: 0o600),
                       "precondition: the key is in the state this button is for")

        let outcome = try await act(b.transport, .fixKeyPermissions)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(b.keys.chmods, ["id_ed25519"])
        let after = try await state(b.transport)
        XCTAssertEqual(after.keys.first?.permission, .ok)
    }

    /// The button is idempotent, because a page one refresh out of date must not
    /// turn a no-op into a failure — and nothing is run, because a `chmod` over
    /// a file that does not need one is a write nobody asked for.
    func testAKeyThatIsAlreadyFineIsNotWrittenTo() async throws {
        let b = bench()
        let outcome = try await act(b.transport, .fixKeyPermissions)
        XCTAssertEqual(outcome, .done)
        XCTAssertTrue(b.keys.chmods.isEmpty)
    }

    /// **A mode that could not be read is never fixed.** Writing 0600 over a
    /// file this process could not `stat` is a guess about somebody's key, and
    /// the honest answer is that Helm does not know.
    func testAModeNobodyCouldReadIsNotWrittenOver() async throws {
        let b = bench(keys: FakeSSHKeys(modes: [:]))
        let before = try await state(b.transport)
        XCTAssertEqual(before.keys.first?.permission, .unknown,
                       "precondition: the mode is the unknown this test is about")
        let outcome = try await act(b.transport, .fixKeyPermissions)
        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(b.keys.chmods.isEmpty, "a mode was written over a file nobody could read")
    }

    func testAChmodThePortRefusesIsAFailureAndNotASilentOne() async throws {
        let keys = FakeSSHKeys(modes: ["id_ed25519": 0o644])
        keys.refusesToChangeModes()
        let b = bench(keys: keys)
        let outcome = try await act(b.transport, .fixKeyPermissions)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(b.keys.chmods, ["id_ed25519"], "it did not even try")
    }

    /// A name from a payload may only ever select a key the engine can see. The
    /// traversal is the case worth writing down: nothing here composes a path,
    /// so the refusal is «that is not one of the keys» rather than a resolution.
    func testANameThatIsNotOneOfTheKeysRunsNothing() async throws {
        let b = bench()
        let traversal = try await act(b.transport, .fixKeyPermissions, "../../.zshrc")
        let furniture = try await act(b.transport, .fixKeyPermissions, "known_hosts")
        let absent = try await act(b.transport, .agentLoad, "id_rsa")
        XCTAssertEqual(traversal, .notFound)
        XCTAssertEqual(furniture, .notFound)
        XCTAssertEqual(absent, .notFound)
        XCTAssertTrue(b.keys.chmods.isEmpty)
        XCTAssertTrue(b.agent.acts.isEmpty)
    }

    func testTheDirectoryHasItsOwnFix() async throws {
        let b = bench(keys: FakeSSHKeys(directoryMode: 0o755))
        let before = try await state(b.transport)
        XCTAssertEqual(before.directoryPermission, .tooOpen(fix: 0o700))
        let outcome = try await act(b.transport, .fixDirectoryPermissions)
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(b.keys.chmods, ["."])
        let after = try await state(b.transport)
        XCTAssertEqual(after.directoryPermission, .ok)
    }

    // MARK: - The agent

    func testLoadingPutsTheKeyInAndTheBadgeComesOn() async throws {
        let b = bench()
        let before = try await state(b.transport)
        XCTAssertFalse(before.keys.first?.inAgent ?? true,
                       "precondition: the agent is running and holding nothing")
        let loaded = try await act(b.transport, .agentLoad)
        XCTAssertEqual(loaded, .done)
        let holding = try await state(b.transport)
        XCTAssertTrue(holding.keys.first?.inAgent ?? false)

        let unloaded = try await act(b.transport, .agentUnload)
        XCTAssertEqual(unloaded, .done)
        let empty = try await state(b.transport)
        XCTAssertFalse(empty.keys.first?.inAgent ?? true)
    }

    /// **An agent that is not there is answered before anything is attempted.**
    /// A load against a dead socket fails in a way that reads like a problem
    /// with the key — and the key is fine, there is no agent. The act must not
    /// even reach the port, or the log fills with refusals about keys.
    func testAnAgentThatIsNotThereIsItsOwnAnswer() async throws {
        let agent = FakeSSHAgent()
        let b = bench(agent: agent)
        agent.goesAway()
        let outcome = try await act(b.transport, .agentLoad)
        XCTAssertEqual(outcome, .agentUnreachable)
        XCTAssertTrue(b.agent.acts.isEmpty, "a load was attempted against an agent that is gone")
    }

    /// An encrypted key is the ordinary reason `ssh-add` says no: it wants a
    /// passphrase and this path has no channel for one. A failure, not a
    /// pretence of success.
    func testAKeyTheAgentRefusesIsAFailure() async throws {
        let b = bench(agent: FakeSSHAgent(.empty, refuses: true))
        let outcome = try await act(b.transport, .agentLoad)
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(b.agent.acts, ["load id_ed25519"])
    }
}
