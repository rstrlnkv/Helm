import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A move rule whose conditions also match the folder it files into meets that
/// folder on the next sweep. `RuleRunner.move` has a guard for exactly this —
/// «a folder cannot be moved inside itself» — so the answer is a refusal and
/// the file system is never asked.
///
/// The guard compares the bucket's path with the walked item's path as
/// strings. The walk hands back the root's symlinks resolved (`/private/var/…`
/// for `/var/…`), and a rule's destination is stored as it was spelled, so the
/// two spellings of one folder pass the guard and reach `moveItem`, which
/// fails with EINVAL — a «failed» row in the history on every sweep, for
/// ever, about a folder nobody asked to move. On disk: a scratch home under
/// `/var/folders`, whose `/private` spelling is a real second spelling.
final class ARuleNeverMovesItsOwnBucketIntoItselfTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try XCTSkipUnless(home.path.hasPrefix("/var/"), "the scratch home is not under /var: \(home.path)")
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func sweepTwice(destination: String) throws -> SweepReport {
        try write("Downloads/Invoice-march.pdf", in: home)
        let downloads = home.appendingPathComponent("Downloads").path
        let rule = Rule(id: "inv", name: "Invoices", enabled: true,
                        conditions: [.name(.beginsWith, "Invoice")],
                        action: .move(to: destination))
        let watched = WatchedFolder(id: "dl", path: downloads, enabled: true, rules: [rule], depth: 1)
        engine.folders = [watched]
        XCTAssertEqual(engine.sweep(watched).acted, 1, "precondition: the first sweep filed the PDF")
        return engine.sweep(watched)
    }

    /// The control: bucket and walk spelled alike, and the guard answers.
    func testTheGuardAnswersWhenBothAreSpelledAlike() throws {
        // Spelled by hand: `resolvingSymlinksInPath` drops a `/private` the
        // path also exists without, which is the very spelling this avoids.
        let second = try sweepTwice(destination: "/private" + home.path + "/Downloads/Invoices")
        XCTAssertEqual(second.failed, 0)
        XCTAssertEqual(second.refused, 1, "precondition: the bucket was met and the guard refused it")
    }

    /// The bucket stored as `/var/…`, the walk handing back `/private/var/…`.
    func testTheGuardAnswersWhenTheBucketIsSpelledWithoutPrivate() throws {
        let second = try sweepTwice(destination: home.path + "/Downloads/Invoices")
        XCTAssertEqual(second.examined, 1, "precondition: the bucket was met")
        XCTAssertEqual(second.failed, 0,
                       "the bucket was handed to moveItem, which failed: "
                       + "\(engine.history.filter { $0.kind == .failed }.map(\.detail))")
    }
}
