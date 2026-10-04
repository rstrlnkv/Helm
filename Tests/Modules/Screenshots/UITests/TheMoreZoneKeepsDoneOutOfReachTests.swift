import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **⋯ is a 28 pt circle that takes a press 36 pt wide, and the press never reaches Done.** The zone is measured
/// the way a person meets it: the mounted palette in a window ordered in, one press (down and up) at every
/// quarter point along its middle, and what each press sent. ⋯'s answer is `EditorBarModel.openMenu` (what the
/// overlay answers with the menu's `popUp`), Done's is `.exit(.confirm)`. The zone is the run of x that opened the menu;
/// the gap is the run between its end and the first x that reached Done.
///
/// What the palette's own width could hide: a test reading a constant would pass for a zone drawn at 28 and
/// laid at 36, so the sweep must find both ends of both zones, or it fails in its own words. A press may also not
/// leave a half-zone behind: the run must have no holes and nothing else may answer inside the gap.
@MainActor
final class TheMoreZoneKeepsDoneOutOfReachTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The zone's own width and the way to Done, from the answers to a sweep at `step`.
    private struct Zones {
        let moreWidth: CGFloat
        let moreFirst: CGFloat
        let moreLast: CGFloat
        let doneFirst: CGFloat
        /// Distance from ⋯'s last pressing x to Done's first one: at most a step more than the real gap.
        var gap: CGFloat { doneFirst - moreLast }
    }

    private func zones(in answers: [(x: CGFloat, answer: PaletteAnswer)], step: CGFloat, _ context: String,
                       file: StaticString = #filePath, line: UInt = #line) throws -> Zones {
        let more = answers.filter { if case .more = $0.answer { true } else { false } }.map(\.x)
        let done = answers.filter { $0.answer == .action(.exit(.confirm)) }.map(\.x)
        let moreFirst = try XCTUnwrap(more.first, "\(context): no press opened the menu, so ⋯ has no zone to measure", file: file, line: line)
        let moreLast = try XCTUnwrap(more.last, file: file, line: line)
        let doneFirst = try XCTUnwrap(done.first, "\(context): no press reached Done, so «out of reach of Done» means nothing", file: file, line: line)
        // No hole: every sampled x between the ends opened the menu and nothing else.
        let inside = answers.filter { $0.x >= moreFirst && $0.x <= moreLast }
        XCTAssertEqual(inside.count, more.count, "\(context): something other than ⋯ answered inside ⋯'s zone: \(inside.map(\.answer))", file: file, line: line)
        XCTAssertEqual(Set(more).count, Int(((moreLast - moreFirst) / step).rounded()) + 1,
                       "\(context): ⋯'s zone has a hole in it", file: file, line: line)
        // Nothing answers in the gap.
        let gap = answers.filter { $0.x > moreLast && $0.x < doneFirst }
        XCTAssertTrue(gap.isEmpty, "\(context): a press between ⋯ and Done sent \(gap.map(\.answer))", file: file, line: line)
        return Zones(moreWidth: moreLast - moreFirst + step, moreFirst: moreFirst, moreLast: moreLast, doneFirst: doneFirst)
    }

    func testTheMoreZoneIs36PointsAndTheGapToDoneIsAtLeast8() throws {
        AppLanguage.override = .en
        let step: CGFloat = 0.25
        let (answers, _) = try answersAcrossThePalette(language: .en, step: step)
        let found = try zones(in: answers, step: step, "en")
        XCTAssertEqual(found.moreWidth, 36, accuracy: step + 0.01, "⋯ takes a press \(found.moreWidth) pt wide, not 36 (the circle is 28)")
        XCTAssertGreaterThanOrEqual(found.gap, 8, "⋯'s zone ends \(found.gap) pt before Done's starts; at least 8 are owed")
    }

    /// The badge is drawn on ⋯ while a menu tool is chosen and the colours move nothing: the zone is the same
    /// with a menu tool, a row object and none, and in every language.
    func testTheZoneHoldsWithAnyToolChosenInEveryLanguage() throws {
        let step: CGFloat = 0.5
        for language in AppLanguage.allCases {
            for tool in [nil, AnnotationTool.arrow, .ellipse, .pencil] {
                let context = "\(language), tool \(String(describing: tool))"
                let (answers, _) = try answersAcrossThePalette(language: language, step: step, tool: tool)
                let found = try zones(in: answers, step: step, context)
                XCTAssertEqual(found.moreWidth, 36, accuracy: step + 0.01, "\(context): ⋯'s zone is \(found.moreWidth) pt")
                XCTAssertGreaterThanOrEqual(found.gap, 8, "\(context): the gap to Done is \(found.gap) pt")
            }
        }
    }

    /// A press in the gap, and one just past each end of the zone, sends nothing at all; a press inside ⋯ opens
    /// the menu once per press, with the pressed state already set, and the state is cleared when the menu returned.
    func testAPressInTheGapSendsNothingAndAPressOnTheMoreSetsItsStateAroundThePopUp() throws {
        let step: CGFloat = 1
        let (answers, after) = try answersAcrossThePalette(language: .en, step: step)
        let found = try zones(in: answers, step: step, "en")
        let opened = answers.compactMap { entry -> Bool? in if case .more(let pressed) = entry.answer { pressed } else { nil } }
        XCTAssertFalse(opened.isEmpty)
        XCTAssertFalse(opened.contains(false), "the menu was opened with ⋯ not yet drawn pressed: \(opened.filter { !$0 }.count) of \(opened.count)")
        XCTAssertFalse(after, "⋯ stayed drawn pressed after the menu returned")
        XCTAssertTrue(answers.filter { $0.x > found.moreLast && $0.x < found.doneFirst }.isEmpty)
        // One press, one opening: every sampled x pressed once, so the count of openings is the count of x.
        XCTAssertEqual(opened.count, Int(((found.moreLast - found.moreFirst) / step).rounded()) + 1)
    }
}
