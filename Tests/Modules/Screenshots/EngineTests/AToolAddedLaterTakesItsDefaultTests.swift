import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **A palette item that did not exist when a person made their picks is shown, as its default says, whatever they picked
/// for the others.** `paletteChoices` holds only what was picked (`PaletteItems`), so an item added by a later release
/// has no entry and takes `PaletteItem.shownByDefault`; a stored list of the hidden ones, or of the shown ones, could not
/// do that for somebody who had already chosen. The editor track adds Eraser, Ruler and Spotlight while this one is
/// written, so no count here is a number: it is `PaletteItem.allCases`, and "a later item" is every case in turn, left out
/// of a table that hides every other one.
///
/// The family: the read walks the cases and asks the table, never the other way; a name the table holds that is no case
/// (a later release's item read by an older one, or `"colours"`) is neither read nor kept; and a write keeps the picks
/// of the others and bounds the record by the cases.
final class AToolAddedLaterTakesItsDefaultTests: XCTestCase {

    private func store(_ table: Any? = nil) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        if let table { backing.set(table, forKey: "module.screenshots.\(ScreenshotsSettings.Key.paletteChoices)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    private func stored(_ store: NamespacedStore) -> [String: Bool] { store.boolTable(ScreenshotsSettings.Key.paletteChoices) }

    func testNothingPickedIsEveryItemItsDefaultInTheOrderOfTheCases() {
        let fresh = store()
        XCTAssertGreaterThan(PaletteItem.allCases.count, 0, "the subject: there are cases")
        XCTAssertEqual(PaletteItems.visible(fresh), PaletteItem.allCases.filter(\.shownByDefault))
        XCTAssertTrue(PaletteItems.picks(fresh).isEmpty)
        for item in PaletteItem.allCases { XCTAssertEqual(PaletteItems.isShown(item, in: fresh), item.shownByDefault, "\(item)") }
    }

    /// Every case as the one that "came later": the table hides all the others, and the one it never heard of is shown.
    func testTheItemTheTableNeverHeardOfIsShownWhileEveryOtherIsHidden() {
        XCTAssertGreaterThan(PaletteItem.allCases.count, 1, "the subject: with one case there is no 'other'")
        for later in PaletteItem.allCases {
            var table: [String: Bool] = [:]
            for item in PaletteItem.allCases where item != later { table[item.rawValue] = false }
            let read = store(table)
            XCTAssertEqual(PaletteItems.visible(read), [later].filter(\.shownByDefault), "\(later) came later and the person's picks hid it")
            XCTAssertEqual(PaletteItems.isShown(later, in: read), later.shownByDefault, "\(later)")
            XCTAssertNil(PaletteItems.picks(read)[later], "\(later): a pick was invented for an item that had none")
            for other in PaletteItem.allCases where other != later {
                XCTAssertFalse(PaletteItems.isShown(other, in: read), "\(other) was picked hidden and shows")
            }
        }
    }

    /// The same, the other way round: a person who showed everything they knew of is not shown a later item against its default.
    func testAnExplicitShowForTheOthersLeavesTheLaterOneToItsDefault() {
        for later in PaletteItem.allCases {
            var table: [String: Bool] = [:]
            for item in PaletteItem.allCases where item != later { table[item.rawValue] = true }
            XCTAssertEqual(PaletteItems.isShown(later, in: store(table)), later.shownByDefault, "\(later)")
        }
    }

    func testAnExplicitPickOverridesTheDefaultBothWays() {
        for item in PaletteItem.allCases {
            for shown in [true, false] {
                let read = store([item.rawValue: shown])
                XCTAssertEqual(PaletteItems.isShown(item, in: read), shown, "\(item) picked \(shown)")
                XCTAssertEqual(PaletteItems.visible(read).contains(item), shown, "\(item) picked \(shown)")
                XCTAssertEqual(PaletteItems.visible(read).count, PaletteItem.allCases.count - (shown ? 0 : 1),
                               "\(item) picked \(shown) moved another item")
            }
        }
    }

    // MARK: - What the table holds beyond the cases

    func testANameThatIsNoCaseIsNeitherReadNorShownNorCounted() {
        let foreign = ["colours", "undo", "redo", "arrow", "more", "done", "close", "laser", "", "PEN", " pen", "pen "]
        for name in foreign {
            XCTAssertNil(PaletteItem(rawValue: name), "the subject: \(name) is no case")
        }
        var table: [String: Bool] = [:]
        for name in foreign { table[name] = false }
        let read = store(table)
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases, "a foreign name hid something")
        XCTAssertTrue(PaletteItems.picks(read).isEmpty, "a foreign name was read as a pick")
        XCTAssertEqual(Set(PaletteItems.picks(read).keys.map(\.rawValue)).subtracting(PaletteItem.allCases.map(\.rawValue)), [])
    }

    /// Whatever the table holds beyond the cases goes with the next write, so the record is bounded by the cases and not by
    /// what a file once said (a thousand foreign keys, the pick this write makes, and the picks that were there).
    func testTheNextWriteDropsEveryForeignNameAndKeepsTheOthersPicks() throws {
        let item = try XCTUnwrap(PaletteItem.allCases.first)
        let kept = try XCTUnwrap(PaletteItem.allCases.last)
        XCTAssertNotEqual(item, kept, "the subject: two different cases")
        var table: [String: Bool] = [kept.rawValue: false, "colours": false]
        for index in 0..<1000 { table["foreign-\(index)"] = index.isMultiple(of: 2) }
        let read = store(table)
        XCTAssertEqual(stored(read).count, 1002, "the subject: the table held the foreign keys")
        PaletteItems.set(item, shown: false, in: read)
        let after = stored(read)
        XCTAssertEqual(Set(after.keys), [item.rawValue, kept.rawValue], "foreign names survived the write: \(after.count) keys")
        XCTAssertEqual(after[kept.rawValue], false, "the write lost a pick the person had made for another item")
        XCTAssertEqual(after[item.rawValue], false)
        XCTAssertLessThanOrEqual(after.count, PaletteItem.allCases.count)
    }

    /// A write for every item in turn, shown and hidden, ends with exactly one entry per case at most, and each pick holds.
    func testWritesInAnyOrderKeepEveryPickAndNeverGrowPastTheCases() {
        let read = store()
        var expected: [PaletteItem: Bool] = [:]
        for round in 0..<3 {
            for (index, item) in PaletteItem.allCases.enumerated() {
                let shown = (index + round).isMultiple(of: 2)
                PaletteItems.set(item, shown: shown, in: read)
                expected[item] = shown
                XCTAssertEqual(PaletteItems.picks(read), expected, "round \(round), \(item)")
                XCTAssertLessThanOrEqual(stored(read).count, PaletteItem.allCases.count)
            }
        }
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases.filter { expected[$0] ?? true })
    }

    /// The write is a pick and nothing else: the same pick twice is the same table, and a pick for one item leaves the rest of the row alone.
    func testASecondIdenticalWriteChangesNothingAndOneItemMovesOnlyItself() {
        let read = store()
        guard let item = PaletteItem.allCases.first else { return XCTFail("no cases") }
        PaletteItems.set(item, shown: false, in: read)
        let once = stored(read)
        PaletteItems.set(item, shown: false, in: read)
        XCTAssertEqual(stored(read), once)
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases.filter { $0 != item })
        PaletteItems.set(item, shown: true, in: read)
        XCTAssertEqual(PaletteItems.visible(read), PaletteItem.allCases)
    }

    /// The raw value is stored data: the names a release has shipped keep reading. A case may retire, never be renamed.
    func testTheShippedRawValuesStayWhatTheyWere() {
        for name in ["pen", "highlighter", "pencil", "eraser", "ruler", "spotlight"] {
            XCTAssertNotNil(PaletteItem(rawValue: name), "\(name) was a case and a table may hold it")
        }
        XCTAssertEqual(Set(PaletteItem.allCases.map(\.rawValue)).count, PaletteItem.allCases.count)
    }
}
