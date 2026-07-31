import Foundation
import XCTest
@testable import HelmRuntime

/// Which operations can name themselves in the memory trail.
///
/// `HelmLog.memory(_:)` logs the process footprint as a delta against the last
/// reading for the same label, plus a `sample` every fifteen seconds that belongs
/// to no operation at all. That is how the 48 GB leak was found: the
/// deltas said which phase stood between two totals.
///
/// It only works for phases that have a label. On 2026-07-30 the app's own log
/// caught a real spike — 75 MB, then 508, 1066, 1338, then back down to 300
/// across ninety seconds — with **no command logged at all**, because every
/// operation that could have caused it ran in a module that had none. Autopilot's
/// sweep runs off a timer, Homebrew parses the whole installed set, and the
/// updater hashes a downloaded archive; none of the three said anything, and none
/// said anything at all, so the spike had no phase name against it.
///
/// (Those operations also called `MemoryReclaim.afterHeavyWork`, which was
/// removed 2026-07-31 after four probes and five live operations measured it
/// returning 0 MB every time — ARCHITECTURE.md § Memory.)
/// docs/superpowers/plans/2026-07-29-third-pass.md has the trail and the vmmap.
///
/// This is a coverage test, not a measurement: it asserts the labels exist in the
/// source, so removing one is visible. It cannot tell whether a label sits in the
/// right place — only that the operation is still able to name itself.
final class MemoryTrailCoverageTests: XCTestCase {

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmRuntimeTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
    }

    /// Every bulk operation that has been found to matter, with the file it lives
    /// in — so a failure says where to look rather than only what is missing.
    ///
    /// Deliberately not "every `offTheCooperativePool` call site": plenty of those
    /// are a `scutil` read or a status query, and a label on a cheap call is noise
    /// in the one trail that has to stay readable.
    private let expected: [(label: String, file: String)] = [
        ("disk.scan", "Modules/Disk/Engine/DiskEngine.swift"),
        ("duplicates.walk", "Modules/Duplicates/Engine/DuplicateScanner.swift"),
        ("duplicates.hash", "Modules/Duplicates/Engine/DuplicateScanner.swift"),
        ("leftovers.scan", "Modules/Leftovers/Engine/LeftoversEngine.swift"),
        ("uninstaller.appSizes", "Modules/Uninstaller/Engine/UninstallerEngine.swift"),
        ("autopilot.sweep", "Modules/Autopilot/Engine/AutopilotEngine.swift"),
        ("homebrew.listInstalled", "Modules/Homebrew/Engine/HomebrewEngine.swift"),
        ("homebrew.outdated", "Modules/Homebrew/Engine/HomebrewEngine.swift"),
        ("update.digest", "HelmApp/UpdateService.swift"),
        ("sample", "HelmApp/AppDelegate.swift"),
        ("launch", "HelmApp/AppDelegate.swift"),
    ]

    func testEveryBulkOperationCanNameItselfInTheMemoryTrail() throws {
        var missing: [String] = []
        for (label, file) in expected {
            let url = sources.appendingPathComponent(file)
            let source = try? String(contentsOf: url, encoding: .utf8)
            guard let source else { missing.append("\(label): \(file) is not there"); continue }
            guard source.contains("memory(\"\(label)\")") else {
                missing.append("\(label): \(file) no longer logs it")
                continue
            }
        }

        XCTAssertEqual(missing, [], """
            An operation that does bulk work and does not name itself cannot be \
            blamed by the memory trail — which is the position the +177 MB report \
            was stuck in for two days:
            \(missing.joined(separator: "\n"))
            """)
    }
}
