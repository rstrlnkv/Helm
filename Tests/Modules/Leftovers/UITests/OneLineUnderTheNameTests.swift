import HelmRuntime
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// What the row says under the name, and how many lines it takes to say it.
///
/// The list had three heights in it: 32 pt where a system extension has no second
/// line, 44 with a name and a path, and 59 where a missing target added a third at
/// 10 pt. Two of those are the same row wearing a fact it happens to carry, and a
/// list whose rows are three heights has no rhythm to read down.
///
/// So the path and the reason are **one** line — built from the two keys that were
/// already there, which is why this costs no `.strings` edit: what is new is the
/// middle dot between them.
///
/// The line is one and it is drawn as two `Text`s, because which half gives way
/// when the width runs out is the point — `TheReasonIsNotWhatGetsCutTests` is that
/// half of it, measured off the render. Here it is still the same one line: two
/// parts, one of them a fact the row happens to carry.
@MainActor
final class OneLineUnderTheNameTests: XCTestCase {

    private func agent(_ name: String, missingTarget: String? = nil) -> StaleItem {
        StaleItem(path: "\(NSHomeDirectory())/Library/LaunchAgents/\(name).plist",
                  identifier: name, kind: .launchAgent, sizeBytes: 4_096,
                  missingTarget: missingTarget)
    }

    /// The ordinary row: where the file is, and nothing else.
    func testARowWithNothingWrongWithItSaysWhereItIs() throws {
        let item = agent("plain")

        let detail = try XCTUnwrap(LfStr.detail(for: item))
        XCTAssertEqual(detail.path, item.path)
        XCTAssertNil(detail.reason)
    }

    /// And a row that points at a file that has gone says both facts on one line,
    /// in the order a person reads them: where it is, then what is wrong.
    func testAMissingTargetJoinsThePathRatherThanAddingALine() throws {
        let item = agent("broken", missingTarget: "/opt/gone/helper")
        let line = try XCTUnwrap(Self.joined(item))

        XCTAssertFalse(line.contains("\n"), "the two facts are on two lines again: \(line)")
        XCTAssertTrue(line.hasPrefix(item.path),
                      "the path is what the row is about and comes first: \(line)")
        XCTAssertTrue(line.contains(LfStr.missingTarget("/opt/gone/helper")),
                      "the reason lost its own sentence rather than joining the line: \(line)")
        XCTAssertTrue(line.contains(" · "),
                      "two facts on one line need the separator that says they are two: \(line)")
    }

    /// A system extension has no second line at all, and that is not an omission:
    /// `LeftoversScanner.systemExtensions` builds it with `path == identifier`, so
    /// the line would be the name again, one step quieter.
    func testASystemExtensionHasNoSecondLineBecauseItsPathIsItsName() {
        let extensionItem = StaleItem(path: "com.vendor.ext", identifier: "com.vendor.ext",
                                      kind: .systemExtension, sizeBytes: 0)
        XCTAssertEqual(extensionItem.path, extensionItem.identifier,
                       "precondition: the scan gives an extension its identifier as its path")

        XCTAssertNil(LfStr.detail(for: extensionItem))
    }

    /// The line the row says, both parts of it — what a reader of this list hears
    /// read out, and what the two checks above are about.
    static func joined(_ item: StaleItem,
                       language: AppLanguage = AppLanguage.current) -> String? {
        guard let detail = LfStr.detail(for: item, language: language) else { return nil }
        return detail.path + (detail.reason ?? "")
    }

    /// The reason is written in the reader's language on both halves of the join —
    /// a line built by interpolation is looked up before it is joined, and the
    /// half that is not looked up is the half that ships in English.
    func testBothHalvesAreInTheReadersLanguage() throws {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }
        AppLanguage.override = .ru

        let item = agent("broken", missingTarget: "/opt/gone/helper")
        let line = try XCTUnwrap(Self.joined(item))

        XCTAssertTrue(line.contains("Ссылается на отсутствующий файл"),
                      "the reason is in English inside a Russian row: \(line)")
    }
}
