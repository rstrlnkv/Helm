import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// **Zeroing a `Data` that somebody else is still holding zeroes a copy.**
///
/// The whole passphrase design rests on one sentence, written in three places:
/// «the secret is `inout` all the way down and the port zeroes it, so this
/// function holds nothing to leak after the call returns»
/// (`HostsEngine.generate`), «after this returns there is nothing in the
/// caller's buffer to leak» (`KeyGeneratorPort.generate`), «zeroed on every
/// path out» (`PTYProcess`).
///
/// `Data` is copy-on-write. `resetBytes` writes through the buffer **only while
/// that buffer is uniquely referenced**; with a second live reference it
/// allocates, zeroes the new allocation and leaves the old bytes exactly where
/// they were. Both call sites keep one:
///
/// ```swift
/// let secret = request.passphrase            // HostsEngine.generate
/// … { var carried = secret; … generator.generate(arguments, answering: &carried) }
/// ```
///
/// So the buffer the port is handed is never unique, `resetBytes` never reaches
/// the passphrase the person typed, and it stays in freed heap memory for the
/// life of the process.
///
/// **Why no existing test can see it.** `FakeGenerator` and `FakeSSHAgent` both
/// take a copy of the secret before zeroing it (`answers.append(secret)`,
/// `let given = secret`) so a test can assert what the tool was answered with —
/// and that copy *is* a second reference, which forces the copy-on-write
/// whatever the engine did. A fake that records the secret cannot measure
/// whether the secret was reachable.
///
/// The reading below is the buffer's own address, taken inside the port before
/// and after the zeroing it is documented to do. Same address: the write landed
/// on the caller's bytes. Different address: it landed on a copy, and the
/// caller's bytes are still the passphrase.
///
/// **The request travels as JSON, exactly as it does in the app.** A test that
/// built the `Request` and held it would be a second reference of its own —
/// planting a state production never has, and failing whatever the engine did.
///
/// **What this asks is necessary and not sufficient, and the fix must not stop
/// at it.** Measured: replacing `var carried = secret` with
/// `var carried = Data(secret)` turns the generator's case green here, because
/// the port then holds the only reference to *that* buffer — and the original
/// is still the passphrase, one copy further away. What actually empties the
/// heap is moving the buffer rather than copying it: one `var` all the way from
/// the decode to the `inout` argument, with nothing alongside it. Read the
/// fix, not only this file's colour.
final class TheSecretIsHandedOverUniquelyTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-secret")

    /// Long enough that `Data` keeps it on the heap rather than inline in the
    /// struct — 14 bytes is where the representation changes, and the address
    /// of an inline value is a temporary. A passphrase out of a password
    /// manager is this long.
    private let passphrase = Data("correct-horse-battery-staple-0123".utf8)

    // MARK: - Ports that report what the engine handed them

    /// What one hand-over came to.
    private struct HandOver: Sendable {
        let before: UInt
        let after: UInt
        let count: Int
        /// True when `resetBytes` wrote through the caller's own buffer.
        var wasUnique: Bool { before == after }
    }

    /// A box the two ports below report into. One lock and one slot: the same
    /// shape `ProgressBox` has, kept here because what it carries is this
    /// file's own reading.
    private final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [HandOver] = []
        var all: [HandOver] { lock.withLock { seen } }
        func record(_ handOver: HandOver) { lock.withLock { seen.append(handOver) } }
    }

    /// The zeroing `PTYProcess.zero(_:)` does, and nothing else.
    ///
    /// **It takes no copy of the secret**, deliberately: a copy is a second
    /// reference, and this port exists to measure whether the engine left one.
    private static func zeroAndReport(_ secret: inout Data, into reports: Reports) {
        let before = secret.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        let count = secret.count
        secret.resetBytes(in: 0..<secret.count)
        let after = secret.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        secret = Data()
        reports.record(HandOver(before: before, after: after, count: count))
    }

    private final class ReportingGenerator: KeyGeneratorPort, @unchecked Sendable {
        let reports = Reports()
        func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
            TheSecretIsHandedOverUniquelyTests.zeroAndReport(&secret, into: reports)
            return 0
        }
    }

    /// The agent takes the same secret down the same shape of path, and its
    /// call site keeps the same extra reference.
    private final class ReportingAgent: SSHAgentPort, @unchecked Sendable {
        let reports = Reports()
        func list() -> AgentList { .empty }
        func load(_ name: String, answering secret: inout Data) -> AgentLoad {
            TheSecretIsHandedOverUniquelyTests.zeroAndReport(&secret, into: reports)
            return .loaded
        }
        func unload(_ name: String) -> Bool { true }
    }

    // MARK: - The bench

    private func bench(generator: KeyGeneratorPort = SilentGenerator(),
                       agent: SSHAgentPort = FakeSSHAgent(),
                       transport: LocalTransport) -> HostsEngine {
        let hosts = FakeHostsFile()
        return HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                           backups: FakeBackups(),
                           sshConfig: FakeSSHConfig(url: URL(fileURLWithPath: "/nowhere/config"),
                                                    text: "Host a\n"),
                           knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(),
                           agent: agent, generator: generator, home: home, transport: transport)
    }

    /// Stands in for the generator when the agent is the subject.
    private final class SilentGenerator: KeyGeneratorPort {
        func generate(_ arguments: [String], answering secret: inout Data) -> Int32 {
            secret = Data()
            return 0
        }
    }

    private func send(_ command: HostsCommand, _ payload: some Encodable,
                      to transport: LocalTransport) async throws {
        _ = try await transport.send(EngineCommand(name: command.rawValue,
                                                   payload: try JSONEncoder().encode(payload)))
    }

    // MARK: - The two paths a passphrase takes

    func testTheGeneratorIsHandedTheOnlyCopyOfThePassphrase() async throws {
        let transport = LocalTransport()
        let generator = ReportingGenerator()
        // Held for the length of the call: an engine nobody refers to is an
        // engine whose transport handler has gone.
        let engine = bench(generator: generator, transport: transport)
        defer { engine.deactivate() }

        try await send(.generateKey,
                       KeyGeneration.Request(type: .ed25519, name: "fresh_key",
                                             comment: "me@mac", passphrase: passphrase),
                       to: transport)

        guard let handOver = generator.reports.all.first else {
            return XCTFail("the generator was never run, so nothing below was measured")
        }
        XCTAssertEqual(handOver.count, passphrase.count,
                       "precondition: the passphrase reached the tool at all")
        XCTAssertTrue(handOver.wasUnique, """
            the engine handed the generator a buffer it was still holding another reference to \
            (`let secret = request.passphrase`, then `var carried = secret`). `Data` is \
            copy-on-write, so the port's `resetBytes` allocated \(handOver.after) and zeroed \
            that, leaving the passphrase at \(handOver.before) — where it stays, unreferenced \
            and un-overwritten, for the life of the process. Every sentence in this module \
            about the secret being zeroed is about the copy.
            """)
    }

    func testTheAgentIsHandedTheOnlyCopyOfThePassphrase() async throws {
        let transport = LocalTransport()
        let agent = ReportingAgent()
        let engine = bench(agent: agent, transport: transport)
        defer { engine.deactivate() }

        try await send(.agentLoad, KeyLoad(name: "id_ed25519", passphrase: passphrase),
                       to: transport)

        guard let handOver = agent.reports.all.first else {
            return XCTFail("the agent was never asked, so nothing below was measured")
        }
        XCTAssertEqual(handOver.count, passphrase.count,
                       "precondition: the passphrase reached the tool at all")
        XCTAssertTrue(handOver.wasUnique, """
            the engine handed `ssh-add` a buffer it was still holding another reference to \
            (`var carried = passphrase`, with the parameter alive beside it), so the zeroing \
            landed on a copy and the typed passphrase is still at \(handOver.before).
            """)
    }

    /// **The reading itself, proved against a buffer nobody else holds.**
    ///
    /// Without this the two tests above could be measuring a property of
    /// `resetBytes` rather than of the engine — an address that always changes
    /// would make `wasUnique` a check that cannot pass, which is as useless as
    /// one that cannot fail.
    func testAUniquelyHeldBufferIsZeroedInPlace() {
        let reports = Reports()
        // Built here and referred to nowhere else — not `= passphrase`, which
        // would share this file's own buffer and be the very state under test.
        var alone = Data("correct-horse-battery-staple-0123".utf8)
        Self.zeroAndReport(&alone, into: reports)
        XCTAssertEqual(reports.all.first?.wasUnique, true,
                       "the measurement itself is wrong: zeroing a buffer nobody else holds "
                       + "moved it, so «the address did not change» could never be true")
    }
}
