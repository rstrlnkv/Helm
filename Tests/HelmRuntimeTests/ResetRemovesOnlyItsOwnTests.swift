import XCTest
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
final class ResetRemovesOnlyItsOwnTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "reset-test-" + UUID().uuidString
        // The two directories a reset is allowed to take…
        for path in ResetPlan.removablePaths(home: home) {
            try FileManager.default.createDirectory(atPath: path + "/Disk",
                                                   withIntermediateDirectories: true)
            try "state".write(toFile: path + "/Disk/last-scan.json", atomically: true,
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
    }

    func testItTakesHelmsTwoDirectoriesAndLeavesTheNeighbours() throws {
        let paths = ResetPlan.removablePaths(home: home)
            .filter { ResetPlan.mayRemove($0, home: home) }
        XCTAssertEqual(paths.count, 2, "the plan and its own gate disagree")

        let result = HelmTrash.remove(allowed: paths, module: "reset-test")

        XCTAssertEqual(result.removed.count, 2, "refused: \(result.refused)")
        XCTAssertTrue(result.refused.isEmpty)
        for path in paths {
            XCTAssertFalse(FileManager.default.fileExists(atPath: path),
                           "\(path) survived a reset")
        }
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

    /// To the Trash, not past it: somebody who presses this by accident has to
    /// be able to get their Autopilot rules back. `HelmTrash` reports what it
    /// freed, which is only true of a move it actually performed.
    func testWhatItRemovedIsRecoverable() throws {
        let paths = ResetPlan.removablePaths(home: home)
        let result = HelmTrash.remove(allowed: paths, module: "reset-test")
        XCTAssertGreaterThan(result.freedBytes, 0,
                             "nothing was measured as freed, so nothing moved")
    }
}
