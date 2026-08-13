import Foundation
import HelmRuntime
import XCTest
@testable import Module_Leftovers_Engine

/// **A launchd job Helm could not read is offered for one-click bulk deletion, on
/// the strength of its file name.**
///
/// `LeftoversScanner.launchItems` reads each job with
///
///     LaunchAgentReader.read(plist: files.readPlist(url)?.raw ?? [:], path: url.path)
///
/// and `readPlist` is nil for every reason a file resists being read:
/// `NSDictionary(contentsOf:)` answers nil for a corrupt plist, for a truncated
/// one, for a plist whose root is an array rather than a dictionary, and for one
/// the process may not open. `?? [:]` turns all of that into «this job has no
/// `Program`», the next line turns *that* into `targetAlive = false`, and a job
/// that points at nothing is a leftover — ticked by «Select all», counted in the
/// batch, and moved to the Trash.
///
/// The scanner's own documentation is the argument for calling this a defect
/// rather than a judgement call: «the rules err on the side of leaving things
/// alone: anything Apple's, anything in a system location, anything whose owner is
/// still installed, and **anything whose owner cannot be identified** stays put».
/// A file whose contents could not be read is the plainest case of an owner that
/// cannot be identified, and it is the one case the rule does not cover — because
/// the unreadability is spent one line before the rule runs.
///
/// The distinction that has to survive the fix is in the second test: a plist that
/// really *is* empty is a job launchd cannot load and a leftover Helm should
/// offer. «I read it and there is nothing in it» and «I could not read it» are two
/// facts, and `?? [:]` is where they became one.
///
/// The first test is the tester's and is **expected to fail** until the two are
/// told apart.
final class APlistNobodyCouldReadTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/x")

    /// Writability by directory, the only distinction the filesystem offers here —
    /// see `LeftoversScannerFakes`.
    private func agent(named file: String, plist: PlistData?) -> StaleItem? {
        var files = LeftoversFakeFiles()
        files.listing["/Users/x/Library/LaunchAgents"] = [file]
        if let plist { files.plists["/Users/x/Library/LaunchAgents/\(file)"] = plist }
        return LeftoversScanner(home: home, files: files, apps: LeftoversFakeApps(),
                                extensions: LeftoversFakeLoaded()).scan()
            .first { $0.kind == .launchAgent }
    }

    /// **The finding.** Nothing was read, and the row says «Leftover» with a tick
    /// beside it.
    func testAnAgentWhosePlistCouldNotBeReadIsNotOfferedForBulkDeletion() throws {
        let item = try XCTUnwrap(agent(named: "com.vendor.updater.plist", plist: nil),
                                 "precondition: the unreadable job is still listed, which it "
                                 + "should be — a row nobody can read is worth showing")

        XCTAssertEqual(item.identifier, "com.vendor.updater",
                       "precondition: the name comes from the file, since the label could not be "
                       + "read")
        XCTAssertFalse(item.removable, """
            a launchd job whose plist could not be read is ticked by «Select all» and trashed with \
            the batch: `readPlist` answered nil — corrupt, truncated, an array at the root, or a \
            file this process may not open — and `?? [:]` made that «no Program», which the status \
            rule reads as «points at nothing». The scanner's own rule is that anything whose owner \
            cannot be identified stays put.
            """)
    }

    /// And the other half, which must keep working: a job that really carries no
    /// `Program` is a job launchd cannot start, and clearing it is the whole point
    /// of the module.
    func testAnAgentWhosePlistIsReadableAndEmptyIsStillALeftover() throws {
        let item = try XCTUnwrap(agent(named: "com.vendor.updater.plist", plist: PlistData([:])))

        XCTAssertEqual(item.status, .orphaned)
        XCTAssertTrue(item.removable, """
            an empty plist is a job launchd will not load, and it is the case this module exists \
            for — a fix that tells «unreadable» from «empty» must not take this row with it.
            """)
    }

    /// The same reading, one field down: a plist that *does* name a program, in a
    /// shape the reader cannot take. `Program` is asked for as a `String` and
    /// `ProgramArguments` as `[String]`, so a job whose program is a number, a
    /// dictionary, or an array of them reads as a job with no program at all.
    ///
    /// Not asserted as a defect — a job launchd itself would refuse to load is
    /// arguably rubbish worth clearing — but recorded, because it is the same
    /// `nil`-means-two-things shape and a fix for the test above may well cover it.
    /// If it does, this assertion is the one that says so.
    func testAProgramInAShapeTheReaderCannotTakeReadsAsNoProgramAtAll() throws {
        let item = try XCTUnwrap(agent(named: "com.vendor.updater.plist",
                                       plist: PlistData(["Label": "com.vendor.updater",
                                                         "ProgramArguments": [42, 43]])))

        XCTAssertNil(item.missingTarget,
                     "the row says nothing about a target, so at least it makes no false claim")
        XCTAssertEqual(item.status, .orphaned,
                       "recorded, not endorsed: a program the reader could not take reads as a "
                       + "job that points nowhere")
    }
}
