import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A press anywhere in an object's 38 × 76 cell picks that object and nothing else.** The cell is as tall as the
/// palette now (it was 28 pt), so its zone reaches the capsule's top and bottom edge; the neighbours — Undo and Redo on
/// the left, the colour grid on the right — stand beside it. Pressed at the top, the middle and the bottom of the
/// capsule, each object answers over one run of x the cell's width wide, the run holds no other answer, and the
/// neighbours' zones are neither entered nor touched.
final class ThePaletteObjectZoneIsItsOwnTests: XCTestCase {
    private let step: CGFloat = 1
    private let rows: [CGFloat] = [0.03, 0.5, 0.97]
    private let objects: [AnnotationTool] = [.pen, .highlighter, .pencil]

    @MainActor private func presses(tool: AnnotationTool?, row: CGFloat) throws -> [(x: CGFloat, action: EditorAction)] {
        try answersAcrossThePalette(language: .en, canUndoAndRedo: true, step: step, tool: tool, heightFraction: row).answers.compactMap {
            // A press on the chosen object's cell opens the pop-over instead of choosing the tool again: the zone is the
            // same, so it counts as that object's answer (the pop-over's own answer is ThePopoverEditsTheChosenToolsOwnStyleTests').
            guard case .action(let action) = $0.answer else { return nil }
            if case .thicknessAndOpacity = action, let tool { return ($0.x, .tool(tool)) }
            return ($0.x, action)
        }
    }

    private func label(_ action: EditorAction) -> String { String(describing: action) }

    @MainActor func testEachObjectTakesOneRunOfItsOwnWidthAtEveryHeight() throws {
        for tool in [nil, AnnotationTool.pen, AnnotationTool.highlighter] as [AnnotationTool?] {
            for row in rows {
                let sent = try presses(tool: tool, row: row)
                for object in objects {
                    let xs = sent.filter { $0.action == .tool(object) }.map(\.x)
                    let lo = try XCTUnwrap(xs.min(), "\(object) answered nowhere at height \(row)")
                    let hi = try XCTUnwrap(xs.max())
                    XCTAssertEqual(hi - lo + step, PaletteObject.width, accuracy: step * 2,
                                   "\(object) zone is \(hi - lo + step) wide at height \(row), tool \(String(describing: tool))")
                    let between = Set(sent.filter { $0.x > lo && $0.x < hi }.map { label($0.action) })
                    XCTAssertEqual(between, [label(.tool(object))], "\(object): other answers inside its zone at \(row): \(between)")
                }
            }
        }
    }

    /// The neighbours are the colour swatches (24 pt circles, the lit one's ring 33), Undo and Redo (28 pt circles) and the ⋯ zone (36 pt); they take no press in the capsule's top and bottom rows: only the objects
    /// answer there. In the middle row the object zones stand clear of every other answer's x, with a gap and no touch.
    @MainActor func testOnlyTheObjectsAnswerAtTheEdgesAndTheyTouchNoNeighbourInTheMiddle() throws {
        let objectLabels = Set(objects.map { label(.tool($0)) })
        for row in [0.03, 0.97] as [CGFloat] {
            let sent = try presses(tool: nil, row: row)
            XCTAssertFalse(sent.isEmpty, "nothing answered at height \(row): the sweep read nothing")
            XCTAssertEqual(Set(sent.map { label($0.action) }), objectLabels, "at height \(row) a neighbour answered")
        }
        let middle = try presses(tool: nil, row: 0.5)
        let others = middle.filter { !objectLabels.contains(label($0.action)) }.map(\.x)
        XCTAssertFalse(others.isEmpty, "no neighbour answered in the middle row: nothing to keep clear of")
        for object in objects {
            let xs = middle.filter { $0.action == .tool(object) }.map(\.x)
            let (lo, hi) = (try XCTUnwrap(xs.min()), try XCTUnwrap(xs.max()))
            let left = lo - (others.filter { $0 < lo }.max() ?? -.infinity)
            let right = (others.filter { $0 > hi }.min() ?? .infinity) - hi
            XCTAssertGreaterThanOrEqual(min(left, right), step * 2, "\(object) zone touches a neighbour's (gaps \(left), \(right))")
        }
    }
}
