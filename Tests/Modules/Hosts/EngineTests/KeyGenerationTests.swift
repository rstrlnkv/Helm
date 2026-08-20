import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
@testable import Module_Hosts_Engine

/// Making a key: what is refused before a child exists, what reaches the tool,
/// and what a second press does while one is being made.
final class KeyGenerationTests: XCTestCase {

    private let directory = URL(fileURLWithPath: "/nowhere/.ssh")

    private func request(type: KeyGeneration.KeyType = .ed25519,
                         name: String = "id_new",
                         comment: String = "me@mac",
                         passphrase: String = "") -> KeyGeneration.Request {
        KeyGeneration.Request(type: type, name: name, comment: comment,
                              passphrase: Data(passphrase.utf8))
    }

    // MARK: - The sentence

    /// **No `-N` in it, ever.** That argument is the defect this whole design
    /// exists for: it puts the passphrase in `ps auxww` for every process on the
    /// machine. The sentence is asserted whole rather than searched, so an
    /// argument added later has to be looked at rather than slipped past.
    func testTheSentenceNeverCarriesThePassphrase() throws {
        let built = try KeyGeneration.arguments(for: request(passphrase: "hunter2"),
                                                in: directory).get()
        XCTAssertEqual(built, ["-t", "ed25519", "-f", "/nowhere/.ssh/id_new", "-C", "me@mac"])
        XCTAssertFalse(built.contains("-N"))
        XCTAssertFalse(built.contains { $0.contains("hunter2") })
    }

    /// `ed25519` has one size and `ssh-keygen` refuses `-b` for it, so the
    /// argument is added only where it means something.
    func testOnlyRSAIsToldItsSize() throws {
        let rsa = try KeyGeneration.arguments(for: request(type: .rsa), in: directory).get()
        XCTAssertEqual(rsa.suffix(2), ["-b", "4096"])
        let ed = try KeyGeneration.arguments(for: request(), in: directory).get()
        XCTAssertFalse(ed.contains("-b"))
    }

    /// A comment is written into the `.pub` file, which is one line per key: a
    /// break in it makes a file `ssh` reads as two keys, one of them nonsense.
    func testACommentWithALineBreakIsRefused() {
        XCTAssertEqual(KeyGeneration.arguments(for: request(comment: "me@mac\nssh-rsa AAAA"),
                                               in: directory),
                       .failure(.commentHasALineBreak))
    }

    func testANameThatIsNotAPlainComponentIsRefused() {
        for name in ["../../.zshrc", "a/b", "", ".", ".."] {
            XCTAssertEqual(KeyGeneration.arguments(for: request(name: name), in: directory),
                           .failure(.notAPlainName), "«\(name)» was composed into a path")
        }
    }

    // MARK: - Through the engine

    private struct Bench {
        let engine: HostsEngine
        let generator: FakeGenerator
        let transport: LocalTransport
    }

    private func bench(names: KeyInventory.Listing? = ["id_ed25519", "id_ed25519.pub"],
                       status: Int32 = 0) -> Bench {
        let transport = LocalTransport()
        let hosts = FakeHostsFile()
        let generator = FakeGenerator(status: status)
        let home = scratchDirectory("key-generation")
        let engine = HostsEngine(file: hosts, privileged: FakePrivileged(writingTo: hosts),
                                 backups: FakeBackups(),
                                 sshConfig: FakeSSHConfig(
                                    url: home.appendingPathComponent(".ssh/config"),
                                    text: "Host a\n"),
                                 knownHosts: FakeKnownHosts(), keys: FakeSSHKeys(names: names), agent: FakeSSHAgent(),
                                 generator: generator, home: home, transport: transport)
        return Bench(engine: engine, generator: generator, transport: transport)
    }

    /// The same send, as a free function of its arguments — an `async let`
    /// cannot call a method on this class without sending `self` with it.
    private static func post(_ request: KeyGeneration.Request,
                             on transport: LocalTransport) async throws -> GenerateOutcome {
        let reply = try await transport.send(EngineCommand(
            name: HostsCommand.generateKey.rawValue,
            payload: try JSONEncoder().encode(request)))
        return try JSONDecoder().decode(GenerateOutcome.self, from: reply)
    }

    private func generate(_ transport: LocalTransport,
                          _ request: KeyGeneration.Request) async throws -> GenerateOutcome {
        let reply = try await transport.send(EngineCommand(
            name: HostsCommand.generateKey.rawValue,
            payload: try JSONEncoder().encode(request)))
        return try JSONDecoder().decode(GenerateOutcome.self, from: reply)
    }

    func testAKeyIsMadeAndTheToolIsAnsweredWithThePassphrase() async throws {
        let b = bench()
        let outcome = try await generate(b.transport, request(passphrase: "hunter2"))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(b.generator.sentences.count, 1)
        XCTAssertEqual(b.generator.answered.first, Data("hunter2".utf8),
                       "the tool was not answered with what the sheet asked for")
    }

    /// **A name already in the directory is never pointed at.** `ssh-keygen`
    /// asks before it overwrites, and this design answers its prompts — so an
    /// answer meant for a passphrase would land on «Overwrite (y/n)?» and
    /// destroy a key nobody offered to replace. The public half counts too: a
    /// pair whose private key was moved away still owns that name.
    func testAnExistingKeyIsNeverOverwritten() async throws {
        let b = bench()
        let taken = try await generate(b.transport, request(name: "id_ed25519"))
        XCTAssertEqual(taken, .nameTaken)

        let orphan = bench(names: ["id_rsa.pub"])
        let alsoTaken = try await generate(orphan.transport, request(name: "id_rsa"))
        XCTAssertEqual(alsoTaken, .nameTaken)

        XCTAssertTrue(b.generator.sentences.isEmpty)
        XCTAssertTrue(orphan.generator.sentences.isEmpty)
    }

    func testARefusedNameNeverReachesTheTool() async throws {
        let b = bench()
        let outcome = try await generate(b.transport, request(name: "../../.zshrc"))
        XCTAssertEqual(outcome, .notAPlainName)
        XCTAssertTrue(b.generator.sentences.isEmpty)
    }

    func testAToolThatFailsIsReportedAsAFailure() async throws {
        let b = bench(status: 1)
        let outcome = try await generate(b.transport, request())
        XCTAssertEqual(outcome, .failed)
    }

    /// **The second press, while the first is still at the prompt.**
    ///
    /// This is the test the fake exists for: a generator that finished
    /// instantly would be over before the second command was sent, and the gate
    /// would be proved by nothing. The first run is held at the prompt, the
    /// second is sent, and only then is the first released.
    func testASecondPressWhileOneIsBeingMadeIsAnsweredRatherThanRun() async throws {
        let b = bench()
        b.generator.sitsAtThePrompt()

        // Both payloads are built before either is sent: `request(_:)` is a
        // method on this class, and reaching for it from inside `async let`
        // sends `self` across an isolation boundary.
        let firstRequest = request(name: "id_first")
        let secondRequest = request(name: "id_second")
        let transport = b.transport
        let generator = b.generator

        async let first = Self.post(firstRequest, on: transport)
        await Task.detached { generator.waitUntilAsked() }.value

        let second = try await generate(transport, secondRequest)
        XCTAssertEqual(second, .alreadyRunning)

        b.generator.finish()
        let outcome = try await first
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(b.generator.sentences.count, 1,
                       "two generations were started, and they were pointed at one directory")
    }
}
