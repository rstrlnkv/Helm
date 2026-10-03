import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// The property list is a file any process running as the person can write. A
/// stored value that is not one of the cases reads as the default; it is never
/// a crash and never "off".
final class TheScreenshotsSettingsSurviveAPlistThatCanSayAnythingTests: XCTestCase {

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    func testAnEmptyStoreIsTheDefaults() {
        let read = ScreenshotsSettings.read(store())
        XCTAssertEqual(read, .defaults)
        XCTAssertEqual(read.saveTarget, .macOS)
        XCTAssertEqual(read.format, .png)
        XCTAssertTrue(read.thumbnail)
        XCTAssertTrue(read.shutterSound)
        XCTAssertFalse(read.showCursor)
        XCTAssertEqual(read.timer, .none)
        XCTAssertFalse(read.rememberSelection)
        XCTAssertNil(read.otherFolder)
    }

    func testEveryCaseReadsBack() {
        for target in SaveTarget.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.saveTarget: target.rawValue])).saveTarget, target)
        }
        for format in ShotFormat.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.format: format.rawValue])).format, format)
        }
        for timer in CaptureTimer.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: timer.rawValue])).timer, timer)
        }
        for mode in PanelMode.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelMode: mode.rawValue])).panelMode, mode)
        }
        XCTAssertFalse(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.thumbnail: false])).thumbnail)
        XCTAssertFalse(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.shutterSound: false])).shutterSound)
        XCTAssertTrue(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.showCursor: true])).showCursor)
        XCTAssertTrue(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.rememberSelection: true])).rememberSelection)
        XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.otherFolder: "/tmp/x"])).otherFolder, "/tmp/x")
    }

    func testGarbageReadsAsTheDefaultsAndNeverAsOff() {
        let garbage: [Any] = [Data([1]), ["file"], "FILE", "", 1e300, Int.max, -1, Double.nan, 2]
        for value in garbage {
            let read = ScreenshotsSettings.read(store([
                ScreenshotsSettings.Key.saveTarget: value, ScreenshotsSettings.Key.format: value,
                ScreenshotsSettings.Key.thumbnail: value, ScreenshotsSettings.Key.shutterSound: value,
                ScreenshotsSettings.Key.showCursor: value, ScreenshotsSettings.Key.timer: value,
                ScreenshotsSettings.Key.rememberSelection: value, ScreenshotsSettings.Key.panelMode: value,
                ScreenshotsSettings.Key.otherFolder: value is String && value as! String != "" ? "" : value]))
            XCTAssertEqual(read.saveTarget, .macOS, "\(value)")
            XCTAssertEqual(read.format, .png, "\(value)")
            XCTAssertTrue(read.thumbnail, "a thumbnail setting of \(value) was read as off")
            XCTAssertTrue(read.shutterSound, "a shutter setting of \(value) was read as off")
            XCTAssertFalse(read.showCursor, "\(value)")
            XCTAssertEqual(read.timer, .none, "a timer of \(value) was read as a countdown")
            XCTAssertFalse(read.rememberSelection, "\(value)")
            XCTAssertEqual(read.panelMode, .area, "\(value)")
            XCTAssertNil(read.otherFolder, "a folder of \(value) was read as a path")
        }
    }

    func testATimerThatIsNotAChoiceIsNoCountdown() {
        for seconds in [1, 7, 60, 3600, Int.max] {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: seconds])).timer, .none, "\(seconds)")
        }
    }

    func testAFolderLongerThanAnyPathIsNone() {
        let long = "/" + String(repeating: "a", count: ScreenshotsSettings.longestFolder)
        XCTAssertNil(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.otherFolder: long])).otherFolder)
    }

    func testOnlyTheClipboardMakesNoFile() {
        for target in SaveTarget.allCases {
            XCTAssertEqual(target.savesAFile, target != .clipboard, "\(target)")
        }
    }

    // MARK: the editor's two tables

    private typealias Key = ScreenshotsSettings.Key

    /// Whatever a table's key holds, every tool reads a step in 0…2 and an opacity in 0.1…1.
    private func assertEveryToolIsInBounds(_ values: [String: Any], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let read = EditorMemory.read(store(values))
        for tool in AnnotationTool.allCases {
            let style = read.style(for: tool)
            XCTAssertTrue(AnnotationThickness.allCases.contains(style.thickness), "\(label) \(tool): step \(style.thickness)", file: file, line: line)
            XCTAssertTrue(style.opacity.isFinite && (0.1...1).contains(style.opacity), "\(label) \(tool): opacity \(style.opacity)", file: file, line: line)
        }
    }

    func testATableThatIsNotATableIsEveryToolsDefault() {
        let notTables: [Any] = [1e300, Double.nan, -1, Int.max, "pen", "", true, Data([1]), ["pen"], [2, 3], [String: Any]()]
        for value in notTables {
            for key in [Key.editorThicknessByTool, Key.editorOpacityByTool] {
                let read = EditorMemory.read(store([key: value]))
                for tool in AnnotationTool.allCases {
                    XCTAssertEqual(read.style(for: tool).thickness, .medium, "\(key) = \(value) \(tool): the step is not the default")
                    XCTAssertEqual(read.style(for: tool).opacity, 1, "\(key) = \(value) \(tool): the opacity is not the default")
                }
            }
            assertEveryToolIsInBounds([Key.editorThicknessByTool: value, Key.editorOpacityByTool: value], "both = \(value)")
        }
    }

    func testAnEntryOutOfRangeIsTheNearestStepAndTheNearestOpacity() {
        for (stored, step) in [(Int.max, AnnotationThickness.thick), (3, .thick), (2, .thick), (1, .medium),
                               (0, .thin), (-1, .thin), (Int.min, .thin)] as [(Int, AnnotationThickness)] {
            let read = EditorMemory.read(store([Key.editorThicknessByTool: ["pen": stored]]))
            XCTAssertEqual(read.style(for: .pen).thickness, step, "\(stored)")
            XCTAssertEqual(read.style(for: .highlighter).thickness, .medium, "\(stored): a neighbour moved")
        }
        let cases: [(Double, Double)] = [(1e300, 1), (.infinity, 1), (2, 1), (1, 1), (0.5, 0.5), (0.1, 0.1),
                                         (0.05, 0.1), (0, 0.1), (-1, 0.1), (-1e300, 0.1), (-.infinity, 0.1), (.nan, 1)]
        for (stored, opacity) in cases {
            let read = EditorMemory.read(store([Key.editorOpacityByTool: ["pen": stored]]))
            XCTAssertEqual(read.style(for: .pen).opacity, opacity, "\(stored)")
            XCTAssertEqual(read.style(for: .highlighter).opacity, 1, "\(stored): a neighbour moved")
        }
    }

    func testATableOfAThousandEntriesAndStrangersIsReadByTheToolsThereAre() {
        var steps: [String: Int] = [:], opacities: [String: Double] = [:]
        for index in 0..<1000 { steps["laser\(index)"] = index; opacities["laser\(index)"] = Double(index) / 10 }
        steps["pen"] = 2; opacities["pen"] = 0.4
        let read = EditorMemory.read(store([Key.editorThicknessByTool: steps, Key.editorOpacityByTool: opacities]))
        XCTAssertEqual(read.style(for: .pen).thickness, .thick, "the real entry was lost among the strangers")
        XCTAssertEqual(read.style(for: .pen).opacity, 0.4)
        for tool in AnnotationTool.allCases where tool != .pen {
            XCTAssertEqual(read.style(for: tool).thickness, .medium, "\(tool) took a stranger's entry")
            XCTAssertEqual(read.style(for: tool).opacity, 1, "\(tool) took a stranger's entry")
        }
        XCTAssertEqual(read, EditorMemory.read(store([Key.editorThicknessByTool: ["pen": 2], Key.editorOpacityByTool: ["pen": 0.4]])),
                       "the strangers changed what was read")
    }

    func testAnUnknownToolKeyIsNoToolAndAWrongKindInsideATableIsTheDefault() {
        let unknown = EditorMemory.read(store([Key.editorThicknessByTool: ["laser": 2, "": 2, "PEN": 2, "pen ": 2],
                                               Key.editorOpacityByTool: ["laser": 0.5, "": 0.5, "PEN": 0.5]]))
        XCTAssertEqual(unknown, EditorMemory.read(store()), "a name that is no tool was read as one")
        let mixed: [String: Any] = ["pen": "thick", "pencil": 2]
        assertEveryToolIsInBounds([Key.editorThicknessByTool: mixed, Key.editorOpacityByTool: ["pen": "half", "pencil": 0.5] as [String: Any]], "mixed")
        let thickness = EditorMemory.read(store([Key.editorThicknessByTool: mixed]))
        XCTAssertEqual(thickness.style(for: .pen).thickness, .medium, "a string was read as a step")
    }

    func testTheEditorsMemoryWritesNothingBackAndTheSettingsReaderIsUnmoved() {
        let values: [String: Any] = [Key.editorThicknessByTool: 1e300, Key.editorOpacityByTool: "x"]
        let kept = store(values)
        _ = EditorMemory.read(kept)
        XCTAssertEqual(kept.object(Key.editorThicknessByTool) as? Double, 1e300)
        XCTAssertEqual(kept.object(Key.editorOpacityByTool) as? String, "x")
        XCTAssertEqual(ScreenshotsSettings.read(kept), .defaults)
    }

    func testTheFormatsNameTheirFiles() {
        XCTAssertEqual(ShotFormat.png.pathExtension, "png")
        XCTAssertEqual(ShotFormat.jpeg.pathExtension, "jpg")
    }
}
