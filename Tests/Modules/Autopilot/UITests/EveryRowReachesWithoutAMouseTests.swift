import HelmTestSupport
import XCTest

/// Actions the module offers must not need a right-click.
///
/// A `.contextMenu` is a mouse gesture; wherever a view puts an action there it
/// has to offer the same action somewhere VoiceOver and Full Keyboard Access can
/// reach — under `.accessibilityActions`. `HistorySection` does exactly this and
/// says so in a comment; the rule row in `AutopilotSettingsPage` offered Edit and
/// Delete through a context menu alone, so a rule could not be removed without a
/// mouse. Read off the source for the reason `ResultViewAccessibilityTests` gives
/// one module over: the gap is invisible to whoever is holding the mouse.
final class EveryRowReachesWithoutAMouseTests: XCTestCase {

    func testEveryContextMenuInAutopilotHasAnActionThatDoesNotNeedAMouse() throws {
        var offenders: [String] = []

        for file in try RepoSource.swiftFiles(under: "Sources/Modules/Autopilot/UI") {
            let source = try RepoSource.text(of: file)
            for view in Self.viewDeclarations(in: source) where view.body.contains(".contextMenu") {
                guard !view.body.contains(".accessibilityActions") else { continue }
                offenders.append("\((file as NSString).lastPathComponent): \(view.name)")
            }
        }

        XCTAssertEqual(offenders, [], """
            These offer an action only through a context menu, which needs a \
            right-click. Add the same action under .accessibilityActions:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The scan has to be reading the view the rule is about — a check that has
    /// stopped seeing its subject passes forever.
    func testTheScanReadsThePageTheRuleIsAbout() throws {
        var names: [String] = []
        for file in try RepoSource.swiftFiles(under: "Sources/Modules/Autopilot/UI") {
            names += Self.viewDeclarations(in: try RepoSource.text(of: file)).map(\.name)
        }
        XCTAssertTrue(names.contains("AutopilotSettingsPage"), "found: \(names)")
    }

    // MARK: - Source

    private struct ViewDeclaration {
        let name: String
        let body: String
    }

    /// Every `struct … : View` in a file, with everything under it — the shape
    /// `ResultViewAccessibilityTests` reads. A helper folds into its parent,
    /// which is the safe direction: it reports against the outer name rather than
    /// hiding.
    private static func viewDeclarations(in source: String) -> [ViewDeclaration] {
        var out: [ViewDeclaration] = []
        var current: (name: String, lines: [String])?
        for line in source.components(separatedBy: "\n") {
            if let name = declaredViewName(line) {
                if let current {
                    out.append(ViewDeclaration(name: current.name,
                                               body: current.lines.joined(separator: "\n")))
                }
                current = (name, [line])
            } else {
                current?.lines.append(line)
            }
        }
        if let current {
            out.append(ViewDeclaration(name: current.name,
                                       body: current.lines.joined(separator: "\n")))
        }
        return out
    }

    private static func declaredViewName(_ line: String) -> String? {
        guard !line.hasPrefix(" "), line.contains("struct "), line.contains(": View") else {
            return nil
        }
        return line.components(separatedBy: "struct ").last?
            .components(separatedBy: ":").first?
            .trimmingCharacters(in: .whitespaces)
    }
}
