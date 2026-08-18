import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Writing `~/.ssh/config` — the half of tab 2 that touches the disk.
///
/// The file is the person's own, so there is no dialog and no backup, and the
/// two things standing in their place are the gate and the read-back. Both are
/// exercised here against a fake that can do what the real port can: fail, and
/// **report success over a file it did not change**.
final class SSHConfigApplyTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("ssh-apply")

    /// A home with a `.ssh/config` in it, and the engine pointed at it. Every
    /// port is named — a default argument here would reach the owner's own
    /// `~/.ssh/config`, which is the Autopilot lesson with somebody's SSH setup
    /// in the blast radius.
    /// The bench: the engine, the port it writes through, and the wire it
    /// speaks on. A struct rather than a tuple, because three members is one
    /// past what this house reads by position.
    private struct Bench {
        let engine: HostsEngine
        let port: FakeSSHConfig
        let transport: LocalTransport
    }

    private func bench(text: String = "Host a\n    HostName a.example\n",
                       behaviour: FakeSSHConfig.Behaviour = .ordinary) -> Bench {
        let directory = home.appendingPathComponent(".ssh")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        let port = FakeSSHConfig(url: url, text: text, behaviour: behaviour)
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(), sshConfig: port, home: home,
                                 transport: transport)
        return Bench(engine: engine, port: port, transport: transport)
    }

    private func apply(_ transport: LocalTransport,
                       _ text: String) async throws -> SSHConfigOutcome {
        let reply = try await transport.send(EngineCommand(
            name: HostsCommand.applySSHConfig.rawValue,
            payload: try JSONEncoder().encode(SSHConfigApply(text: text))))
        return try JSONDecoder().decode(SSHConfigOutcome.self, from: reply)
    }

    func testAnOrdinaryWriteIsAppliedAndLandsInTheFile() async throws {
        let b = bench()
        b.engine.activate()
        let wanted = "Host a\n    HostName b.example\n"
        let outcome = try await apply(b.transport, wanted)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(b.port.read(), wanted)
    }

    /// The port says it wrote and the file is unchanged. Without this the
    /// read-back is a line of code nothing asks for.
    func testAWriteThatReportsSuccessOverAnUnchangedFileIsNotVerified() async throws {
        let b = bench(behaviour: .lie)
        b.engine.activate()
        let before = b.port.read()
        let outcome = try await apply(b.transport, "Host a\n    HostName c.example\n")
        XCTAssertEqual(outcome, .notVerified)
        XCTAssertEqual(b.port.read(), before, "the fake was supposed to change nothing")
    }

    func testAWriteThatFailsIsReportedAsFailed() async throws {
        let b = bench(behaviour: .refuse)
        b.engine.activate()
        let outcome = try await apply(b.transport, "Host a\n")
        XCTAssertEqual(outcome, .failed)
    }

    /// The gate, from the engine's side: a port pointed out of the home
    /// directory is refused, **and nothing is written** — the refusal has to
    /// come before the write, not be discovered after it.
    func testAPathOutsideTheHomeDirectoryIsRefusedWithoutWriting() async throws {
        let outside = scratchDirectory("ssh-elsewhere").appendingPathComponent("config")
        try "Host a\n".write(to: outside, atomically: true, encoding: .utf8)
        let port = FakeSSHConfig(url: outside, text: "Host a\n", behaviour: .ordinary)
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(), sshConfig: port, home: home,
                                 transport: transport)
        engine.activate()
        let outcome = try await apply(transport, "Host b\n")
        XCTAssertEqual(outcome, .outOfScope)
        XCTAssertEqual(port.writes, 0, "a refused path was written to anyway")
    }

    /// The state carries the config, and says whether it may be written — the
    /// page draws Apply from that, so a page that offers it on a file the
    /// engine will refuse is a page that lies at the last moment.
    func testTheStateCarriesTheConfigAndWhetherItMayBeWritten() async throws {
        let b = bench(text: "Host reachable\n")
        b.engine.activate()
        var seen: HostsState?
        for await event in b.transport.events where HostsEvent(rawValue: event.name) == .state {
            seen = try JSONDecoder().decode(HostsState.self, from: event.payload)
            break
        }
        XCTAssertEqual(seen?.sshText, "Host reachable\n")
        XCTAssertEqual(seen?.sshReadable, true)
        XCTAssertEqual(seen?.sshWritable, true)
    }

    /// A config that is not there is not an empty config — the same distinction
    /// `hostsReadable` carries, and the page needs it to tell «you have no SSH
    /// config» from «your SSH config is empty».
    func testAMissingConfigReadsAsUnreadableRatherThanEmpty() async throws {
        let b = bench()
        b.port.changeUnderTheApp(to: nil)
        b.engine.activate()
        var seen: HostsState?
        for await event in b.transport.events where HostsEvent(rawValue: event.name) == .state {
            seen = try JSONDecoder().decode(HostsState.self, from: event.payload)
            break
        }
        XCTAssertEqual(seen?.sshText, "")
        XCTAssertEqual(seen?.sshReadable, false)
    }
}
