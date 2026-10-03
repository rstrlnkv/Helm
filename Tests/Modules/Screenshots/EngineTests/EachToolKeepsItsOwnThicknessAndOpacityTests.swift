import CoreGraphics
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **Each tool keeps its own thickness and opacity; the colour and the fill stay everybody's.**
/// The points of a step come from one table, `AnnotationThickness.points(for:)`, and the numbers below are
/// the owner's, spelled out here and read from nowhere in the tree, so a table that drifts fails against
/// them and not against itself. What is remembered is two tables in the store, read by walking the tools
/// there are, never by walking the table.
final class EachToolKeepsItsOwnThicknessAndOpacityTests: XCTestCase {

    private typealias Key = ScreenshotsSettings.Key

    private func backing() -> InMemoryKeyValueStore { InMemoryKeyValueStore() }
    private func store(_ backing: InMemoryKeyValueStore) -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    // MARK: the table of points

    func testThePointsOfEveryToolAndStepAreTheOwnersNumbers() {
        let owners: [(AnnotationTool, [CGFloat])] = [
            (.pen, [1.5, 3, 6]), (.highlighter, [6, 12, 18]), (.pencil, [2, 3.5, 5]),
            (.arrow, [6, 10, 16]),
            (.rectangle, [3, 5, 8]), (.ellipse, [3, 5, 8]), (.line, [3, 5, 8]),
            (.blur, [10, 16, 24]), (.text, [12, 15, 22]),
        ]
        XCTAssertEqual(Set(owners.map(\.0)), Set(AnnotationTool.allCases), "a tool has no row here: add its numbers")
        for (tool, points) in owners {
            XCTAssertEqual(AnnotationThickness.allCases.map { $0.points(for: tool) }, points, "\(tool)")
        }
    }

    func testTheStrokeReadsTheTableAndSoDoesTheArrowsHead() {
        let start = CGPoint(x: 20, y: 60), far = CGPoint(x: 180, y: 60)
        for step in AnnotationThickness.allCases {
            for tool in [AnnotationTool.pen, .pencil, .highlighter, .line, .rectangle, .ellipse] {
                let layer = Annotation(tool: tool, start: start, end: far, points: [start, CGPoint(x: 100, y: 60), far],
                                       style: AnnotationStyle(thickness: step))
                XCTAssertEqual(layer.stroke?.width, step.points(for: tool), "\(tool) \(step): the stroke is not the table's")
            }
            let arrow = Annotation(tool: .arrow, start: .zero, end: CGPoint(x: 200, y: 0), style: AnnotationStyle(thickness: step))
            XCTAssertEqual(arrow.outline.boundingBox.height, step.points(for: .arrow) * 3, accuracy: 0.001,
                           "\(step): the head is not three shafts wide")
        }
    }

    func testThePenIsTheSmoothStrokeThePencilDrawsAndTheNamesStayPut() {
        let points = [CGPoint(x: 20, y: 60), CGPoint(x: 100, y: 80), CGPoint(x: 180, y: 60)]
        let pen = Annotation(tool: .pen, start: points[0], end: points[2], points: points)
        let pencil = Annotation(tool: .pencil, start: points[0], end: points[2], points: points)
        XCTAssertEqual(pen.outline, pencil.outline, "the pen is not the smooth stroke the pencil draws")
        XCTAssertEqual(pen.stroke?.cap, .round)
        XCTAssertEqual(pen.stroke?.join, .round)
        XCTAssertEqual(pen.stroke?.multiplies, false)
        XCTAssertEqual(AnnotationTool.pen.rawValue, "pen")
        let deployed = ["arrow", "rectangle", "ellipse", "line", "pencil", "highlighter"]
        XCTAssertEqual(deployed.compactMap(AnnotationTool.init(rawValue:)).count, 6, "a deployed tool name is gone")
    }

    // MARK: what is remembered

