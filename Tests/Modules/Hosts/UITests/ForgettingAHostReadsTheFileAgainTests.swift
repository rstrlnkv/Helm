import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// **Forget writes a file the page read some time ago.**
///
/// The act is «drop this one line». What crosses the wire is the whole file,
/// rendered from `knownHostsText` — the model's copy of the last snapshot —
/// and the engine writes it as it stands. The reasoning beside it is about the
/// alternative: «an index would be a second contract about which line, decided
/// on one side of the wire and acted on at the other after the file may have
/// changed».
///
/// The file changing underneath is exactly what makes the whole-file form
/// worse, not better. `known_hosts` is not a document a person edits and saves;
/// it is a file **`ssh` appends to** every time somebody connects to a machine
/// for the first time, from any terminal on the Mac, while this page is open.
/// A snapshot is minutes old by the time a Forget is pressed, and sending it
/// back takes out every line that arrived in between — silently, and reported
/// as `applied`, because the engine reads back what it just sent and finds it
/// there.
///
/// This is the family CLAUDE.md names «a reading older than the act», and the
/// fix has a shape the module already uses: the act names the line
/// (`KnownHostsFile.Entry.raw` is held on the value for exactly this kind of
/// reason), and the engine re-reads, removes that line and writes.
///
/// **No test could have caught this before**, and the reason is in the wire:
/// `WireKnownHosts` is a `struct` whose `read()` is a constant and whose
/// `write(_:)` returns `true` without storing anything — it cannot change under
/// the app and cannot say what it was given. The engine-side `FakeKnownHosts`
/// can do both, and lives in a target this one cannot see.
@MainActor
final class ForgettingAHostReadsTheFileAgainTests: XCTestCase {

    private lazy var home: URL = scratchDirectory("hosts-forget")
    /// Held: the transport's handler holds the engine weakly.
    private var engines: [HostsEngine] = []

    /// `known_hosts` as the real file behaves: it stores, it can be read back,
    /// and **it can grow under the app** — which is what `ssh` does to it every
    /// time somebody trusts a new machine.
    private final class GrowingKnownHosts: KnownHostsPort, @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private var stored: String

        init(url: URL, text: String) {
            self.url = url
            self.stored = text
        }

        var text: String { lock.withLock { stored } }
        /// `ssh` trusted a new host while the page was open.
        func appendUnderTheApp(_ line: String) { lock.withLock { stored += line } }

        func read() -> String? { lock.withLock { stored } }
        func write(_ text: String) -> Bool {
            lock.withLock { stored = text }
            return true
        }
    }

    private let first = "github.com ssh-ed25519 AAAAB3Nza me@mac\n"
    private let second = "old.example ssh-rsa AAAAB3Nza me@mac\n"
    private let arrived = "new.example ssh-ed25519 AAAAC3Nza me@mac\n"

    private func wire() async throws -> (model: HostsViewModel, known: GrowingKnownHosts) {
        // A real file at the path, because the gate stats it: the port is a
        // fake so the test can move it under the app, and `SSHFileScope` judges
        // the path either way.
        let directory = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("known_hosts")
        try (first + second).write(to: url, atomically: true, encoding: .utf8)

        let known = GrowingKnownHosts(url: url, text: first + second)
        let transport = LocalTransport()
        let engine = HostsEngine(file: FixedFile("127.0.0.1\tlocalhost\n"),
                                 privileged: FixedPrivileged(.declined),
                                 backups: MemoryBackups(), sshConfig: WireSSHConfig(),
                                 knownHosts: known, keys: WireKeys(), agent: WireAgent(),
                                 generator: WireKeyGenerator(), home: home, transport: transport)
        engines.append(engine)
        let model = HostsViewModel(vm: ModuleViewModel(transport: engine.transport))
        addTeardownBlock { await MainActor.run { model.stop() } }
        await model.firstLoad?.value
        await waitUntil("the first snapshot arrived") { !model.knownHostsText.isEmpty }
        return (model, known)
    }

    /// The ordinary case first, so the one below is about staleness and not
    /// about Forget being broken: the line asked for goes, the other stays.
    func testForgettingDropsTheLineItWasAskedTo() async throws {
        let (model, known) = try await wire()
        guard let entry = model.otherTrusted.first(where: { $0.hosts == ["github.com"] }) else {
            return XCTFail("the trusts on the page are \(model.otherTrusted.map(\.hosts))")
        }

        await model.forget(entry)

        XCTAssertEqual(model.knownHostsOutcome, .applied)
        XCTAssertFalse(known.text.contains("github.com"))
        XCTAssertTrue(known.text.contains("old.example"))
    }

    /// **The finding.** `ssh` trusted a machine after the page's last snapshot;
    /// one Forget takes that trust away with it, and the page says «applied».
    func testATrustThatArrivedAfterTheSnapshotSurvivesAForget() async throws {
        let (model, known) = try await wire()
        guard let entry = model.otherTrusted.first(where: { $0.hosts == ["github.com"] }) else {
            return XCTFail("the trusts on the page are \(model.otherTrusted.map(\.hosts))")
        }

        // Somebody ran `ssh new.example` in a terminal while this page was
        // open. Nothing tells the page, and nothing has to: the file belongs to
        // whoever is logged in.
        known.appendUnderTheApp(arrived)
        XCTAssertTrue(known.text.contains("new.example"), "precondition: the file really grew")

        await model.forget(entry)

        XCTAssertEqual(model.knownHostsOutcome, .applied,
                       "precondition: the write went through, which is what makes this silent")
        XCTAssertFalse(known.text.contains("github.com"),
                       "precondition: the line asked for is the one that went")
        XCTAssertTrue(known.text.contains("new.example"), """
            forgetting one host removed a host trusted after the page last read the file. The \
            act carried the whole document as the page remembered it, so everything `ssh` \
            appended in between was written away — and the read-back compared what was sent \
            with what was written, which agree exactly. The next connection to that machine \
            meets the «host key verification» wall, and nothing on this page said a word.
            """)
    }
}
