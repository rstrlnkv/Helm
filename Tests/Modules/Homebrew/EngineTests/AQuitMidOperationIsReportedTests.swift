import Foundation
import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Homebrew_Engine

/// A child brew survives Helm: quit the app mid-`upgrade all` and the install
/// carries on with no observer — at the next launch the page looked calm while
/// the Cellar had changed underneath it. Killing the child at quit would be
/// worse (a build interrupted halfway is how broken Cellar state is made), so
/// the engine *knows and says*: the running operation leaves a marker, a clean
/// exit removes it, and the next launch's first `status()` reports what was
/// left behind — once.
final class AQuitMidOperationIsReportedTests: XCTestCase {

    func testAQuitMidOperationIsReportedAtTheNextLaunchOnce() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))

        // Launch one: the operation starts and the app "quits" — the engine is
        // simply gone, the way a process is.
        let before = brewEngine(HangingRunner(), marker: marker)
        before.upgradeAll()

        // Launch two.
        let after = brewEngine(HangingRunner(), marker: marker)
        XCTAssertEqual(after.status().interruptedOp, "upgrade all",
                       "the operation Helm quit under was never reported")
        XCTAssertNil(after.status().interruptedOp,
                     "the report must be made once, not on every status query")
    }

    func testAFinishedOperationLeavesNothingToReport() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let runner = HangingRunner()
        let before = brewEngine(runner, marker: marker)
        before.upgradeAll()
        runner.finishAll(code: 0)

        let after = brewEngine(HangingRunner(), marker: marker)
        XCTAssertNil(after.status().interruptedOp,
                     "a clean exit left its marker behind — every launch would report a ghost")
    }

    /// A failure is an exit too: the person saw it fail on screen, and the next
    /// launch has nothing new to say about it.
    func testAFailedOperationLeavesNothingToReport() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let runner = HangingRunner()
        let before = brewEngine(runner, marker: marker)
        before.upgradeAll()
        runner.finishAll(code: 1)

        let after = brewEngine(HangingRunner(), marker: marker)
        XCTAssertNil(after.status().interruptedOp)
    }

    /// The session's own status queries must not eat the marker while the
    /// operation is still running — the page refreshes its status freely, and
    /// the marker exists for the launch after this one.
    func testAStatusQueryDuringTheOperationDoesNotEatTheMarker() {
        let marker = FileOpMarker(directory: scratchDirectory("brew-marker"))
        let running = brewEngine(HangingRunner(), marker: marker)
        running.upgradeAll()

        XCTAssertNil(running.status().interruptedOp,
                     "a running operation reported itself as an interrupted one")

        let after = brewEngine(HangingRunner(), marker: marker)
        XCTAssertEqual(after.status().interruptedOp, "upgrade all",
                       "the mid-operation status query above consumed the marker")
    }

    /// The marker is stored data: the bytes an earlier build left must read as
    /// before, once, and the file must be gone after.
    func testAMarkerWrittenByAnEarlierBuildIsReadAsBefore() throws {
        let folder = scratchDirectory("brew-marker")
        let file = folder.appendingPathComponent("homebrew-operation")
        try Data("upgrade all".utf8).write(to: file)

        XCTAssertEqual(FileOpMarker(directory: folder).take(), "upgrade all")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "taking the marker must remove it")

        try Data("upgrade all".utf8).write(to: file)
        let fresh = brewEngine(HangingRunner(), marker: FileOpMarker(directory: folder))
        XCTAssertEqual(fresh.status().interruptedOp, "upgrade all")
    }
}
