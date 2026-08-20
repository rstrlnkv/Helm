import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Hosts_Engine

/// **`ssh-keygen -l` is pointed at the `.pub`, and nothing here opens the
/// private half.**
///
/// The promise is written in three places — `SystemSSHKeys`' own documentation,
/// `SSHKeysPort` («no method here opens a private key, and there is no method
/// that could») and `KeyInventory` — and until now it was checked by reading
/// the source. A promise about which of two files a tool is handed is a
/// property of the *running* port, so this one is asked of the real
/// `SystemSSHKeys`, pointed at a directory of this test's own.
///
/// The private half in the first test is unreadable (mode 000) **and** is not a
/// key, so a tool aimed at it comes back with nothing and the fingerprint the
/// row must carry is missing. The orphan test needs the opposite fixture — a
/// real key the tool *can* read — and says why at the test.
///
/// **Nothing here goes near the owner's own `~/.ssh`.** The directory is a
/// `scratchDirectory`, which drains its own teardown; the key pair is a
/// throwaway generated once and written down, so no test run makes one.
final class ThePrivateHalfIsNeverOpenedTests: XCTestCase {

    private lazy var directory: URL = scratchDirectory("hosts-private-half")

    /// A real `ed25519` public half — generated once, outside anybody's `~/.ssh`,
    /// and kept here so this test needs no `ssh-keygen` run of its own to make
    /// one. `ssh-keygen -l` reads it, which is the whole point: a fixture the
    /// tool refuses would make every reading below vacuous.
    private let publicHalf = "ssh-ed25519 "
        + "AAAAC3NzaC1lZDI1NTE5AAAAIPlbqyRBNaFZbc+GsF6UwufErw/HBmEowrh05UymPM4o me@mac\n"
    private let fingerprint = "SHA256:4pz7iO0haQXWFjkqkKCLit+YXYqSz1gvnQlLnbAb+gw"
    /// What a private key would be, if anything opened one. A word no correct
    /// reading of this directory can produce.
    private let privateHalf = "PRIVATE-HALF-WAS-READ\n"

