import Foundation
import XCTest
@testable import Module_Leftovers_Engine

/// **A launchd job Helm could not read is not offered for bulk deletion on the
/// strength of its file name.**
///
/// `readPlist` is nil for every reason a file resists being read:
/// `PropertyListFile.dictionary(atPath:followingLink:)` answers nil for a corrupt
/// plist, a truncated one, one whose root is an array, one the process may not
/// open, a pipe, and one over `PropertyListFile.byteCeiling`. Read as «this job
/// has no `Program`», that would make `targetAlive = false`, and a job that
/// points at nothing is a leftover — ticked by «Select all» and trashed.
///
/// The scanner's rule is that **anything whose owner cannot be identified**
/// stays put, and a file whose contents could not be read is the plainest case.
///
/// The distinction that has to survive is in the second test: a plist that
/// really *is* empty is a job launchd cannot load and a leftover Helm should
/// offer. «I read it and there is nothing in it» and «I could not read it» are
/// two facts.
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

    /// **The guard.** Nothing was read, and the row is not a ticked «Leftover».
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
    /// `nil`-means-two-things shape.
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
