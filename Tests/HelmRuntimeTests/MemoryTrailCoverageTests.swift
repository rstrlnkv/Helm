import Foundation
import XCTest
@testable import HelmRuntime

/// Which operations can name themselves in the memory trail.
///
/// `HelmLog.memory(_:)` logs the process footprint as a delta against the last
/// reading for the same label, plus an `idle` reading every fifteen seconds that
/// belongs to no operation at all. That is how the 48 GB leak was found: the
/// deltas said which phase stood between two totals.
///
/// It only works for phases that have a label. On 2026-07-30 the app's own log
/// caught a real spike — 75 MB, then 508, 1066, 1338, then back down to 300
/// across ninety seconds — with **no command logged at all**, because every
/// operation that could have caused it ran in a module that had none. Autopilot's
/// sweep runs off a timer, Homebrew parses the whole installed set, and the
/// updater hashes a downloaded archive; none of the three said anything, and none
/// called `MemoryReclaim.afterHeavyWork`, so their emptied regions stayed
/// resident until some later labelled operation happened to reclaim them.
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
        ("idle", "HelmApp/AppDelegate.swift"),
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

    /// A label without a reclaim leaves the emptied regions resident: freeing
    /// returns memory to malloc and not to macOS, and the moment the work ends is
    /// the only moment we know it is over. `idle` and `launch` are readings rather
    /// than operations, so they are exempt.
    func testEveryOperationThatIsMeasuredAlsoHandsTheMemoryBack() throws {
        let readings: Set<String> = ["idle", "launch"]
        var unreclaimed: [String] = []
        for (label, file) in expected where !readings.contains(label) {
            let url = sources.appendingPathComponent(file)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if !source.contains("afterHeavyWork(\"\(label)\")") {
                unreclaimed.append("\(label) in \(file)")
            }
        }

        XCTAssertEqual(unreclaimed, [], """
            Measured but never reclaimed — the footprint will show the growth and \
            then keep it, because a freed allocation goes back to malloc rather \
            than to macOS (ARCHITECTURE.md § Memory):
            \(unreclaimed.joined(separator: "\n"))
            """)
    }

    /// The three phases that gave their memory back **only when they finished**.
    ///
    /// Found 2026-07-31: in each of these the reclaim and the reading sat inside
    /// a conditional — after `if let result`, or below an `if isCancelled {
    /// return nil }`. So a scan somebody stopped handed nothing back to macOS and
    /// wrote nothing to the trail, and Stop is pressed exactly when the footprint
    /// is at its highest, because that is why the person pressed it.
    /// `duplicates.hash` is the loop that caused the 48 GB incident.
    ///
    /// Judged by indentation, which is the one textual signal that says "this is
    /// inside a branch": a phase's reclaim belongs at its function's own level,
    /// on every path out. `defer` would satisfy this too — it is not required,
    /// because `DuplicateScanner` runs two phases in one function and a deferred
    /// reclaim would fire at the wrong end of it.
    func testTheCancellablePhasesReclaimOnEveryPathOut() throws {
        let cancellable = [
            ("disk.scan", "Modules/Disk/Engine/DiskEngine.swift"),
            ("duplicates.walk", "Modules/Duplicates/Engine/DuplicateScanner.swift"),
            ("duplicates.hash", "Modules/Duplicates/Engine/DuplicateScanner.swift"),
        ]
        var branched: [String] = []
        for (label, file) in cancellable {
            let url = sources.appendingPathComponent(file)
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                branched.append("\(label): \(file) is not there"); continue
            }
            let call = "MemoryReclaim.afterHeavyWork(\"\(label)\")"
            guard let line = source.split(separator: "\n", omittingEmptySubsequences: false)
                .first(where: { $0.contains(call) }) else {
                branched.append("\(label): no reclaim at all"); continue
            }
            let indent = line.prefix { $0 == " " }.count
            // Eight spaces is a method body; deeper means a branch owns it, and a
            // branch is a path the cancelled run does not take.
            if indent > 8 {
                branched.append("\(label): reclaim is \(indent) spaces in — a stopped run never reaches it")
            }
            // The other shape, and the one `DuplicateScanner` had: the reclaim
            // sits at the right level but *below* the cancellation's own way out,
            // so the stopped run returns before reaching it.
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            if let at = lines.firstIndex(where: { $0.contains(call) }) {
                let above = lines[max(0, at - 10)..<at]
                if above.contains(where: { $0.contains("return nil") }) {
                    branched.append("\(label): a `return nil` stands between the work and the reclaim")
                }
            }
        }
        XCTAssertTrue(branched.isEmpty, "a stopped scan gives nothing back: \(branched)")
    }
}
