import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A phase names itself while it runs — for every deleting module, not one.
///
/// `HelmTrash.remove` weighs each path with `FileWeight` before it moves
/// anything, a walk apiece for a folder, and only Disk wrapped its call in a
/// phase: Disk was not the outlier, it was the one that got audited. The phase
/// lives in the loop now, named `"\(module).trash"`, so Uninstaller, Leftovers
/// and Duplicates carry a name beside their memory readings for free — and
/// Disk's own guard (`TheRemovalNamesItselfWhileItRunsTests`) still proves the
/// engine's path arrives here.
///
/// Caught **during** the move rather than read off the source: `trashing` is a
/// synchronous injection point inside the loop, so what `HelmActivity.running`
/// answers there is what any memory reading taken mid-removal would see. No
/// scheduling guess, no scan of a function body.
final class HelmTrashPhaseTests: XCTestCase {

    override func tearDown() {
        HelmLog.shared.setEnabled(false)
        HelmLog.shared.clearTail()
        super.tearDown()
    }

    /// The file is removed outright rather than trashed: the subject is the
    /// phase around the move, and a move that leaves nothing in anybody's
    /// `~/.Trash` needs no reclaiming afterwards.
    func testTheMoveRunsInsideAPhaseNamedForItsModule() throws {
        let module = "phase-probe"
        let root = scratchDirectory("trash-phase")
        let file = root.appendingPathComponent("f.bin")
        try Data(repeating: 0x41, count: 16).write(to: file)

        var openDuringMove: Bool?
        let result = HelmTrash.remove(allowed: [file.path], module: module,
                                      trashing: { url in
            openDuringMove = HelmActivity.running.contains { $0.label == "\(module).trash" }
            try FileManager.default.removeItem(at: url)
        })

        // The subject happened, or the probe read nothing worth asserting on.
        XCTAssertEqual(result.removed, [file.path], "the move never ran")
        XCTAssertEqual(openDuringMove, true, """
            the removal ran with no phase open, so a memory reading taken while \
            \(module) weighs and moves its batch says «nothing running» about it
            """)
        XCTAssertFalse(HelmActivity.running.contains { $0.label == "\(module).trash" },
                       "the removal left its interval open for the life of the process")
    }

    /// And what it cost is written down, per module. The label is unique to
    /// this test, so the tracker's first-reading rule guarantees a line if the
    /// reading was taken at all.
    func testTheRemovalLeavesAMemoryLineNamedForItsModule() throws {
        let module = "memory-probe-\(UUID().uuidString.prefix(8))"
        let root = scratchDirectory("trash-memory")
        let file = root.appendingPathComponent("f.bin")
        try Data(repeating: 0x41, count: 16).write(to: file)

        HelmLog.shared.setEnabled(true)
        let result = HelmTrash.remove(allowed: [file.path], module: module,
                                      trashing: { try FileManager.default.removeItem(at: $0) })
        XCTAssertEqual(result.removed, [file.path], "the move never ran")

        // The reading crosses two queues before it is a tail entry; polled
        // rather than raced, and bounded so a missing line fails in seconds.
        let deadline = Date().addingTimeInterval(5)
        var found = false
        while !found, Date() < deadline {
            found = HelmLog.shared.recentEntries().contains {
                $0.category == "memory" && $0.message.hasPrefix("\(module).trash:")
            }
            if !found { usleep(20_000) }
        }
        XCTAssertTrue(found, """
            the removal took no memory reading, so what the heaviest removal in \
            a module cost is never in its log
            """)
    }
}