    private func makePair(named name: String, withPublicHalf: Bool = true,
                          privateMode: NSNumber = 0o000) throws {
        let key = directory.appendingPathComponent(name)
        try privateHalf.write(to: key, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: privateMode],
                                              ofItemAtPath: key.path)
        if withPublicHalf {
            try publicHalf.write(to: directory.appendingPathComponent(name + ".pub"),
                                 atomically: true, encoding: .utf8)
        }
        addTeardownBlock {
            // Readable again before the scratch teardown, so a 000 file is
            // never what the drain is left arguing with.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: key.path)
        }
    }

    /// The fingerprint on the row comes from the `.pub`, over a private half
    /// this process could not open even if it tried.
    func testTheRowIsBuiltFromThePublicHalfAlone() throws {
        try makePair(named: "id_ed25519")
        let port = SystemSSHKeys(directory: directory, deadline: 15)

        let facts = port.facts(for: KeyInventory.Pair(name: "id_ed25519", hasPublicHalf: true))

        XCTAssertNotNil(facts.describeLine, """
            `ssh-keygen -l` said nothing this build could use. Either it was pointed at the \
            private half — which is mode 000 here and is not a key — or the fixture has stopped \
            being a key `ssh-keygen` reads, and then every reading below is taken over nothing.
            """)
        // The raw line, not the parsed one: what this test is about is *which
        // file* the tool was handed. That the parse of that line then fails is
        // a different defect, and it has a file of its own next door
        // (`TheToolsOwnOutputIsReadTests`) — two subjects in one assertion is
        // two checks that can only fail together.
        XCTAssertTrue((facts.describeLine ?? "").contains(fingerprint),
                      "the description is not the public half's: \(facts.describeLine ?? "nil")")
        XCTAssertEqual(facts.publicText, publicHalf)
        XCTAssertFalse((facts.describeLine ?? "").contains("PRIVATE-HALF-WAS-READ"))
        XCTAssertFalse((facts.publicText ?? "").contains("PRIVATE-HALF-WAS-READ"),
                       "the private half's bytes are in the state the engine sends to the page")
    }

    /// **A pair with no `.pub` has no description at all**, and that is the
    /// design rather than a gap: the alternative is aiming the tool at the
    /// private key, which puts a passphrase prompt and the key's own bytes into
    /// a listing that runs on every refresh. The row says «no public half»
    /// instead, and this is what stops somebody «fixing» it later.
    ///
    /// **The private half here is a real, readable, unencrypted key**, and it
    /// has to be. The junk-and-mode-000 file the other tests use would make
    /// this vacuous: `ssh-keygen` refuses that whichever file it is handed, so
    /// «no description» would be green over a port that had opened the private
    /// key and been turned away. Measured — with the guard removed and the tool
    /// aimed at the private half, this test stayed green until the fixture
    /// became a key the tool can actually read. So the precondition below runs
    /// the tool by hand first: the description is *available* from that file,
    /// and the port did not take it.
    ///
    /// The pair is generated into a `scratchDirectory` that drains. Nothing
    /// goes near the owner's `~/.ssh`, and nothing is left behind.
    func testAPairWithNoPublicHalfIsNotDescribedAtAll() throws {
        let key = directory.appendingPathComponent("orphan")
        let made = Process()
        made.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        made.arguments = ["-t", "ed25519", "-N", "", "-C", "me@mac", "-q", "-f", key.path]
        try made.run()
        made.waitUntilExit()
        try XCTSkipIf(made.terminationStatus != 0, "ssh-keygen would not make a throwaway key")
        // The public half goes, which is the state under test: a private key
        // whose `.pub` was deleted, and which `ssh-keygen -y` could regenerate.
        try FileManager.default.removeItem(at: key.appendingPathExtension("pub"))

        let byHand = HelmProcess.run("/usr/bin/ssh-keygen", ["-l", "-f", key.path], timeout: 15)
        XCTAssertEqual(byHand.status, 0, """
            precondition: `ssh-keygen -l` cannot read this private half, so «the port did not \
            describe it» would be true of a port that had opened it and failed. The whole \
            reading below rests on the description being there to take.
            """)

        let facts = SystemSSHKeys(directory: directory, deadline: 15)
            .facts(for: KeyInventory.Pair(name: "orphan", hasPublicHalf: false))

        XCTAssertNil(facts.describeLine, """
            a key with no public half was described anyway, and the description is only in the \
            private half — so the private half was opened. On a key with a passphrase that is a \
            prompt inside a listing that runs on every state emission, and the tool is handed \
            the key's own bytes either way.
            """)
        XCTAssertNil(facts.publicText)
        XCTAssertNotNil(facts.mode, "precondition: the file is there and was stat'ed")
    }

    /// The mode and the date come from the private half — `stat`, which opens
    /// nothing — so a key nobody may read still has a verdict and a Fix beside
    /// it. This is the reading that must keep working while the file stays
    /// shut.
    func testTheVerdictIsReadFromAFileThatIsNeverOpened() throws {
        try makePair(named: "tight", privateMode: 0o644)
        let port = SystemSSHKeys(directory: directory, deadline: 15)

        let row = KeyRow.row(from: port.facts(for: KeyInventory.Pair(name: "tight",
                                                                    hasPublicHalf: true)),
                             agent: .unreachable)

        XCTAssertEqual(row.permission, .tooOpen(fix: 0o600))
        XCTAssertNotNil(row.modified)
    }

    /// The whole directory, through the port the engine uses: what is a key,
    /// what is furniture, and — the reason this test is in this file — that
    /// listing a directory reads no file in it at all.
    func testListingTheDirectoryNamesPairsAndNotFurniture() throws {
        try makePair(named: "id_ed25519")
        for furniture in ["config", "known_hosts", ".DS_Store"] {
            try "whatever\n".write(to: directory.appendingPathComponent(furniture),
                                   atomically: true, encoding: .utf8)
        }
        let port = SystemSSHKeys(directory: directory, deadline: 15)

        let names = try XCTUnwrap(port.names())
        XCTAssertEqual(KeyInventory.pairs(in: names).map(\.name), ["id_ed25519"])
    }
}
