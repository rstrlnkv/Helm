import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The layout file is read from disk and could be anything: huge counts, wrong types, duplicate ids,
/// a newer version, a giant string, an empty file, binary, an oversize file. The answer is a bounded
/// layout or `.unreadable`, never a trap, and a file that was never there is `.absent`.
final class ALayoutFileUnderOddInputsTests: XCTestCase {
    private func read(_ bytes: Data) throws -> LayoutRead {
        let dir = scratchDirectory("layout-odd")
        try bytes.write(to: dir.appendingPathComponent("layout.json"))
        return LayoutStore(directory: dir).load()
    }
    private func read(_ json: String) throws -> LayoutRead { try read(Data(json.utf8)) }

    private func loaded(_ r: LayoutRead, file: StaticString = #filePath, line: UInt = #line) -> LaunchpadLayout {
        guard case .loaded(let l) = r else { XCTFail("not loaded: \(r)", file: file, line: line); return .empty }
        return l
    }

    func testNoFileIsAbsentNotUnreadable() {
        XCTAssertEqual(LayoutStore(directory: scratchDirectory("layout-none")).load(), .absent)
    }

    func testEmptyFileAndBinaryGarbageAreUnreadable() throws {
        XCTAssertEqual(try read(Data()), .unreadable)
        XCTAssertEqual(try read(Data((0..<512).map { UInt8($0 % 251) })), .unreadable)
    }

    func testAVersionAboveTheKnownIsUnreadable() throws {
        XCTAssertEqual(try read(#"{"version": 2, "items": []}"#), .unreadable)
    }

    func testAnOversizeFileIsUnreadableBeforeDecoding() throws {
        let filler = Data(repeating: 0x20, count: LaunchpadLimits.maxFileBytes + 10)
        XCTAssertEqual(try read(Data(#"{"items":[]}"#.utf8) + filler), .unreadable)
    }

    func testHugeCountsAreTruncated() throws {
        let items = (0..<(LaunchpadLimits.maxItems + 500)).map { #"{"app":"id\#($0)"}"# }.joined(separator: ",")
        let l = loaded(try read(#"{"version":1,"items":[\#(items)]}"#))
        XCTAssertEqual(l.items.count, LaunchpadLimits.maxItems)
        let apps = (0..<(LaunchpadLimits.maxFolderApps + 50)).map { "\"x\($0)\"" }.joined(separator: ",")
        let f = loaded(try read(#"{"items":[{"folder":{"name":"F","apps":[\#(apps)]}}]}"#))
        guard case .folder(let folder) = f.items.first else { return XCTFail("no folder") }
        XCTAssertEqual(folder.apps.count, LaunchpadLimits.maxFolderApps)
    }

    func testWrongTypesSkipTheEntryAndKeepTheRest() throws {
        let l = loaded(try read(#"{"items":[1,"x",{"app":5},{"app":"keep"},{"folder":{"name":7,"apps":[1,"in"]}}],"hidden":["h",3]}"#))
        XCTAssertEqual(l.items.first, .app("keep"))
        XCTAssertEqual(l.hidden, ["h"])
        XCTAssertEqual(l.items.count, 2)
    }

    func testAGiantStringIsCut() throws {
        let long = String(repeating: "a", count: 100_000)
        let l = loaded(try read(#"{"items":[{"app":"\#(long)"},{"folder":{"name":"\#(long)","apps":["\#(long)"]}}],"hidden":["\#(long)"]}"#))
        guard case .app(let id) = l.items[0] else { return XCTFail() }
        XCTAssertEqual(id.count, LaunchpadLimits.maxStringLength)
        XCTAssertEqual(l.hidden.first?.count, LaunchpadLimits.maxStringLength)
        guard case .folder(let f) = l.items[1] else { return XCTFail() }
        XCTAssertEqual(f.name.count, LaunchpadLimits.maxFolderName)
    }

    func testDuplicateIdsAreNormalisedAndABadFolderIdGetsAFreshOne() throws {
        let l = loaded(try read(#"{"items":[{"app":"a"},{"app":"a"},{"folder":{"id":"nope","name":"F","apps":["a","b","c"]}}]}"#)).normalized()
        XCTAssertEqual(l.items.count, 2)
        guard case .folder(let f) = l.items[1] else { return XCTFail() }
        XCTAssertEqual(f.apps, ["b", "c"])
        XCTAssertNotEqual(f.id.uuidString, "nope")
        XCTAssertNotNil(UUID(uuidString: f.id.uuidString))
    }

    func testASavedLayoutRoundTrips() throws {
        let dir = scratchDirectory("layout-trip")
        let store = LayoutStore(directory: dir)
        let layout = try XCTUnwrap(LaunchpadLayout(items: [.app("a"), .app("b")]).applying(.makeFolder(drop: "a", onto: "b", name: "F")))
        XCTAssertTrue(store.save(layout))
        XCTAssertEqual(store.load(), .loaded(layout))
    }

    // MARK: Page breaks

    func testAFileWithoutBreaksDecodesAsItAlwaysDidAndABreakRoundTrips() throws {
        let old = loaded(try read(#"{"version": 1, "items": [{"app": "a"}, {"app": "b"}], "hidden": ["h"]}"#))
        XCTAssertEqual(old, LaunchpadLayout(items: [.app("a"), .app("b")], hidden: ["h"]))
        let layout = LaunchpadLayout(items: [.app("a"), .pageBreak, .app("b")])
        let dir = scratchDirectory("layout-breaks")
        let store = LayoutStore(directory: dir)
        XCTAssertTrue(store.save(layout))
        XCTAssertEqual(store.load(), .loaded(layout))
        XCTAssertEqual(try JSONDecoder().decode(LaunchpadLayout.self, from: try JSONEncoder().encode(layout)), layout)
    }

    func testAnOddBreakEntryIsSkippedAndBreaksAtTheEdgesOrInARowDoNotSurviveANormalise() throws {
        let l = loaded(try read(#"{"items": [{"pageBreak": true}, {"app": "a"}, {"pageBreak": false}, {"pageBreak": "yes"}, {"pageBreak": true}, {"pageBreak": true}, {"app": "b"}, {"pageBreak": true}]}"#))
        XCTAssertEqual(l.items, [.pageBreak, .app("a"), .pageBreak, .pageBreak, .app("b"), .pageBreak])
        XCTAssertEqual(l.normalized().items, [.app("a"), .pageBreak, .app("b")])
    }

    func testBreaksCountAgainstTheItemCeiling() throws {
        let items = (0..<(LaunchpadLimits.maxItems + 500)).map { _ in #"{"pageBreak":true}"# }.joined(separator: ",")
        XCTAssertLessThanOrEqual(loaded(try read(#"{"items":[\#(items)]}"#)).items.count, LaunchpadLimits.maxItems)
    }

    func testAlternatingAppsAndBreaksMakeNoMorePagesThanTheCeiling() throws {
        let items = (0..<LaunchpadLimits.maxItems).map { $0 % 2 == 0 ? #"{"app":"id\#($0)"}"# : #"{"pageBreak":true}"# }.joined(separator: ",")
        let l = loaded(try read(#"{"items":[\#(items)]}"#)).normalized()
        let breaks = l.items.filter { $0 == .pageBreak }.count
        XCTAssertEqual(breaks, LaunchpadLimits.maxPages - 1, "the control: breaks stand up to the ceiling")
        XCTAssertEqual(l.items.count - breaks, LaunchpadLimits.maxItems / 2, "the apps all stay, only breaks go")
    }
}
