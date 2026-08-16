import HelmTestSupport
import XCTest

/// A module's log category is its id, and the id has one spelling.
///
/// The Journal's module filter is built from the categories that arrive
/// (`LogFilter.categories(in:)`), so a category that disagrees with the
/// module's id does not fail — it files the module's lines under a second
/// name, and the filter offers two entries for one module. Keep Awake did
/// exactly that: nineteen lines under `keepawake` against an id of
/// `keep-awake`, and three more modules spelled their own id as a literal
/// beside the constant that already existed.
///
/// Equality is by construction: every category inside a module reads
/// `<Engine>.moduleID`, the same constant the descriptor forwards as the id,
/// so there is nothing to compare at runtime. What can regress is a literal
/// growing back — which this scan fails on, naming the file and line.
final class LogCategoriesAreModuleIdsTests: XCTestCase {

    /// The scan gate's own category, and the one literal a module may log
    /// under. `ScanCoordinator` in the app layer files every background-scan
    /// verdict under `scan`, and an engine's refusal to start one belongs to
    /// that story rather than to the module's own — which is why those
    /// messages open with the module's name. Deliberately named here, so a
    /// second shared category is a decision somebody writes down.
    private static let sharedCategories: Set<String> = ["scan"]

    /// `HelmLog`'s levels, and all of them — a level missing here is a hole
    /// in the scan, and one that does not exist scans for nothing.
    private static let levels = ["info", "warn", "error", "failure"]

    func testNoModuleLogsUnderALiteralCategory() throws {
        var offenders: [String] = []
        var callSites = 0
        let files = try RepoSource.swiftFiles(under: "Sources/Modules")

        for file in files {
            for (index, raw) in try RepoSource.lines(of: file).enumerated() {
                let text = RepoSource.code(raw)
                for level in Self.levels {
                    guard let start = text.range(of: "HelmLog.shared.\(level)(") else { continue }
                    callSites += 1
                    let rest = text[start.upperBound...]
                    guard rest.hasPrefix("\"") else { continue }
                    let literal = rest.dropFirst().prefix { $0 != "\"" }
                    guard !Self.sharedCategories.contains(String(literal)) else { continue }
                    offenders.append("\(file):\(index + 1) — \"\(literal)\"")
                }
            }
        }

        // Two controls, because a scan that reaches nothing reports nothing.
        XCTAssertGreaterThan(files.count, 50,
                             "only \(files.count) files under Sources/Modules were read, so "
                             + "this scan is looking somewhere that has moved")
        XCTAssertGreaterThan(callSites, 50,
                             "only \(callSites) log calls were found, so the marker this "
                             + "scan looks for has changed shape")

        XCTAssertTrue(offenders.isEmpty,
                      "a module logs under a literal category. The Journal's filter would "
                      + "offer it as a second module beside the id — read `<Engine>.moduleID` "
                      + "instead:\n" + offenders.joined(separator: "\n"))
    }
}
