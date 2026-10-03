import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **The last tool, colour, thickness and fill come back, and a property list that can say
/// anything gets the nearest thing the editor has.** The store is a file any process running
/// as the user can write: a stored number is clamped to the steps there are, and a name that
/// is none of the cases is the default, never a crash and never a stranger's value.
final class TheEditorRemembersItsLastPicksTests: XCTestCase {

    private func store(_ raw: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        for (key, value) in raw { store.set(value, for: key) }
        return store
    }

    private typealias Key = ScreenshotsSettings.Key

    func testAnEmptyStoreIsTheStandardEditor() {
        XCTAssertEqual(EditorMemory.read(store()), EditorMemory())
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(EditorMemory.read(store()).style(for: tool), .standard, "\(tool)")
            XCTAssertNil(EditorMemory.read(store()).style(for: tool).color, "no colour was ever picked, so each tool keeps its own")
        }
    }

    func testWhatWasPickedComesBackWholeForEveryCase() {
        for tool in AnnotationTool.allCases {
            let kept = store()
            EditorMemory.remember(tool: tool, in: kept)
            XCTAssertEqual(EditorMemory.read(kept).tool, tool)
        }
        for color in AnnotationColor.allCases {
            for step in AnnotationThickness.allCases {
                let kept = store()
                let style = AnnotationStyle(color: color, thickness: step, filled: step == .medium)
                EditorMemory.remember(style: style, for: .arrow, in: kept)
                XCTAssertEqual(EditorMemory.read(kept).style(for: .arrow), style, "\(color) \(step)")
            }
        }
    }

    func testPuttingTheToolDownIsRememberedAsNoTool() {
        let kept = store()
        EditorMemory.remember(tool: .pencil, in: kept)
        EditorMemory.remember(tool: nil, in: kept)
        XCTAssertNil(EditorMemory.read(kept).tool)
        XCTAssertNil(kept.object(Key.editorTool), "a tool put down left its name in the store")
    }

    func testAThicknessOutOfRangeIsTheNearestStep() {
        for (stored, step) in [(Int.max, AnnotationThickness.thick), (3, .thick), (2, .thick), (1, .medium),
                               (0, .thin), (-1, .thin), (Int.min, .thin)] as [(Int, AnnotationThickness)] {
            XCTAssertEqual(EditorMemory.read(store([Key.editorThicknessByTool: ["arrow": stored]])).style(for: .arrow).thickness,
                           step, "\(stored)")
        }
    }

    func testAnythingElseInAKeyIsTheDefault() {
        let garbage: [String: Any] = [
            Key.editorTool: "laser", Key.editorColor: "magenta",
            Key.editorThicknessByTool: "thick", Key.editorOpacityByTool: "half", Key.editorFill: "yes",
        ]
        XCTAssertEqual(EditorMemory.read(store(garbage)), EditorMemory())
        let wrongKinds: [String: Any] = [
            Key.editorTool: 7, Key.editorColor: [1, 2], Key.editorThicknessByTool: 1e300, Key.editorFill: 3.5,
        ]
        XCTAssertEqual(EditorMemory.read(store(wrongKinds)).style(for: .arrow).thickness, .medium, "a real number is not a table of steps")
        XCTAssertNil(EditorMemory.read(store(wrongKinds)).tool)
        XCTAssertNil(EditorMemory.read(store(wrongKinds)).style(for: .arrow).color)
        XCTAssertFalse(EditorMemory.read(store(wrongKinds)).style(for: .arrow).filled)
    }

    func testTheSettingsReaderIsNotMovedByTheEditorsKeys() {
        let kept = store()
        EditorMemory.remember(tool: .line, in: kept)
        EditorMemory.remember(style: AnnotationStyle(color: .blue, thickness: .thick, filled: true), for: .line, in: kept)
        XCTAssertEqual(ScreenshotsSettings.read(kept), ScreenshotsSettings.defaults,
                       "the editor's memory changed what a capture does")
    }

    func testTheStoredNamesAreTheDeployedSpellings() {
        XCTAssertEqual(AnnotationTool.allCases.map(\.rawValue), ["arrow", "rectangle", "ellipse", "line", "pen", "pencil", "highlighter", "blur"])
        XCTAssertEqual(AnnotationColor.allCases.map(\.rawValue),
                       ["red", "orange", "yellow", "green", "blue", "purple", "black", "white"])
        XCTAssertEqual(AnnotationThickness.allCases.map(\.rawValue), [0, 1, 2])
    }
}
