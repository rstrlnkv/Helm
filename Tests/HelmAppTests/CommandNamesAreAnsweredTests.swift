import HelmRuntime
import Module_Disk_UI
import Module_Duplicates_UI
import Module_Uninstaller_UI
import XCTest

/// A command name is a type now, and this keeps it one.
///
/// **This file used to scan for the defect it now cannot happen.** A command was
/// a string on both sides of the transport: a caller's typo fell through the
/// engine's `default`, the reply was empty, the caller read `nil` — which this
/// codebase spells "the module could not answer" — so a misspelling was
/// indistinguishable from a refusal. The scan compared, per module, the names
/// sent against the names handled. Then every module got its own command enum
/// and its engine switched over it exhaustively, at which point the scan had
/// nothing left to compare: **the literals it read are gone, so a green result
/// meant only that it had stopped looking.**
///
/// What is left worth checking is the two things the compiler still cannot see.
final class CommandNamesAreAnsweredTests: XCTestCase {

    private var sources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // HelmAppTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo
            .appendingPathComponent("Sources")
    }

    /// **Nothing goes back to a literal.** The enum only helps while call sites
    /// use it; one `client.request("scan")` typed out of habit is the old defect
    /// back in one module, and it would compile.
    func testNoModuleSendsACommandAsAStringLiteral() throws {
        let modules = sources.appendingPathComponent("Modules")
        guard let walk = FileManager.default.enumerator(at: modules,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles])
        else { return XCTFail("Sources/Modules is not where this test thinks it is") }
        let literal = try NSRegularExpression(
            pattern: "\\b(?:request|fire|send)\\(\\s*\"[A-Za-z][A-Za-z0-9.]*\"")
        var offenders: [String] = []
        for case let file as URL in walk where file.pathExtension == "swift" {
            // The engines' own `send` is the transport's, not a command's.
            guard !file.pathComponents.contains("Engine"),
                  let text = try? String(contentsOf: file, encoding: .utf8)
            else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if literal.firstMatch(in: line, range: range) != nil {
                    offenders.append("\(file.lastPathComponent):\(index + 1) \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "a command sent as a string, where its module has an enum for it:\n"
                      + offenders.joined(separator: "\n"))
    }

    /// **The one name that crosses a target boundary.** The coordinator sends
    /// `ScanCommand.backgroundScan` from `HelmApp`; three engines answer it from
    /// their own enums, and no compiler sees both sides. Two spellings of one
    /// string is exactly the shape this whole change removes elsewhere.
    func testTheThreeScannersSpellTheScanCommandTheSameWay() {
        XCTAssertEqual(DiskCommand.backgroundScan.rawValue, ScanCommand.backgroundScan)
        XCTAssertEqual(DuplicatesCommand.backgroundScan.rawValue, ScanCommand.backgroundScan)
        XCTAssertEqual(UninstallerCommand.backgroundScan.rawValue, ScanCommand.backgroundScan)
    }
}
