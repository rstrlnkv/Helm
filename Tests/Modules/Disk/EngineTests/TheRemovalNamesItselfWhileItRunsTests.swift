import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// A phase names itself while it runs, not only after.
///
/// The module's only `HelmActivity` pair was `disk.scan`. `trash` had none — and
/// it is the call that hands every path in the batch to `HelmTrash.remove`,
/// which weighs each of them with `FileWeight` before it moves anything: for a
/// folder that is a walk apiece. So the most expensive removal in the app was
/// the one heavy phase with no name beside a memory reading and no reading of
/// its own afterwards.
///
/// **What each half of this file can fail on**, because the two halves are not
/// the same kind of check.
///
/// **The two are a pair and neither stands alone**, which is worth saying
/// plainly. The source check proves the phase is opened; the balance check
/// proves nothing is left open — and on its own it would pass over a `trash`
/// with no phase at all, because an absence is satisfied by a run that never
/// opened anything. Together they are «opened, and closed on every way out».
///
/// The name is read off the source, for the reason `OneRemovalAtATimeEverywhereTests`
/// gives about its own scan: the state it is about lasts as long as the work and
/// is over before anything can be asserted about it. Catching it live needs a
/// removal slow enough to poll, which is a guess about scheduling — and a guess
/// that fails in the wrong direction, since a missed observation would be a red
/// test over correct code.
final class TheRemovalNamesItselfWhileItRunsTests: XCTestCase {

    /// The engine's own `trash`, run for real over a folder the gate refuses —
    /// out of scope, so nothing leaves the disk and the phase still opens and
    /// closes around the partition and the weighing.
    func testARemovalLeavesNoPhaseOpenBehindIt() async {
        let probe = "disk.balance-probe"
        HelmActivity.begin(probe)
        addTeardownBlock { HelmActivity.end(probe) }
        XCTAssertTrue(HelmActivity.running.contains { $0.label == probe },
                      "the probe never opened, so the check below is vacuous")

        let removal = await DiskEngine().trash(["/System/Library"])
        // Said out loud rather than assumed: this test hands a system folder to
        // a real engine, and the reason that is safe is `UserFileScope`. If it
        // ever stopped refusing, the test would be moving `/System/Library` to
        // somebody's Trash to check a log label.
        XCTAssertTrue(removal.removed.isEmpty, "the gate let a system folder through")

        XCTAssertFalse(HelmActivity.running.contains { $0.label == "disk.trash" }, """
            the removal left its interval open. Every memory reading taken from now on names \
            it as running, for the life of the process — which is the leak this registry \
            exists to find, arriving from the registry itself.
            """)
        XCTAssertTrue(HelmActivity.running.contains { $0.label == probe },
                      "the probe went missing under a removal, so the registry is not what "
                      + "this test thinks it is")
    }

    /// And it is named. `disk.trash`, in the module's own file, because a phase
    /// with no name is what the log had before any of this.
    func testTheRemovalOpensAPhaseOfItsOwn() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Disk/Engine/DiskEngine.swift")
        let body = try XCTUnwrap(functionBody(named: "public func trash", in: source),
                                 "`trash` is not where this scan looks for it any more")

        XCTAssertTrue(body.contains("HelmActivity"), """
            `DiskEngine.trash` runs without naming a phase. It is the call that weighs every \
            path in the batch, so a memory line taken while it runs says «nothing running» \
            about the heaviest work in the app:
            \(body.prefix(200))
            """)
        XCTAssertTrue(body.contains(#"HelmLog.shared.memory("disk.trash")"#),
                      "the phase has no reading after it, so what it cost is never recorded")
    }

    /// From the declaration to the closing brace at the same indentation. Crude
    /// on purpose: the alternative is a scan over the whole file, which finds
    /// `disk.scan` two functions up and passes with `trash` untouched.
    private func functionBody(named declaration: String, in source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains(declaration) }) else { return nil }
        let indent = String(repeating: " ", count: lines[start].prefix(while: { $0 == " " }).count)
        let end = lines[(start + 1)...].firstIndex { $0 == indent + "}" } ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }
}
