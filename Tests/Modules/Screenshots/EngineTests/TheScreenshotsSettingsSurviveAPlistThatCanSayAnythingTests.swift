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
        // 30 is a choice since the panel's timer menu offers it.
        XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: 30])).timer, .thirty)
        for seconds in [1, 7, 15, 31, 60, 3600, Int.max] {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: seconds])).timer, .none, "\(seconds)")
        }
    }

    func testTheTimerLengthAndThePanelsPlaceReadAsTheDefaultsFromAnythingAPlistCanHold() {
        let garbage: [Any] = [Data([1]), ["file"], "FILE", "", "5", 1e300, -1e300, Int.max, Int.min, -1, 0, 2, 7,
                              Double.nan, Double.infinity, -Double.infinity, true]
        for value in garbage {
            let read = ScreenshotsSettings.read(store([
                ScreenshotsSettings.Key.timer: 10, ScreenshotsSettings.Key.timerLength: value,
                ScreenshotsSettings.Key.panelOffsetX: value, ScreenshotsSettings.Key.panelOffsetY: value]))
            XCTAssertEqual(read.timerLength, .five, "a length of \(value) was not read as five, and with a timer of ten stored: a damaged key is not a missing one")
            XCTAssertEqual(read.timer, .ten, "\(value): the length key moved the timer")
            XCTAssertTrue(read.panelOffset.dx.isFinite && read.panelOffset.dy.isFinite, "a place of \(value) reached the panel as \(read.panelOffset)")
            XCTAssertLessThanOrEqual(abs(read.panelOffset.dx), PanelOffset.ceiling, "\(value)")
            XCTAssertLessThanOrEqual(abs(read.panelOffset.dy), PanelOffset.ceiling, "\(value)")
        }
    }

    func testAPlaceThatIsNoNumberIsNoMoveAndTheAxesAreJudgedAlone() {
        for value in [Double.nan, 0] {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelOffsetX: value])).panelOffset, .zero, "\(value)")
        }
        for value: Any in ["x", true, Data([1]), ["a"], [1.0]] {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelOffsetX: value,
                                                           ScreenshotsSettings.Key.panelOffsetY: value])).panelOffset, .zero, "\(value)")
        }
        let half = ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelOffsetX: Double.nan,
                                                   ScreenshotsSettings.Key.panelOffsetY: 40.5])).panelOffset
        XCTAssertEqual(half, PanelOffset(dx: 0, dy: 40.5), "a bad axis took the good one with it")
        let far = ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelOffsetX: 1e300,
                                                  ScreenshotsSettings.Key.panelOffsetY: -Double.infinity])).panelOffset
        XCTAssertEqual(far, PanelOffset(dx: PanelOffset.ceiling, dy: -PanelOffset.ceiling), "a number that is only large is held at the ceiling")
        XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelOffsetX: 12, ScreenshotsSettings.Key.panelOffsetY: -7])).panelOffset,
                       PanelOffset(dx: 12, dy: -7), "an integer is a number too")
    }

    func testTheReaderWritesNothingBackFromADamagedTimerLengthOrPlace() {
        let kept = store([ScreenshotsSettings.Key.timerLength: "x", ScreenshotsSettings.Key.panelOffsetX: 1e300])
        _ = ScreenshotsSettings.read(kept)
        XCTAssertEqual(kept.object(ScreenshotsSettings.Key.timerLength) as? String, "x")
        XCTAssertEqual(kept.object(ScreenshotsSettings.Key.panelOffsetX) as? Double, 1e300)
        XCTAssertNil(kept.object(ScreenshotsSettings.Key.panelOffsetY))
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

    // MARK: the palette's picks

    /// A value for `paletteChoices` that is no table of picks reads as no picks: every item is on the palette, whatever
    /// the file said, and nothing here crashes, hides an item or is written back.
    func testAPaletteChoicesValueThatIsNoTableIsNoPicks() {
        let notTables: [Any] = ["pen", "undo", "colours", "arrow", "", "true", 1e300, Double.nan, -1, 0, 1, Int.max, true, false,
                                Data([1]), ["pen"], ["pen", "pencil", "colours"], [Bool](repeating: false, count: 1000),
                                (0..<1000).map { "value-\($0)" }, [String: Any](), [[String: Bool]]()]
        for value in notTables {
            let read = store([Key.paletteChoices: value])
            XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases, "a paletteChoices of \(value) hid something")
            XCTAssertTrue(PaletteItems.picks(read).isEmpty, "a paletteChoices of \(value) was read as picks")
            XCTAssertEqual(ScreenshotsSettings.read(read), .defaults, "a paletteChoices of \(value) moved another setting")
            XCTAssertEqual(EditorMemory.read(read), EditorMemory.read(store()), "a paletteChoices of \(value) moved the editor's memory")
        }
    }

    /// The names that must never be read as an item, as a table of "hide it": the colours and the way out are not on the list,
    /// and neither is a glyph tool, which stands in the ⋯ menu with nowhere to be taken from.
    func testNoNameThatIsNoPaletteItemHidesAnythingAndTheNextWriteDropsIt() {
        let names = ["colours", "colors", "colour", "undo", "redo", "more", "done", "close", "arrow", "rectangle", "ellipse", "line", "select"]
        let hideEverything = Dictionary(uniqueKeysWithValues: names.map { ($0, false) })
        let read = store([Key.paletteChoices: hideEverything])
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases, "a name that is no item hid the palette's row")
        for name in names { XCTAssertNil(PaletteItem(rawValue: name), "\(name) became a case: it can now be hidden") }
        PaletteItems.set(.pen, shown: false, in: read)
        XCTAssertEqual(Set(read.boolTable(Key.paletteChoices).keys), [PaletteItem.pen.rawValue], "the write kept names that are no item")
        XCTAssertEqual(read.boolTable(Key.paletteChoices).count, 1)
    }

    /// A thousand keys that no case answers to: not read, and no longer in the store after one write.
    func testAThousandForeignKeysAreNotReadAndAreGoneAfterOneWrite() {
        var table: [String: Bool] = [:]
        for index in 0..<1000 { table["foreign-\(index)"] = false }
        let read = store([Key.paletteChoices: table])
        XCTAssertEqual(read.boolTable(Key.paletteChoices).count, 1000, "the subject: the table is in the store")
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases)
        PaletteItems.set(.highlighter, shown: false, in: read)
        XCTAssertEqual(read.boolTable(Key.paletteChoices), [PaletteItem.highlighter.rawValue: false])
    }

    /// A value that is no Bool does not hide the item it sits under: a string, a number other than a Bool, a list, a table.
    func testAnItemWhoseValueIsNoBoolIsOnThePalette() {
        let strangers: [Any] = ["false", "no", "hidden", 2, -1, 1e300, Double.nan, Data([0]), [false], ["shown": false], NSNull()]
        for stranger in strangers {
            for item in PaletteItem.allCases {
                let read = store([Key.paletteChoices: [item.rawValue: stranger]])
                XCTAssertTrue(PaletteItems.isShown(item, in: read), "\(item) = \(stranger) hid the item")
            }
        }
    }

    /// The palette's picks are not a sealed setting and nothing reads them unattended; the key is read and never written by a read.
    func testReadingThePicksWritesNothingBack() {
        let values: [String: Any] = [Key.paletteChoices: ["pen": false, "colours": false, "laser": true]]
        let read = store(values)
        _ = PaletteItems.visible(read)
        _ = PaletteItems.picks(read)
        _ = PaletteItems.isShown(.pen, in: read)
        XCTAssertEqual(read.object(Key.paletteChoices) as? [String: Bool], ["pen": false, "colours": false, "laser": true],
                       "a read rewrote the table")
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases.filter { $0 != .pen })
    }

    /// One value in the table that is no Bool costs the picks beside it nothing: the table is read case by case, as
    /// `EditorMemory` reads its own (`testAnUnknownToolKeyIsNoToolAndAWrongKindInsideATableIsTheDefault`).
    func testAPickBesideAValueThatIsNoBoolIsKept() {
        let strangers: [Any] = [5, "laser", "false", 2.5, Data([0]), [true], ["x": false], NSNull(), 1e300]
        for stranger in strangers {
            let read = store([Key.paletteChoices: ["pen": false, "laser": stranger, "pencil": stranger, "highlighter": true] as [String: Any]])
            XCTAssertFalse(PaletteItems.isShown(.pen, in: read), "the pen was picked hidden and \(stranger) beside it undid the pick")
            XCTAssertEqual(PaletteItems.picks(read), [.pen: false, .highlighter: true], "\(stranger): the picks beside it are not as written")
            XCTAssertTrue(PaletteItems.isShown(.pencil, in: read), "\(stranger) under pencil is no pick: the default decides")
        }
    }

    /// A number in the table: what `as? Bool` makes of it. An `NSNumber` (what a property list hands back) and a Swift
    /// integer boxed in `Any` alike read as a Bool when exactly 0 or 1 and as no pick otherwise.
    /// Harm: none that matters. A hand-written `0` hides the item as `false` would, `1` is the default, and the next write
    /// replaces the table with real Bools; no other item's pick is touched and nothing crashes.
    func testANumberInTheTableIsAPickOnlyAsAnNSNumberOfZeroOrOne() {
        let asNumbers: [(Any, Bool?)] = [(NSNumber(value: 0), false), (NSNumber(value: 1), true), (NSNumber(value: 0.0), false),
                                         (NSNumber(value: 1.0), true), (NSNumber(value: 2), nil), (NSNumber(value: -1), nil),
                                         (NSNumber(value: 0.5), nil), (NSNumber(value: Double.nan), nil),
                                         (NSNumber(value: Int.max), nil)]
        for (number, pick) in asNumbers {
            let read = store([Key.paletteChoices: ["pen": number, "pencil": false] as [String: Any]])
            XCTAssertEqual(PaletteItems.picks(read)[.pen], pick, "\(number) as a pick")
            XCTAssertEqual(PaletteItems.picks(read)[.pencil], false, "\(number) beside it cost the pencil's pick")
            XCTAssertEqual(PaletteItems.isShown(.pen, in: read), pick ?? PaletteItem.pen.shownByDefault)
            PaletteItems.set(.highlighter, shown: false, in: read)
            let after = read.boolTable(Key.paletteChoices)
            XCTAssertEqual(after["highlighter"], false, "\(number): the write did not take")
            XCTAssertEqual(after["pencil"], false, "\(number): the write lost a pick beside the number")
            XCTAssertEqual(after["pen"], pick, "\(number): the write kept it as \(String(describing: pick))")
        }
        // Measured: a Swift integer boxed in `Any` bridges the same way, 0 and 1 and nothing else.
        for (plain, pick) in [(0, false), (1, true), (2, nil), (-1, nil)] as [(Int, Bool?)] {
            XCTAssertEqual(PaletteItems.picks(store([Key.paletteChoices: ["pen": plain] as [String: Any]]))[.pen], pick, "Int \(plain)")
        }
    }
}
