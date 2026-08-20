import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Hosts_Engine
@testable import Module_Hosts_UI

/// Which key opens which host, on the model that answers both tabs.
///
/// **The join is the model's, once per change.** A row that worked out its own
/// share of it would be the shape `ScanCoordinator.Conditions` exists to stop —
/// one tick judging three modules against three different readings — and here
/// the three readings would be the same three files parsed once per row and
/// again on every redraw.
@MainActor
final class TheJoinIsComputedOnceForTheTabTests: XCTestCase {

    private let home = "/Users/someone"

    private func model(_ state: HostsState) -> HostsViewModel {
        let model = HostsViewModel(vm: ModuleViewModel(transport: LocalTransport()))
        addTeardownBlock { await MainActor.run { model.stop() } }
        model.adopt(state)
        return model
    }

    private func key(_ name: String) -> KeyRow {
        KeyRow(name: name, hasPublicHalf: true,
               described: KeyInventory.described("256 SHA256:abc123 me@mac (ED25519)"),
               modified: nil, permission: .ok, publicText: nil, inAgent: false)
    }

    private var config: String {
        """
        Host build
            HostName build.example
            User rstrlnkv
            Port 2222
            IdentityFile ~/.ssh/work_rsa

        Host old
            HostName old.example
            IdentityFile ~/.ssh/deleted

        """
    }

    private func loaded() -> HostsViewModel {
        model(HostsState(sshText: config,
                         keys: [key("work_rsa"), key("id_ed25519"), key("personal")],
                         knownHostsText: "build.example ssh-ed25519 AAAA me@mac\n"
                             + "github.com ssh-ed25519 BBBB me@mac\n",
                         home: home))
    }

    /// **The four states, and the one that must not read as «unused».**
    /// `id_ed25519` is named by nothing here and `ssh` will still reach for it;
    /// `personal` is named by nothing and nothing will. A page that drew those
    /// two the same way tells somebody the key they log in with is safe to
    /// delete.
    func testTheModelAnswersWithAllFourUsages() {
        let hvm = loaded()

        XCTAssertEqual(hvm.usage(of: "work_rsa"), .namedBy(["build"]))
        XCTAssertEqual(hvm.usage(of: "id_ed25519"), .byDefaultName)
        XCTAssertEqual(hvm.usage(of: "personal"), .unused)
        XCTAssertNotEqual(hvm.usage(of: "id_ed25519"), hvm.usage(of: "personal"), """
            a key `ssh` tries by name and a key nothing will ever reach for came back the same — \
            which is «you can delete this» written over the key somebody logs in with
            """)
    }

    /// A `*` block lends its key to everything, and the sentence is not a list
    /// of the blocks that happen to mention it.
    func testAStarBlockReachesTheModelAsEveryHost() {
        let hvm = model(HostsState(sshText: "Host *\n  IdentityFile ~/.ssh/work_rsa\n",
                                   keys: [key("work_rsa")], home: home))
        XCTAssertEqual(hvm.usage(of: "work_rsa"), .everyHost)
    }

    /// The rows tab 2 draws, from the same reading: the address, the key, and
    /// the fingerprint already trusted for that host.
    func testTheHostRowsCarryTheAddressTheKeyAndTheTrust() {
        let hvm = loaded()

        XCTAssertEqual(hvm.hostRows.map(\.address),
                       ["rstrlnkv@build.example:2222", "old.example"])
        XCTAssertEqual(hvm.hostRows.first?.identities, [.named("work_rsa")])
        XCTAssertEqual(hvm.hostRows.last?.identities, [.missing("deleted")],
                       "a host pointing at a key that is gone reached the page as a host "
                       + "pointing at nothing")
        XCTAssertEqual(hvm.hostRows.first?.trusted.map(\.keyType), ["ssh-ed25519"])
        XCTAssertEqual(hvm.otherTrusted.map { $0.hosts }, [["github.com"]],
                       "the trust for a host no block names was not gathered under «other»")
    }