    func testEachToolKeepsItsOwnAndAFreshReadReturnsBoth() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(thickness: .thick, opacity: 0.5), for: .pen, in: store(disk))
        // The marker was not touched: it is what a tool nobody picked for is, the middle step at full ink.
        XCTAssertEqual(EditorMemory.read(store(disk)).style(for: .highlighter).thickness, .medium)
        XCTAssertEqual(EditorMemory.read(store(disk)).style(for: .highlighter).opacity, 1)
        EditorMemory.remember(style: AnnotationStyle(thickness: .thin, opacity: 0.3), for: .highlighter, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        XCTAssertEqual(fresh.style(for: .pen).thickness, .thick, "the marker's pick overwrote the pen's step")
        XCTAssertEqual(fresh.style(for: .pen).opacity, 0.5, "the marker's pick overwrote the pen's opacity")
        XCTAssertEqual(fresh.style(for: .highlighter).thickness, .thin)
        XCTAssertEqual(fresh.style(for: .highlighter).opacity, 0.3)
        for other in [AnnotationTool.arrow, .rectangle, .ellipse, .line, .pencil] {
            XCTAssertEqual(fresh.style(for: other).thickness, .medium, "\(other) took a neighbour's step")
            XCTAssertEqual(fresh.style(for: other).opacity, 1, "\(other) took a neighbour's opacity")
        }
    }

    func testEveryToolRoundTripsEveryStepAndTheOpacitiesOnTheirBounds() {
        for tool in AnnotationTool.allCases {
            for step in AnnotationThickness.allCases {
                for opacity in [0.1, 0.35, 1.0] {
                    let disk = backing()
                    let style = AnnotationStyle(color: .blue, thickness: step, filled: true, opacity: opacity)
                    EditorMemory.remember(style: style, for: tool, in: store(disk))
                    XCTAssertEqual(EditorMemory.read(store(disk)).style(for: tool), style, "\(tool) \(step) \(opacity)")
                }
            }
        }
    }

    func testTheColourAndTheFillAreEveryToolsAndTheTwoTablesAreWhatIsStored() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .purple, thickness: .thick, filled: true, opacity: 0.5), for: .pen, in: store(disk))
        EditorMemory.remember(style: AnnotationStyle(color: .purple, thickness: .thin, filled: true, opacity: 0.3), for: .highlighter, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(fresh.style(for: tool).color, .purple, "\(tool): the colour is not shared")
            XCTAssertTrue(fresh.style(for: tool).filled, "\(tool): the fill is not shared")
        }
        // A pick on one tool moves the shared colour for all, and the other tools' steps stay.
        EditorMemory.remember(style: AnnotationStyle(color: .green, thickness: .medium, filled: false, opacity: 1), for: .arrow, in: store(disk))
        let after = EditorMemory.read(store(disk))
        XCTAssertEqual(after.style(for: .pen).color, .green)
        XCTAssertEqual(after.style(for: .pen).thickness, .thick)
        XCTAssertEqual(after.style(for: .highlighter).opacity, 0.3)
        XCTAssertEqual(store(disk).intTable("editorThicknessByTool"), ["pen": 2, "highlighter": 0, "arrow": 1])
        XCTAssertEqual(store(disk).doubleTable("editorOpacityByTool"), ["pen": 0.5, "highlighter": 0.3, "arrow": 1])
        XCTAssertEqual(Key.editorThicknessByTool, "editorThicknessByTool")
        XCTAssertEqual(Key.editorOpacityByTool, "editorOpacityByTool")
    }

    func testTheOldSingleThicknessIsNeitherReadNorMigrated() {
        let kept = store(backing())
        kept.set(2, for: Key.editorThickness)
        let read = EditorMemory.read(kept)
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(read.style(for: tool).thickness, .medium, "\(tool): the retired key was read")
        }
        XCTAssertEqual(Key.editorThickness, "editorThickness", "a deployed name moved")
        EditorMemory.remember(style: AnnotationStyle(thickness: .thin), for: .pen, in: kept)
        XCTAssertEqual(kept.object(Key.editorThickness) as? Int, 2, "the retired key was written or erased")
        XCTAssertEqual(kept.intTable(Key.editorThicknessByTool), ["pen": 0], "the old pick was migrated into the table")
    }

    func testAToolThatWasNeverPickedForReadsTheDefaultWhateverTheOthersHold() {
        let disk = backing()
        for tool in [AnnotationTool.pen, .pencil, .arrow] {
            EditorMemory.remember(style: AnnotationStyle(thickness: .thick, opacity: 0.2), for: tool, in: store(disk))
        }
        let read = EditorMemory.read(store(disk))
        for tool in [AnnotationTool.highlighter, .line, .rectangle, .ellipse] {
            XCTAssertEqual(read.style(for: tool).thickness, .medium, "\(tool)")
            XCTAssertEqual(read.style(for: tool).opacity, 1, "\(tool)")
        }
    }

    func testTheStandardStyleIsFullInk() {
        XCTAssertEqual(AnnotationStyle.standard.opacity, 1)
        XCTAssertEqual(AnnotationStyle(color: .red).opacity, 1)
    }
}
