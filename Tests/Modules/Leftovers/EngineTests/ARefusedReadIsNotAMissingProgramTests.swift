import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **A read that was refused reads as «the program is gone», and the row then says
/// so about working software.**
///
/// `LeftoversScanner.launchItems` decides whether a login item is alive with
///
///     let targetAlive = info.program.map(files.exists) ?? false
///
/// and the port behind `exists` was `FileManager.fileExists`, which answers `false`
/// both for a path that is not there and for one inside a directory this process
/// may not search — measured on this Mac: a file under a mode-000 parent gives
/// `fileExists == false` while `stat` gives `EACCES`.
///
/// `targetAlive` is the only thing between a live job and `.orphaned`, so a login
/// item that runs at every login wears the orange «Leftover» badge, claims «Points
/// at a missing file», is ticked by «Select all» and offers a «Turn off» that really
/// does stop working software. It bites hardest with Full Disk Access denied, which
/// ARCHITECTURE.md records as 23 of 42 launches.
///
/// This is the fold commit `6de0a337` closed for the plist read and left open one
/// line below it, so the repair is the module's own: the port answers three ways,
/// and «I could not tell» is not «it is not there».
final class ARefusedReadIsNotAMissingProgramTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")
    private let program = "/Library/Application Support/Vendor/updater"

    /// One agent pointing at `program`, with the third state of the port under the
    /// test's control.
    private func agent(_ arrange: (inout LeftoversFakeFiles) -> Void) throws -> StaleItem {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater", "Program": program, "RunAtLoad": true])
        arrange(&files)
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded()).scan()
        return try XCTUnwrap(items.first { $0.kind == .launchAgent },
                             "precondition: the agent is listed at all")
    }

    /// **The finding.** Nobody could look, and the row calls it a leftover.
    func testAProgramThisProcessMayNotLookAtIsNotAMissingProgram() throws {
        let item = try agent { $0.unreadable = [self.program] }

        XCTAssertEqual(item.status, .undetermined, """
            the existence of «\(self.program)» could not be read — `stat` says EACCES, and \
            `FileManager.fileExists` folds that to «not there» — and the row came back \
            \(item.status.rawValue), which is what «Select all» ticks. A refused read is not a \
            fact about the file.
            """)
        XCTAssertFalse(item.removable, "a job Helm could not judge must not be in the batch")
        XCTAssertNil(item.missingTarget, """
            the row draws «Points at a missing file: \(item.missingTarget ?? "")» about a program \
            it never managed to look for — a claim about somebody's Mac made out of a permission \
            error.
            """)
    }

    /// The other half, which must keep working: a program that really is not there
    /// is the case this module exists for.
    func testAProgramThatIsReallyGoneIsStillALeftover() throws {
        let item = try agent { _ in }

        XCTAssertEqual(item.status, .orphaned)
        XCTAssertTrue(item.removable)
        XCTAssertEqual(item.missingTarget, program,
                       "and the row still says what it points at, which is why anyone believes it")
    }

    /// And a program that is there is in use, as before.
    func testAProgramThatIsThereIsInUse() throws {
        let item = try agent { $0.existing = [self.program] }

        XCTAssertEqual(item.status, .inUse)
        XCTAssertNil(item.missingTarget)
    }

    /// A job that names no program at all is untouched by any of this: the plist was
    /// read, it says nothing about a program, and launchd cannot start it.
    func testAJobThatNamesNoProgramIsUnaffected() throws {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = ["com.vendor.updater.plist"]
        files.plists["/Users/x/Library/LaunchAgents/com.vendor.updater.plist"] =
            PlistData(["Label": "com.vendor.updater"])
        let items = LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                     extensions: LeftoversFakeLoaded()).scan()

        XCTAssertEqual(items.first?.status, .orphaned)
        XCTAssertNil(items.first?.missingTarget)
    }

    /// The row a person is shown for it asks about the reading, not about the file:
    /// «could not read this file» would blame a plist that read perfectly, and
    /// «loaded now» would claim the very thing that could not be checked.
    func testTheQuestionAskedIsAboutTheReadingThatDidNotHappen() throws {
        let item = try agent { $0.unreadable = [self.program] }

        XCTAssertEqual(LeftoverActions.askBeforeDeleting(item), .cannotBeChecked)
        XCTAssertTrue(LeftoverActions.needsConfirmation(item))
        XCTAssertTrue(item.actions.contains(.delete),
                      "the row's own delete stays — clearing it deliberately is allowed")
    }
}
