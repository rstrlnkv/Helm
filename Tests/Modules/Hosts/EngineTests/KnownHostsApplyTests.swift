import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Writing `~/.ssh/known_hosts` — the same three steps as the config next door,
/// against a port that can do what the real one can: fail, and **report success
/// over a file it did not change.**
final class KnownHostsApplyTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("known-hosts")

    private struct Bench {
        let engine: HostsEngine
        let port: FakeKnownHosts
        let transport: LocalTransport
    }

    private func bench(text: String? = "github.com ssh-ed25519 AAAAB3 me@mac\n",
                       behaviour: FakeKnownHosts.Behaviour = .ordinary) -> Bench {
        let directory = home.appendingPathComponent(".ssh")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("known_hosts")
        try? (text ?? "").write(to: url, atomically: true, encoding: .utf8)
        let port = FakeKnownHosts(url: url, text: text, behaviour: behaviour)
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(
                                    url: URL(fileURLWithPath: "/nowhere/.ssh/config"),
                                    text: "Host a\n"),
                                 knownHosts: port, keys: FakeSSHKeys(), agent: FakeSSHAgent(),
                                 generator: FakeGenerator(),
                                 home: home, transport: transport)
        return Bench(engine: engine, port: port, transport: transport)
    }

    /// The act is one line, by its own bytes — the engine reads the file again
    /// and removes it from what it finds there.
    private func forget(_ transport: LocalTransport, _ line: String) async throws
        -> SSHConfigOutcome {
        let reply = try await transport.send(EngineCommand(
            name: HostsCommand.forgetKnownHost.rawValue,
            payload: try JSONEncoder().encode(KnownHostsForget(line: line))))
        return try JSONDecoder().decode(SSHConfigOutcome.self, from: reply)
    }

    private func state(_ transport: LocalTransport) async throws -> HostsState {
        let reply = try await transport.send(EngineCommand(name: HostsCommand.load.rawValue,
                                                           payload: Data()))
        return try JSONDecoder().decode(HostsState.self, from: reply)
    }

    func testForgettingAHostLandsInTheFile() async throws {
        let b = bench(text: "github.com ssh-ed25519 AAAAB3 me@mac\nold.example ssh-rsa AAAAB3\n")
        b.engine.activate()
        let line = KnownHostsFile.parse(b.port.read() ?? "").entries[0].raw

        let outcome = try await forget(b.transport, line)
        XCTAssertEqual(outcome, .applied)
        XCTAssertFalse(b.port.read()?.contains("github.com") ?? true)
        XCTAssertTrue(b.port.read()?.contains("old.example") ?? false,
                      "the line beside it went too")
        // An engine that matched no line ever would report `.applied` over an
        // untouched file; the count is what keeps that from passing.
        XCTAssertEqual(b.port.writeCount, 1, "the file was not written at all")
    }

    /// **A write that reports success over a file it did not change is believed
    /// by nothing.** The read-back is the whole defence here — there is no
    /// backup and no password dialog on this file.
    func testAPortThatLiesAboutTheWriteIsCaught() async throws {
        let b = bench(behaviour: .lie)
        b.engine.activate()
        let outcome = try await forget(b.transport, "github.com ssh-ed25519 AAAAB3 me@mac")
        XCTAssertEqual(outcome, .notVerified)
        XCTAssertEqual(b.port.writeCount, 1, "precondition: the write was attempted")
    }

    func testAWriteThePortRefusesIsAFailure() async throws {
        let b = bench(behaviour: .refuse)
        b.engine.activate()
        let outcome = try await forget(b.transport, "github.com ssh-ed25519 AAAAB3 me@mac")
        XCTAssertEqual(outcome, .failed)
    }

    /// A Mac that has never connected anywhere has no such file. That is not an
    /// empty one, and the page draws a different thing for each.
    func testAFileThatIsNotThereIsNotAnEmptyOne() async throws {
        let b = bench(text: nil)
        let state = try await state(b.transport)
        XCTAssertFalse(state.knownHostsReadable)
        XCTAssertEqual(state.knownHostsText, "")
    }

    /// The gate refuses a path outside the folder it was told to work in, and
    /// nothing is written — the fifth gate, asked of this file exactly as it is
    /// asked of the config.
    func testAPathOutsideTheSSHFolderIsRefused() async throws {
        let outside = home.appendingPathComponent(".zshrc")
        try? "".write(to: outside, atomically: true, encoding: .utf8)
        let port = FakeKnownHosts(url: outside, text: "")
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(
                                    url: URL(fileURLWithPath: "/nowhere/.ssh/config"),
                                    text: "Host a\n"),
                                 knownHosts: port, keys: FakeSSHKeys(), agent: FakeSSHAgent(),
                                 generator: FakeGenerator(),
                                 home: home, transport: transport)
        engine.activate()
        let outcome = try await forget(transport, "anything")
        XCTAssertEqual(outcome, .outOfScope)
        XCTAssertEqual(port.writeCount, 0, "a refused path was written to anyway")
    }
}
