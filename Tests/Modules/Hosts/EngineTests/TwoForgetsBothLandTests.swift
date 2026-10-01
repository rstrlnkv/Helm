import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Two Forgets the engine is asked for at once both land.
///
/// A Forget is read, drop one line, write. The transport's handler is not serial,
/// so two of them run side by side unless something orders them: both read the
/// file with both lines in it, each writes the file without its own line, and
/// the second write puts back the line the first one took away — while both
/// answer `.applied` or `.notVerified` about a trust that is still there.
///
/// The page sends one Forget at a time (`HostsViewModel.forget` refuses a second
/// while one is out), so this is the engine's contract rather than a path a
/// person can reach today: the engine runs Apply's and Forget's writes on one
/// serial queue (`sshWrites`), and this is what that queue owes a second caller.
final class TwoForgetsBothLandTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("known-hosts-two-forgets")

    /// `known_hosts` whose write takes a moment, the way a write to a slow
    /// volume does, so two read-modify-writes that are not ordered overlap.
    private final class SlowKnownHosts: KnownHostsPort, @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private var stored: String
        init(url: URL, text: String) { self.url = url; self.stored = text }
        var text: String { lock.withLock { stored } }
        func read() -> String? { lock.withLock { stored } }
        func write(_ text: String) -> Bool {
            Thread.sleep(forTimeInterval: 0.3)
            lock.withLock { stored = text }
            return true
        }
    }

    private let first = "github.com ssh-ed25519 AAAAB3Nza me@mac"
    private let second = "old.example ssh-rsa AAAAB3Nza me@mac"
    private let third = "keep.example ssh-ed25519 AAAAC3Nza me@mac"

    private static func forget(_ transport: LocalTransport, _ line: String) async throws -> SSHConfigOutcome {
        let reply = try await transport.send(EngineCommand(
            name: HostsCommand.forgetKnownHost.rawValue,
            payload: try JSONEncoder().encode(KnownHostsForget(line: line))))
        return try JSONDecoder().decode(SSHConfigOutcome.self, from: reply)
    }

    func testTwoForgetsAtOnceLeaveNeitherLine() async throws {
        let directory = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("known_hosts")
        let text = [first, second, third].map { $0 + "\n" }.joined()
        try text.write(to: url, atomically: true, encoding: .utf8)
        let port = SlowKnownHosts(url: url, text: text)
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
        defer { engine.deactivate() }

        let first = self.first, second = self.second
        async let a = Self.forget(transport, first)
        async let b = Self.forget(transport, second)
        let outcomes = try await [a, b]

        XCTAssertTrue(port.text.contains(third), "precondition: the line nobody asked about stayed")
        XCTAssertFalse(port.text.contains("github.com"), """
            a Forget answered \(outcomes) and its host is still trusted: two read-modify-writes \
            ran side by side and the later write put the line back — \(port.text)
            """)
        XCTAssertFalse(port.text.contains("old.example"), """
            a Forget answered \(outcomes) and its host is still trusted: \(port.text)
            """)
        XCTAssertEqual(outcomes, [.applied, .applied])
    }
}
