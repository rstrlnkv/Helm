import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// A phase names itself while it runs, not only after.
///
/// The `disk.trash` phase lives in `HelmTrash.remove` now, named
/// `"\(module).trash"` for every deleting module — this engine used to wrap
/// its own call while the other three ran nameless, and Disk was not the
/// outlier, it was the one that got audited. That the phase opens during the
/// move and takes its reading is `HelmTrashPhaseTests`' subject, over in
/// HelmRuntimeTests, where the loop is.
///
/// What is left to prove *here* is the engine's own path: that `trash` really
/// arrives in that loop with this module's id, and that a removal driven
/// through the engine leaves nothing open behind it. On its own the balance
/// half would pass over a `trash` with no phase at all — an absence is
/// satisfied by a run that never opened anything — which is why the runtime
/// test holds the "opened, during the move" half.
final class TheRemovalNamesItselfWhileItRunsTests: XCTestCase {

    /// The engine's own `trash`, run for real over a folder the gate refuses —
    /// out of scope, so nothing leaves the disk and the phase still opens and
    /// closes around the partition and the refusal.
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
        // The refusal is the proof the batch reached `HelmTrash.remove` — the
        // reason arrives from inside the loop, so a `trash` that stopped
        // calling it could not produce this and the balance below would be
        // about nothing.
        XCTAssertEqual(removal.refused.map(\.reason), [.outOfScope],
                       "the engine's batch never reached the shared loop")

        XCTAssertFalse(HelmActivity.running.contains { $0.label == "disk.trash" }, """
            the removal left its interval open. Every memory reading taken from now on names \
            it as running, for the life of the process — which is the leak this registry \
            exists to find, arriving from the registry itself.
            """)
        XCTAssertTrue(HelmActivity.running.contains { $0.label == probe },
                      "the probe went missing under a removal, so the registry is not what "
                      + "this test thinks it is")
    }
}