    /// **The join follows the document.** It is worked out when something
    /// changes rather than once at the first snapshot — a value frozen at the
    /// first reading is the family named in CLAUDE.md, and here it would leave
    /// a key reading «used by build» after the block naming it was deleted.
    func testAnEditToTheConfigMovesTheJoin() {
        let hvm = loaded()
        XCTAssertEqual(hvm.usage(of: "work_rsa"), .namedBy(["build"]),
                       "precondition: the key starts out named by the block")

        hvm.setSSHText("Host build\n    HostName build.example\n")

        XCTAssertEqual(hvm.usage(of: "work_rsa"), .unused)
        XCTAssertEqual(hvm.hostRows.map(\.identities), [[]])
    }

    /// And a snapshot that lands while somebody is mid-edit does not take the
    /// typing away — nor leave the join describing a document nobody is looking
    /// at any more.
    func testASnapshotKeepsTheJoinInStepWithWhatIsOnScreen() {
        let hvm = loaded()
        hvm.setSSHText("Host mine\n  IdentityFile ~/.ssh/personal\n")

        hvm.adopt(HostsState(sshText: "Host theirs\n", keys: [key("personal")], home: home))

        XCTAssertEqual(hvm.sshText, "Host mine\n  IdentityFile ~/.ssh/personal\n",
                       "the snapshot overwrote unsaved typing")
        XCTAssertEqual(hvm.usage(of: "personal"), .namedBy(["mine"]),
                       "the join describes the document on disk, not the one on screen")
    }

    /// **Every key gets an answer**, including one the config never mentions: a
    /// row with no sentence is a row that says nothing about the thing somebody
    /// came to find out.
    func testEveryKeyOnThePageHasASentenceToDraw() {
        let hvm = loaded()
        for row in hvm.keys {
            XCTAssertNotNil(HostsStr.usage(of: hvm.usage(of: row.name)),
                            "\(row.name) has no usage sentence")
        }
    }

    /// **Four states, four sentences, in all eight languages.**
    ///
    /// The English is the key, so a collision is invisible in English and total
    /// in the other seven — which is why this loops over the languages instead
    /// of reading `AppLanguage.current`, the machine's own. The pair that must
    /// never collapse is «used by default» and «not used by anything here»: one
    /// is the key somebody logs in with and the other is safe to delete.
    func testTheFourUsagesAreFourSentencesInEveryLanguage() {
        let states: [KeyUsage.OfKey] = [.namedBy(["build"]), .everyHost, .byDefaultName, .unused]
        for language in AppLanguage.allCases {
            let said = states.map { HostsStr.usage(of: $0, language: language) }
            for sentence in said {
                XCTAssertFalse(sentence.isEmpty, "an empty usage sentence in \(language.rawValue)")
            }
            XCTAssertEqual(Set(said).count, states.count, """
                \(language.rawValue) says \(Set(said).count) different things about four \
                different states: \(said). «Used by default» reading as «not used» is «you can \
                delete this» written over the key somebody logs in with.
                """)
        }
    }

    /// The promise in prose, with a test under it: the page draws the model's
    /// table and does not work one out for itself.
    func testNoViewInThisModuleComputesTheJoin() throws {
        let files = try RepoSource.swiftFiles(under: "Sources/Modules/Hosts/UI")
        XCTAssertFalse(files.isEmpty, "no UI source was read, so the scan below passes for free")

        for file in files where !file.hasSuffix("HostsViewModel.swift") {
            let code = SwiftSource.code(try RepoSource.text(of: file))
            XCTAssertFalse(code.contains("SSHHostRows.table") || code.contains("KeyUsage.of"), """
                \(file) works out the join for itself. It belongs to the view model, once per \
                change: a row that computes it re-parses three files per row and again on every \
                redraw, and two rows can then disagree about one document.
                """)
        }
    }
}
