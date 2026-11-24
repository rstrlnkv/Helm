import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The reset, exercised on a home directory it may destroy.
///
/// `ResetPlanTests` asks the gate questions. This asks the machinery: hand
/// `HelmTrash` what `ResetPlan` produces, against a real directory tree, and
/// see what survives. The other steps of a reset are `removePersistentDomain`
/// and a relaunch, single system calls with no logic of their own.
///
/// ## Why this one moves a single directory for real
///
/// Elsewhere a test that trashes gives its files unownable names, so the
/// cleanup can find `~/.Trash/<name>` (`TrashScratch`). Here the name comes from
/// `ResetPlan.removablePaths` and is `Helm`, and a second `Helm` would arrive
/// under macOS's unpredictable collision spelling, which nothing can find
/// without listing the Trash, and a test process may not.
///
/// So exactly one directory is moved for real, and it is reclaimed by content:
/// each run writes a UUID into its scan file, and the cleanup removes
/// `~/.Trash/Helm` only when that exact UUID reads back. Neither the name nor
/// "it was not there when I started" is enough: either would eventually delete
/// a folder somebody had trashed themselves.
///
/// What a batch of two does is covered by `HelmTrash`'s own tests, on files
/// that can be cleaned up.
final class ResetRemovesOnlyItsOwnTests: XCTestCase {
    private var home: String!
    /// Written into the scan file, and read back before anything is removed
    /// from the Trash.
    private var sentinel: String!

    override func setUpWithError() throws {
        home = scratchDirectory("reset-test").path
        sentinel = "helm-reset-test-" + UUID().uuidString
        // The two directories a reset is allowed to take…
        for path in ResetPlan.removablePaths(home: home, folder: .helm) {
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
        let paths = ResetPlan.removablePaths(home: home, folder: .helm)
            .filter { ResetPlan.mayRemove($0, home: home, folder: .helm) }
        XCTAssertEqual(paths.count, 2, "the plan and its own gate disagree")
        // The gate itself, asked about the neighbours and the containers: a gate
        // widened to the parent of Helm's folders still passes its own two paths.
        for path in ["\(home!)/Library/Application Support/Sketch",
                     "\(home!)/Library/Logs/DiagnosticReports",
                     "\(home!)/Library/Application Support/Helmet",
                     "\(home!)/Library/Application Support", "\(home!)/Library/Logs"] {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: home, folder: .helm), path)
        }

        let taken = try XCTUnwrap(paths.first { $0.contains("Application Support") })
        let result = HelmTrash.remove(allowed: [taken], module: "reset-test")

        XCTAssertEqual(result.removed, [taken], "refused: \(result.refused)")
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: taken),
                       "\(taken) survived a reset")
        // To the Trash, not past it, so an accidental press can be undone;
        // `freedBytes` is non-zero only for a move that really happened.
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
