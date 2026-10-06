import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **Each tool keeps its own colour; only the fill stays everybody's.**
///
/// The colour was one `editorInk` for every tool, so a pick with the Pen recoloured the Marker. The colour is now kept like the
/// thickness and the opacity (`EachToolKeepsItsOwnThicknessAndOpacityTests`): one record per tool, read by walking the tools
/// there are and asking the record about each, never by walking the record. The record is a table from the tool's raw value to
/// three numbers, under `Key.editorInkByTool`, whose value is spelled out once below: a deployed key is never re-keyed. Where the test can say "a tool's colour is no other tool's"
/// it does so over `AnnotationTool.allCases`, never over a list typed here, so a tool added later is held to it too.
///
/// A tool with no record starts with `editorInk`, else with `editorColor` (the Settings row's own value, written by the row
/// and read live): nobody's colour changes on update, and a pick on one tool never touches either (else the next read would
/// hand the pick to every tool that had no record yet).
final class EachToolKeepsItsOwnColourTests: XCTestCase {

    private typealias Key = ScreenshotsSettings.Key

    private let perToolKey = Key.editorInkByTool

    func testThePerToolKeyIsTheDeployedName() {
        XCTAssertEqual(Key.editorInkByTool, "editorInkByTool", "a key that is out in the store must not be re-keyed")
    }

