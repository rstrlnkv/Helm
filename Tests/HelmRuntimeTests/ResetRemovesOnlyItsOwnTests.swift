import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The reset, exercised on a home directory it may destroy.
///
/// `ResetPlanTests` asks the gate questions. This asks the *machinery*: hand
/// `HelmTrash` what `ResetPlan` produces, against a real directory tree, and
/// see what survives. It is the only part of "reset everything" with anything
/// to get wrong — the other two steps are `removePersistentDomain` and a
/// relaunch, both single system calls with no logic of their own.
///
/// Written because the button could not be driven on the development machine
/// (the status item sits on a second display and the automation would not reach
/// it), and "untested" is not a state this particular feature may ship in.
///
/// ## Why this one moves a single directory for real
///
/// Everywhere else a test that trashes gives its files unownable names, so the
/// cleanup can reconstruct `~/.Trash/<name>` and be sure the item is its own
/// (`TrashScratch`). Here the name comes from `ResetPlan.roots` and it is
/// `Helm`. The UUID in the temporary home above it does not survive the move —
/// only the moved item's own name does — so **four folders called `Helm` went
/// into the real Trash on every run**, which is litter that also lies: somebody
/// looking at their Trash saw Helm's data folder in it, again and again.
///
/// Worse, the plan names *two* directories both called `Helm`, so the second
/// arrives as `Helm 20-48-09-452` — macOS's collision spelling, which nothing
/// can predict and nothing can find without listing the Trash, and listing it
/// needs Full Disk Access that a test process does not have (257).
///
/// So exactly one directory is moved for real, and it is reclaimed by
/// **content**: each run writes a UUID into its scan file and the cleanup
/// removes `~/.Trash/Helm` only when that exact UUID reads back out of it.
/// Neither the name nor "it was not there when I started" is enough — either
/// would eventually delete a folder somebody had trashed themselves, which is
/// the one mistake a cleanup must not be able to make.
///
/// What that costs is coverage of the *second* path in the same batch, and
/// `ResetPlanTests` is where the pair is checked; what `HelmTrash` does with a
/// batch of two has its own tests, on files that can be cleaned up.
final class ResetRemovesOnlyItsOwnTests: XCTestCase {
    private var home: String!
    /// Written into the scan file, and read back before anything is removed
    /// from the Trash.
    private var sentinel: String!

    override func setUpWithError() throws {
        home = scratchDirectory("reset-test").path
        sentinel = "helm-reset-test-" + UUID().uuidString
        // The two directories a reset is allowed to take…
        for path in ResetPlan.removablePaths(home: home) {
            try FileManager.default.createDirectory(atPath: path + "/Disk",
                                                    withIntermediateDirectories: true)
            try sentinel.write(toFile: path + "/Disk/last-scan.json", atomically: true,
                               encoding: .utf8)
        }
        // …and three neighbours it is not. The last one is the trap: a sibling
        // whose name starts the same way.
        for path in ["\(home!)/Library/Application Support/Sketch",
                     "\(home!)/Library/Logs/DiagnosticReports",
                     "\(home!)/Library/Application Support/Helmet"] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            try "keep me".write(toFile: path + "/file.txt", atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
        reclaimTheHelmFolderThisTestTrashed()
    }

    /// `~/.Trash/Helm`, removed only if it is the one this run made.
    private func reclaimTheHelmFolderThisTestTrashed() {
        let fm = FileManager.default
        let userHome = URL(fileURLWithPath: NSHomeDirectory())
        let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                 appropriateFor: userHome, create: false))
            ?? userHome.appendingPathComponent(".Trash")
        let item = trash.appendingPathComponent("Helm")
        let marker = item.appendingPathComponent("Disk/last-scan.json")
        guard let found = try? String(contentsOf: marker, encoding: .utf8),
              found == sentinel
        else { return }
        try? fm.removeItem(at: item)
    }

    /// The plan, its gate and the removal, on a tree that really exists.
    ///
    /// The gate is asked about both paths — that half is free — and one of them
    /// is then really moved, which is what proves `HelmTrash` was given a path
    /// it could act on rather than one it would have refused.
    func testItTakesHelmsOwnDirectoryAndLeavesTheNeighbours() throws {
        let paths = ResetPlan.removablePaths(home: home)
            .filter { ResetPlan.mayRemove($0, home: home) }
        XCTAssertEqual(paths.count, 2, "the plan and its own gate disagree")

        let taken = try XCTUnwrap(paths.first { $0.contains("Application Support") })
        let result = HelmTrash.remove(allowed: [taken], module: "reset-test")

        XCTAssertEqual(result.removed, [taken], "refused: \(result.refused)")
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: taken),
                       "\(taken) survived a reset")
        // To the Trash, not past it: somebody who presses this by accident has
        // to be able to get their Autopilot rules back, and `freedBytes` is
        // only non-zero for a move that really happened.
        XCTAssertGreaterThan(result.freedBytes, 0,
                             "nothing was measured as freed, so nothing moved")

        // The neighbours, including the one whose name merely starts alike.
        for path in ["\(home!)/Library/Application Support/Sketch/file.txt",
                     "\(home!)/Library/Logs/DiagnosticReports/file.txt",
                     "\(home!)/Library/Application Support/Helmet/file.txt"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "a reset destroyed \(path), which is not Helm's")
        }
        // And the containers themselves, which a careless plan would have named.
        for path in ["\(home!)/Library/Application Support", "\(home!)/Library/Logs",
                     "\(home!)/Library", home!] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "\(path) is not Helm's to remove")
        }
    }
}
