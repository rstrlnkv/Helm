import XCTest
@testable import Module_Hosts_Engine

/// One row of tab 3, assembled from the four readings that make it.
///
/// The assembly is pure and lives apart from the port that gathers the parts,
/// because every interesting case here is a **missing** part — a key `stat`
/// could not be read, a `ssh-keygen -l` line this build cannot parse — and a
/// row built by the port would put those cases behind real I/O where no test
/// could reach them.
final class KeyRowTests: XCTestCase {

    private let pair = KeyInventory.Pair(name: "id_ed25519", hasPublicHalf: true)
    private let line = "256 SHA256:abc123 me@mac (ED25519)"

    private func facts(describeLine: String? = nil, mode: mode_t? = 0o600,
                       modified: Date? = nil, publicText: String? = nil,
                       pair: KeyInventory.Pair? = nil) -> KeyFacts {
        KeyFacts(pair: pair ?? self.pair, describeLine: describeLine, mode: mode,
                 modified: modified, publicText: publicText)
    }

    func testTheRowCarriesWhatSSHKeygenSaid() {
        let row = KeyRow.row(from: facts(describeLine: line), agent: .empty)
        XCTAssertEqual(row.name, "id_ed25519")
        XCTAssertEqual(row.described?.type, "ED25519")
        XCTAssertEqual(row.described?.bits, 256)
        XCTAssertEqual(row.described?.fingerprint, "SHA256:abc123")
        XCTAssertEqual(row.described?.comment, "me@mac")
    }

    /// **A mode nobody could read is not a mode that is fine.** `stat` fails on
    /// a key inside a directory this process may not search, which is exactly
    /// the machine this module exists for — and a row that folded «unknown»
    /// into «ok» would draw a green verdict over it and offer no Fix.
    func testAnUnreadableModeIsItsOwnAnswerAndNotOK() {
        XCTAssertEqual(KeyRow.row(from: facts(mode: nil), agent: .empty).permission, .unknown)
        XCTAssertEqual(KeyRow.row(from: facts(mode: 0o600), agent: .empty).permission, .ok)
        XCTAssertEqual(KeyRow.row(from: facts(mode: 0o644), agent: .empty).permission,
                       .tooOpen(fix: 0o600))
    }

    /// The badge is asked by fingerprint, so a key whose `ssh-keygen -l` line
    /// this build cannot parse is **not** in the agent however full the agent
    /// is. Saying otherwise would be a claim about somebody's agent made out of
    /// a parse failure — the defect `AgentList.read` refuses one layer down.
    func testAKeyWithNoReadableFingerprintIsNeverInTheAgent() {
        let full = AgentList.holding(["SHA256:abc123", "SHA256:zzz"])
        XCTAssertTrue(KeyRow.row(from: facts(describeLine: line), agent: full).inAgent)
        XCTAssertFalse(KeyRow.row(from: facts(describeLine: "not a keygen line"),
                                  agent: full).inAgent)
        XCTAssertFalse(KeyRow.row(from: facts(describeLine: nil), agent: full).inAgent)
    }

    /// An agent that is not running holds nothing, and that is not the same
    /// sentence as an agent holding nothing — but for one row's badge the
    /// answer is the same, and it must not be `true` for either.
    func testNeitherAnEmptyAgentNorAMissingOneHoldsAKey() {
        XCTAssertFalse(KeyRow.row(from: facts(describeLine: line), agent: .empty).inAgent)
        XCTAssertFalse(KeyRow.row(from: facts(describeLine: line), agent: .unreachable).inAgent)
    }

    /// Copy is a pasteboard write in the UI and no engine command, so the text
    /// travels in the state — it is the public half, and public is what it is.
    /// A pair whose public half was deleted carries none, and the row says so
    /// rather than carrying an empty string that reads like an empty key.
    func testAPairWithNoPublicHalfCarriesNothingToCopy() {
        let orphaned = KeyInventory.Pair(name: "id_rsa", hasPublicHalf: false)
        let row = KeyRow.row(from: facts(publicText: nil, pair: orphaned), agent: .empty)
        XCTAssertFalse(row.hasPublicHalf)
        XCTAssertNil(row.publicText)

        let whole = KeyRow.row(from: facts(publicText: "ssh-ed25519 AAAA me@mac\n"), agent: .empty)
        XCTAssertEqual(whole.publicText, "ssh-ed25519 AAAA me@mac\n")
    }

    /// The row crosses the wire, so it round-trips — and the check is the value
    /// rather than the field list, because a field added without a coding key
    /// is exactly the defect `HostsState`'s hand-written decoder exists for.
    func testARowSurvivesTheWire() throws {
        let row = KeyRow.row(from: facts(describeLine: line, mode: 0o644,
                                         modified: Date(timeIntervalSince1970: 1_700_000_000),
                                         publicText: "ssh-ed25519 AAAA me@mac\n"),
                             agent: .holding(["SHA256:abc123"]))
        let back = try JSONDecoder().decode(KeyRow.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(back, row)
    }
}
