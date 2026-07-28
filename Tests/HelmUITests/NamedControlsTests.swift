import XCTest

/// Every control the app draws must have a name, even when the screen shows it
/// none.
///
/// A `Picker("")` or `TextField("")` looks complete: the segments say
/// "Installed / Updates / Search" and no heading is needed above them. Read
/// aloud it is a tab group with no name, and a form built out of them cannot be
/// filled at all — the Autopilot rule editor had nine such controls, so a rule
/// could not be built by anyone using VoiceOver. Six more were in five other
/// modules; the gap was never one screen's mistake.
///
/// This is a source scan rather than a UI test because the defect is invisible
/// at runtime to anyone not using a screen reader, and the next unnamed control
/// will be added by someone who simply did not think of it. Two ways to satisfy
/// it, both correct:
///
/// - give the control its real label and hide it — `Picker(Str.thing, …)` with
///   `.labelsHidden()`, which is what that modifier is for;
/// - or `.accessibilityLabel(…)`, for a `TextField` whose first argument is
///   already spent on a placeholder.
final class NamedControlsTests: XCTestCase {

    private static let controls = ["Picker", "TextField", "SecureField", "Slider", "Stepper"]

    func testNoControlIsDrawnWithoutAName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources")
        var offenders: [String] = []

        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            guard path.contains("/UI/") || path.contains("/HelmUI/") || path.contains("/HelmApp/")
            else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")

            for (index, line) in lines.enumerated() {
                guard Self.controls.contains(where: { line.contains("\($0)(\"\")")
                                                   || line.contains("\($0)(\"\",") }) else { continue }
                // The control and everything chained onto it: modifiers are
                // indented under it and start with a dot, and a comment between
                // them is still part of the same statement.
                let indent = line.prefix { $0 == " " }.count
                var statement = line
                for next in lines.dropFirst(index + 1).prefix(40) {
                    statement += "\n" + next
                    let body = next.trimmingCharacters(in: .whitespaces)
                    let ends = !body.isEmpty
                        && next.prefix { $0 == " " }.count <= indent
                        && !body.hasPrefix(".") && !body.hasPrefix("//")
                    if ends { break }
                }
                if !statement.contains("accessibilityLabel") {
                    let name = url.lastPathComponent
                    offenders.append("\(name):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These controls have no name. VoiceOver reads them as "pop up button" \
            or "text field" with nothing to say what they are:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan is worth nothing if it stops finding files.
    func testTheScanIsActuallyReadingTheSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var seen = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            if url.pathExtension == "swift", url.path.contains("/UI/") { seen += 1 }
        }
        XCTAssertGreaterThan(seen, 20, "the source tree moved and this test stopped looking at it")
    }
}