    private func backing() -> InMemoryKeyValueStore { InMemoryKeyValueStore() }
    private func store(_ backing: InMemoryKeyValueStore) -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }
    private func colours(_ memory: EditorMemory) -> [AnnotationTool: AnnotationInk?] {
        Dictionary(uniqueKeysWithValues: AnnotationTool.allCases.map { ($0, memory.style(for: $0).color) })
    }

    // MARK: a pick is one tool's

    func testAPickWithOneToolLeavesEveryOtherToolsColourAlone() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .blue), for: .pen, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        XCTAssertEqual(fresh.style(for: .pen).color, .blue)
        for tool in AnnotationTool.allCases where tool != .pen {
            XCTAssertNil(fresh.style(for: tool).color, "\(tool) took the Pen's pick: nobody picked for it, so it reads its own default")
            XCTAssertEqual(fresh.style(for: tool).ink(for: tool), AnnotationStyle().ink(for: tool), "\(tool): the default is the tool's")
        }
    }

    func testTwoToolsKeepTwoColoursAndAFreshReadReturnsBoth() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .blue), for: .pen, in: store(disk))
        EditorMemory.remember(style: AnnotationStyle(color: .green), for: .highlighter, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        XCTAssertEqual(fresh.style(for: .pen).color, .blue, "the Marker's pick overwrote the Pen's colour")
        XCTAssertEqual(fresh.style(for: .highlighter).color, .green)
        for tool in AnnotationTool.allCases where tool != .pen && tool != .highlighter {
            XCTAssertNil(fresh.style(for: tool).color, "\(tool) took a neighbour's colour")
        }
    }

    func testTheInMemoryNoteIsTheSameAsTheStoresRead() {
        // `note` is what the overlay keeps beside the store: it must say what the next read says, or the overlay and the next capture disagree.
        var noted = EditorMemory()
        noted.note(style: AnnotationStyle(color: .blue), for: .pen)
        noted.note(style: AnnotationStyle(color: .green), for: .highlighter)
        XCTAssertEqual(noted.style(for: .pen).color, .blue, "note: the Marker's pick reached the Pen")
        XCTAssertEqual(noted.style(for: .highlighter).color, .green)
        XCTAssertNil(noted.style(for: .arrow).color, "note: a tool nobody picked for took a pick")
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .blue), for: .pen, in: store(disk))
        EditorMemory.remember(style: AnnotationStyle(color: .green), for: .highlighter, in: store(disk))
        XCTAssertEqual(colours(noted), colours(EditorMemory.read(store(disk))), "the overlay's memory and the store's read disagree")
    }

    func testEveryToolRoundTripsAColourOfItsOwnThroughAFreshRead() {
        let disk = backing()
        var wanted: [AnnotationTool: AnnotationInk] = [:]
        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let ink = AnnotationInk(red: Double(index) / 20, green: 0.25, blue: 1 - Double(index) / 20)!
            wanted[tool] = ink
            EditorMemory.remember(style: AnnotationStyle(color: ink), for: tool, in: store(disk))
        }
        let fresh = EditorMemory.read(store(disk))
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(fresh.style(for: tool).color, wanted[tool], "\(tool): its own colour did not come back")
        }
        XCTAssertEqual(Set(wanted.values).count, AnnotationTool.allCases.count, "control: every tool was given a different colour")
    }

    func testAPickOnOneToolKeepsThatToolsOtherPicksAndTheFillIsStillEverybodys() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .blue, thickness: .thick, filled: true, opacity: 0.5), for: .pen, in: store(disk))
        EditorMemory.remember(style: AnnotationStyle(color: .green, thickness: .thin, filled: true, opacity: 0.3), for: .highlighter, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        XCTAssertEqual(fresh.style(for: .pen), AnnotationStyle(color: .blue, thickness: .thick, filled: true, opacity: 0.5))
        XCTAssertEqual(fresh.style(for: .highlighter), AnnotationStyle(color: .green, thickness: .thin, filled: true, opacity: 0.3))
        for tool in AnnotationTool.allCases { XCTAssertTrue(fresh.style(for: tool).filled, "\(tool): the fill is not shared") }
    }

    /// A pick with no colour in it (the tool has not one yet) writes no colour for the tool, and never somebody else's.
    func testAPickWithNoColourWritesNoColourForAnyone() {
        let disk = backing()
        EditorMemory.remember(style: AnnotationStyle(color: .blue), for: .pen, in: store(disk))
        EditorMemory.remember(style: AnnotationStyle(color: nil, thickness: .thin), for: .highlighter, in: store(disk))
        let fresh = EditorMemory.read(store(disk))
        XCTAssertEqual(fresh.style(for: .pen).color, .blue)
        XCTAssertNil(fresh.style(for: .highlighter).color, "the Marker was given the Pen's colour by a pick that carried none")
    }

    // MARK: migration

    func testAStoreWithOnlyTheSharedInkGivesEveryToolThatInk() {
        let kept = store(backing())
        kept.set([0.2, 0.4, 0.6], for: Key.editorInk)
        let read = EditorMemory.read(kept)
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(read.style(for: tool).color, AnnotationInk(red: 0.2, green: 0.4, blue: 0.6), "\(tool): its colour changed on update")
        }
    }

    func testAStoreWithOnlyTheOldSwatchNameGivesEveryToolThatSwatch() {
        let kept = store(backing())
        kept.set(AnnotationColor.green.rawValue, for: Key.editorColor)
        let read = EditorMemory.read(kept)
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(read.style(for: tool).color, AnnotationInk(.green), "\(tool): its colour changed on update")
        }
    }

    func testAStoreWithNothingGivesEveryToolItsDefault() {
        let read = EditorMemory.read(store(backing()))
        for tool in AnnotationTool.allCases { XCTAssertNil(read.style(for: tool).color, "\(tool)") }
    }

    /// The pick after a migration is the one tool's: the shared source stays what it was, so the others still read it.
    func testAPickAfterAMigrationChangesTheOneToolAndTheOthersKeepWhatTheyMigratedWithAndAfterAnotherRead() {
        for legacy in ["editorInk", "editorColor"] {
            let disk = backing()
            let kept = store(disk)
            if legacy == "editorInk" { kept.set([0, 0, 1], for: Key.editorInk) } else { kept.set(AnnotationColor.blue.rawValue, for: Key.editorColor) }
            let migrated = EditorMemory.read(kept).style(for: .pen).color
            XCTAssertNotNil(migrated, "\(legacy): control: the source was read")
            EditorMemory.remember(style: AnnotationStyle(color: .orange), for: .pen, in: kept)
            for _ in 0..<2 {
                let fresh = EditorMemory.read(store(disk))
                XCTAssertEqual(fresh.style(for: .pen).color, .orange, "\(legacy): the pick did not stay")
                for tool in AnnotationTool.allCases where tool != .pen {
                    XCTAssertEqual(fresh.style(for: tool).color, migrated, "\(legacy): the Pen's pick reached \(tool)")
                }
            }
        }
    }

    /// The per-tool record, once it exists, is the colour; the shared source is the start of a tool with no entry in it and nothing more.
    func testATableThatSaysNothingOfAToolLeavesItWithTheMigratedInkAndATablesEntryWins() {
        let kept = store(backing())
        kept.set([0, 0, 1], for: Key.editorInk)
        kept.set(["pen": [1.0, 0.5, 0.0]], for: perToolKey)
        let read = EditorMemory.read(kept)
        XCTAssertEqual(read.style(for: .pen).color, AnnotationInk(red: 1, green: 0.5, blue: 0), "the table's own entry lost to the shared ink")
        XCTAssertEqual(read.style(for: .highlighter).color, AnnotationInk(red: 0, green: 0, blue: 1), "a tool with no entry did not start with the shared ink")
    }

    /// What the Settings row writes (`editorColor`) is read by the editor as the colour a tool starts with until it has its own:
    /// a pick made, the row changed, the Marker (never picked for) starts with the row's colour and the Pen keeps its own.
    func testTheSettingsRowIsTheStartOfAToolWithNoColourOfItsOwn() {
        let disk = backing()
        let kept = store(disk)
        EditorMemory.remember(style: AnnotationStyle(color: .orange), for: .pen, in: kept)
        kept.set(AnnotationColor.blue.rawValue, for: Key.editorColor)
        let read = EditorMemory.read(store(disk))
        XCTAssertEqual(read.style(for: .pen).color, .orange, "the row overwrote a colour the Pen has of its own")
        XCTAssertEqual(read.style(for: .highlighter).color, AnnotationInk(.blue), "the row's colour is ignored for a tool that has none of its own")
    }

    /// What the Settings row does in full: writes `editorColor` and removes `editorInk` (`ScreenshotsSettingsPage`), after a shared ink
    /// and a tool's own entry were stored. The shared ink is gone, the tool with an entry keeps it, a tool with none reads the row's swatch.
    func testTheRowsWriteAfterASharedInkWasStoredHidesNothingAndKeepsAToolsOwnEntry() {
        let disk = backing()
        let kept = store(disk)
        kept.set([1.0, 0.0, 1.0], for: Key.editorInk)
        EditorMemory.remember(style: AnnotationStyle(color: .orange), for: .pen, in: kept)
        XCTAssertEqual(EditorMemory.read(kept).style(for: .highlighter).color, AnnotationInk(red: 1, green: 0, blue: 1), "control: the shared ink hides the row")
        kept.set(AnnotationColor.green.rawValue, for: Key.editorColor)
        kept.set(nil, for: Key.editorInk)
        XCTAssertNil(kept.object(Key.editorInk))
        let read = EditorMemory.read(store(disk))
        XCTAssertEqual(read.style(for: .pen).color, .orange)
        XCTAssertEqual(read.style(for: .highlighter).color, AnnotationInk(.green))
        XCTAssertEqual(read.style(for: .arrow).color, AnnotationInk(.green))
    }

    // MARK: a plist that can say anything

    private func assertBounded(_ kept: NamespacedStore, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let read = EditorMemory.read(kept)
        for tool in AnnotationTool.allCases {
            if let ink = read.style(for: tool).color {
                for part in [ink.red, ink.green, ink.blue] {
                    XCTAssertTrue((0...1).contains(part), "\(what): \(tool) read a component of \(part)", file: file, line: line)
                }
            }
            // `ink(for:)` is what is drawn: it is always a colour, whatever the record said.
            XCTAssertTrue((0...1).contains(read.style(for: tool).ink(for: tool).red), "\(what): \(tool)", file: file, line: line)
        }
    }

    func testARecordOfTheWrongTypeReadsAsNoColourForAnyoneAndNeverMakesAnotherToolsColour() {
        let wrong: [(String, Any)] = [
            ("a string", "blue"), ("a number", 3), ("a list", [1.0, 0.0, 0.0]), ("a bool", true),
            ("a table of strings", ["pen": "red"]), ("a table of numbers", ["pen": 1.0]),
            ("a table of bools", ["pen": true]), ("a table of tables", ["pen": ["r": 1.0]]),
            ("a table of a list of strings", ["pen": ["1", "0", "0"]]),
            ("a table with one good and one wrong entry", ["pen": [1.0, 0.0, 0.0], "highlighter": "blue"]),
        ]
        // Control, or every case below passes for a record nobody reads: a well-formed record is read.
        let good = store(backing())
        good.set(["pen": [0.0, 0.0, 1.0]], for: perToolKey)
        XCTAssertEqual(EditorMemory.read(good).style(for: .pen).color, AnnotationInk(red: 0, green: 0, blue: 1), "control: a well-formed record is not read")
        for (name, value) in wrong {
            let kept = store(backing())
            kept.set(value, for: perToolKey)
            assertBounded(kept, name)
            let read = EditorMemory.read(kept)
            // No tool reads another tool's entry: where the Pen has a good one, only the Pen may have it.
            for tool in AnnotationTool.allCases where tool != .pen {
                XCTAssertNotEqual(read.style(for: tool).color, AnnotationInk(red: 1, green: 0, blue: 0), "\(name): \(tool) read the Pen's entry")
            }
        }
    }

    func testAnEntryOfTheWrongArityOrNotNumbersIsNoColourForThatToolAndNoOtherToolReadsIt() {
        let bad: [(String, Any)] = [
            ("empty", [Double]()), ("one", [1.0]), ("two", [1.0, 0.0]), ("four", [1.0, 0.0, 0.0, 1.0]), ("thirty", [Double](repeating: 1, count: 30)),
            ("strings", ["1", "0", "0"]), ("nested", [[1.0], [0.0], [0.0]]),
        ]
        for (name, entry) in bad {
            let kept = store(backing())
            kept.set(["pen": entry, "highlighter": [0.0, 1.0, 0.0]], for: perToolKey)
            assertBounded(kept, name)
            let read = EditorMemory.read(kept)
            // An entry of another type may make the table read whole as no record (as the thickness tables do): the control is for the numbers' own.
            if entry is [Double] {
                XCTAssertEqual(read.style(for: .highlighter).color, AnnotationInk(red: 0, green: 1, blue: 0), "\(name): control: the good entry beside it is not read")
                XCTAssertNil(read.style(for: .pen).color, "\(name): an entry of the wrong arity was read as a colour")
            }
            for tool in AnnotationTool.allCases where tool != .pen && tool != .highlighter {
                XCTAssertNotEqual(read.style(for: tool).color, AnnotationInk(red: 0, green: 1, blue: 0), "\(name): \(tool) read the Marker's entry")
            }
        }
    }

    func testNaNInfinityAndOutOfRangeComponentsNeverReachADrawnColour() {
        let hostile: [[Double]] = [
            [.nan, 0, 0], [0, .nan, 0], [0, 0, .nan], [.infinity, 0, 0], [-.infinity, 0, 0],
            [2, 0, 0], [-1, 0, 0], [1e308, 0, 0], [0, 0, -1e308], [0, 0, .leastNonzeroMagnitude],
        ]
        for entry in hostile {
            let kept = store(backing())
            kept.set(["pen": entry, "highlighter": [0.0, 1.0, 0.0]], for: perToolKey)
            assertBounded(kept, "\(entry)")
            XCTAssertEqual(EditorMemory.read(kept).style(for: .highlighter).color, AnnotationInk(red: 0, green: 1, blue: 0),
                           "\(entry): control: the good entry beside it is not read")
            // Not a number is no colour: it is not black, which is what a component read as 0 would draw.
            if entry.contains(where: \.isNaN) {
                XCTAssertNil(EditorMemory.read(kept).style(for: .pen).color, "\(entry): a component that is not a number made a colour")
            }
        }
    }

    func testAStrangersKeyInTheRecordIsNeverReadAsAToolAndIsDroppedByTheNextWrite() {
        let disk = backing()
        let kept = store(disk)
        let strangers = ["Pen", "PEN", "pen ", "", "__proto__", "step\u{0}", "../pen", "pen/../arrow", String(repeating: "x", count: 5_000), "\u{1F58A}"]
        var record: [String: Any] = ["pen": [0.0, 0.0, 1.0]]
        for stranger in strangers { record[stranger] = [1.0, 0.0, 0.0] }
        kept.set(record, for: perToolKey)
        let read = EditorMemory.read(kept)
        XCTAssertEqual(read.style(for: .pen).color, AnnotationInk(red: 0, green: 0, blue: 1))
        for tool in AnnotationTool.allCases where tool != .pen {
            XCTAssertNotEqual(read.style(for: tool).color, AnnotationInk(red: 1, green: 0, blue: 0), "\(tool) read a stranger's entry")
        }
        EditorMemory.remember(style: AnnotationStyle(color: .green), for: .arrow, in: kept)
        let table = kept.object(perToolKey) as? [String: Any]
        XCTAssertEqual(Set((table ?? [:]).keys), ["pen", "arrow"], "a stranger's key survived a write: \(String(describing: table?.keys))")
    }

    func testAReadThatCannotBeUnderstoodWritesNothingBack() {
        let disk = backing()
        let kept = store(disk)
        kept.set("not a table", for: perToolKey)
        kept.set([0.1, 0.2], for: Key.editorInk)
        kept.set("blue", for: Key.editorColor)
        _ = EditorMemory.read(kept)
        XCTAssertEqual(kept.object(perToolKey) as? String, "not a table", "a read rewrote the damaged record")
        XCTAssertEqual(kept.object(Key.editorInk) as? [Double], [0.1, 0.2], "a read rewrote the shared ink")
        XCTAssertEqual(kept.object(Key.editorColor) as? String, "blue", "a read rewrote the old swatch")
    }

    /// Only a missing key signals migration: a damaged `editorInk` is no colour, and the old swatch is not asked then, for every tool.
    func testADamagedSharedInkIsNotMigratedAndTheOldSwatchIsNotAskedThen() {
        for damaged in [[0.1, 0.2], [Double.nan, 0, 0], "blue"] as [Any] {
            let kept = store(backing())
            kept.set(damaged, for: Key.editorInk)
            kept.set(AnnotationColor.green.rawValue, for: Key.editorColor)
            let read = EditorMemory.read(kept)
            for tool in AnnotationTool.allCases {
                XCTAssertNil(read.style(for: tool).color, "\(damaged): \(tool) read a colour from a record that cannot be read")
            }
        }
    }

    /// A pick on top of a damaged record repairs it for that tool and does not turn the damage into a colour for the others.
    func testAPickOnADamagedRecordWritesThatToolAloneAndNoCrash() {
        let disk = backing()
        let kept = store(disk)
        kept.set("not a table", for: perToolKey)
        EditorMemory.remember(style: AnnotationStyle(color: .blue), for: .pen, in: kept)
        let read = EditorMemory.read(store(disk))
        XCTAssertEqual(read.style(for: .pen).color, .blue)
        for tool in AnnotationTool.allCases where tool != .pen { XCTAssertNil(read.style(for: tool).color, "\(tool)") }
    }
}
