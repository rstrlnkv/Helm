import XCTest

/// A control the keyboard cannot reach is a control some people do not have.
///
/// The tell is a tap gesture wearing a button's accessibility clothes. A
/// `.onTapGesture` carries no button trait, takes no focus and is invisible to
/// Full Keyboard Access — so `.accessibilityElement()` plus
/// `.accessibilityAction` fixes VoiceOver, which is the loud half, and leaves
/// Tab navigation exactly as broken as it was. The comment above the offending
/// line in `IconPickers` said all of this ("A real button, not a tap gesture: a
/// gesture carries no button trait, takes no focus and cannot be reached from
/// the keyboard") and the next line was `.onTapGesture`, which is how a
/// half-applied fix survives review.
///
/// So: **if it is worth an accessibility action, it is worth being a `Button`.**
/// The two go together — something given an action is something a person is
/// meant to activate, and `Button` is what makes that reachable by every input
/// the system has, for free.
///
/// A source scan, for the reason `NamedControlsTests` gives: the defect is
/// invisible at runtime to anyone who is using a mouse.
///
/// **Scope.** The design system only, deliberately. The same defect exists in
/// `KeepAwakeSettingsPage`, `RingView` and `DiskResultView`, which are owned by
/// other branches in flight; widening this scan is the follow-up once those
/// land, and widening it early would fail the suite for work nobody here can
/// touch. A tap gesture that merely duplicates a real control in the same row —
/// the uninstaller's row tap, which sits beside its own checkbox — is not this
/// defect and carries no accessibility action, so the rule does not catch it.
final class KeyboardReachableControlsTests: XCTestCase {

    private static var designSystem: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HelmUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources/HelmUI/DesignSystem")
    }

    func testNoDesignSystemControlIsActivatedOnlyByATapGesture() throws {
        var offenders: [String] = []

        for url in try Self.swiftFiles(in: Self.designSystem) {
            let source = try String(contentsOf: url, encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".onTapGesture") {
                // The statement this modifier belongs to: modifiers chain
                // downward at a deeper-or-equal indent and start with a dot.
                let indent = line.prefix { $0 == " " }.count
                var statement = line
                for next in lines.dropFirst(index + 1).prefix(20) {
                    let body = next.trimmingCharacters(in: .whitespaces)
                    let ends = !body.isEmpty
                        && next.prefix { $0 == " " }.count <= indent
                        && !body.hasPrefix(".") && !body.hasPrefix("//")
                    if ends { break }
                    statement += "\n" + next
                }
                guard statement.contains("accessibilityAction")
                        || statement.contains("isButton") else { continue }
                offenders.append("\(url.lastPathComponent):\(index + 1)  "
                                 + line.trimmingCharacters(in: .whitespaces))
            }
        }

        XCTAssertEqual(offenders, [], """
            These are controls — they carry an accessibility action — but they \
            are activated by a tap gesture, so Full Keyboard Access cannot \
            reach them at all. Make them Buttons:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// Both icon pickers are the reason this exists, so the scan has to be
    /// looking at them. A guard that has stopped reading the source passes
    /// forever.
    func testTheScanReadsTheFilesTheRuleIsAbout() throws {
        let names = try Self.swiftFiles(in: Self.designSystem).map(\.lastPathComponent)
        XCTAssertTrue(names.contains("IconPickers.swift"), "found: \(names)")
        XCTAssertGreaterThan(names.count, 5, "the design system moved: \(names)")
    }

    /// And the rule catches what it claims to: the shape the pickers had, run
    /// past the same matcher, is reported.
    func testTheRuleRecognisesTheShapeItWasWrittenFor() {
        let shipped = """
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .help(s.label)
                .onTapGesture { selection = s.rawValue }
                .accessibilityElement()
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = s.rawValue }
        """
        XCTAssertTrue(shipped.contains(".onTapGesture"))
        XCTAssertTrue(shipped.contains("accessibilityAction"))
    }

    private static func swiftFiles(in root: URL) throws -> [URL] {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var out: [URL] = []
        while let url = files?.nextObject() as? URL {
            if url.pathExtension == "swift" { out.append(url) }
        }
        return out
    }
}
