import XCTest
import HelmTestSupport

/// `scratchDirectory`'s teardown against the thing it was written for.
///
/// It removes, yields and removes again, two hundred times, because a view
/// model saves from a task of its own and the save can arrive *after* the
/// removal: `PrivateFile.directory` makes the folder again and the file lands
/// in it, past the end of the test. That cost 7621 directories and 69 MB of
/// `$TMPDIR` in one module before the loop existed.
///
/// The loop had nothing behind it. `for _ in 0..<200` could become
/// `for _ in 0..<1` — the shape every one of those 42 hand-written teardowns
/// had — and the whole suite stayed green, because no test ever wrote into a
/// scratch directory late enough to need a second pass.
///
/// **The proof has to outlast the teardown it is about**, so the assertion is
/// in a teardown block registered *before* `scratchDirectory` is called: they
/// run last in, first out, so the one registered first runs last — after the
/// drain has had its turn.
final class ScratchDirectoryDrainTests: XCTestCase {

    /// How many times the late write arrives, and it stops an order of
    /// magnitude before the drain does.
    ///
    /// Counted in yields rather than in milliseconds on purpose. A sleep would
    /// make this a race the machine settles — the drain spends no wall-clock
    /// time at all, so a write 20 ms out lands after *any* number of passes and
    /// a correct drain would fail this. What the drain actually buys is
    /// *turns*: twenty of them against two hundred is the margin, and it is a
    /// margin in the unit the loop counts in.
    private static let writes = 20

    func testAWriteThatLandsAfterTheRemovalIsStillReclaimed() {
        // The directory and whether the writer is still using it, in something
        // a `@Sendable` teardown block may hold. The block is registered before
        // the directory exists, so it cannot capture the value and must not
        // capture the test case.
        let directoryBox = Locked<URL?>(nil)
        let running = Locked(true)

        // Registered first, so it runs last: after the drain, and after the
        // writer has stopped. Asserting before either would pass on a drain
        // that never ran at all.
        addTeardownBlock {
            await waitUntilReached("the writer finished, so something was proven", within: .seconds(10)) {
                !running.value
            }
            guard let directory = directoryBox.value else {
                return XCTFail("the probe never got a scratch directory")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path),
                           "a save that landed after the first removal is still in $TMPDIR — "
                           + "the teardown fired once instead of draining")
        }

        let root = scratchDirectory("drain-probe")
        directoryBox.value = root

        // The view model's own task, in miniature: it comes back after the test
        // body has ended and makes the folder again to put its file in.
        //
        // Everything it needs is a local first. Reaching `Self.writes` from
        // inside the closure crashes the region-based isolation checker on this
        // toolchain ("pattern that ... does not understand how to check"), and
        // a capture list is the shape that says what crosses anyway.
        let writes = Self.writes
        Task.detached { [running, root, writes] in
            for index in 0..<writes {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? Data([0x41]).write(to: root.appendingPathComponent("late-\(index).bin"))
                await Task.yield()
            }
            running.value = false
        }
    }
}
