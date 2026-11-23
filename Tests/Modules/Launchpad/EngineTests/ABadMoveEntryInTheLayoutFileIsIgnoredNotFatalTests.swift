import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// The `moved` key is read from disk like the rest: an entry that is not a known category is skipped, a key that is not an
/// object reads as no moves, the rest of the layout reads whatever `moved` holds, the count is bounded, and a read changes no byte.
final class ABadMoveEntryInTheLayoutFileIsIgnoredNotFatalTests: XCTestCase {
    private func load(_ json: String) throws -> (LayoutRead, Data) {
        let dir = scratchDirectory("moved-odd")
        let bytes = Data(json.utf8)
        try bytes.write(to: dir.appendingPathComponent("layout.json"))
        let read = LayoutStore(directory: dir).load()
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("layout.json")), bytes, "a read changes no byte")
        return (read, bytes)
    }

    private func loaded(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> LaunchpadLayout {
        guard case .loaded(let l) = try load(json).0 else { XCTFail("not loaded", file: file, line: line); return .empty }
        return l
    }

    func testAGoodEntryIsReadAtAll() throws {
        let l = try loaded(#"{"items":[{"app":"a"}],"moved":{"x":"games","y":"others","z":"developer-tools"}}"#)
        XCTAssertEqual(l.categoryOverrides, ["x": .category(.games), "y": .others, "z": .category(.developerTools)])
    }

    func testABadValueSkipsThatEntryAndKeepsTheOthers() throws {
        for bad in [#""nonsense""#, #""Games""#, #""public.app-category.games""#, "5", "null", "[\"games\"]", #"{"a":"games"}"#, "true", #""""#] {
            let l = try loaded(#"{"items":[{"app":"keep"}],"moved":{"a":\#(bad),"b":"music","c":\#(bad)}}"#)
            XCTAssertEqual(l.categoryOverrides, ["b": .category(.music)], bad)
            XCTAssertEqual(l.items, [.app("keep")], bad)
        }
    }

    func testAMovedThatIsNotAnObjectReadsAsNoMovesAndTheRestReads() throws {
        for bad in ["5", #""games""#, #"["x","games"]"#, "null", "true"] {
            let l = try loaded(#"{"items":[{"app":"keep"}],"hidden":["h"],"moved":\#(bad)}"#)
            XCTAssertEqual(l.categoryOverrides, [:], bad)
            XCTAssertEqual(l.items, [.app("keep")], bad)
            XCTAssertEqual(l.hidden, ["h"], bad)
        }
    }

    func testAnEmptyKeyIsSkippedAndALongKeyIsCut() throws {
        let long = String(repeating: "k", count: LaunchpadLimits.maxStringLength + 1)
        let l = try loaded(#"{"moved":{"":"games","\#(long)":"others"}}"#)
        XCTAssertEqual(l.categoryOverrides, [String(long.prefix(LaunchpadLimits.maxStringLength)): .others])
    }

    func testTooManyEntriesAreBounded() throws {
        let entries = (0..<(LaunchpadLimits.maxApps + 1)).map { #""id\#($0)":"games""# }.joined(separator: ",")
        let l = try loaded(#"{"moved":{\#(entries)}}"#)
        XCTAssertEqual(l.categoryOverrides.count, LaunchpadLimits.maxApps)
    }

    func testMovedBesideBrokenItemsStillReads() throws {
        let l = try loaded(#"{"items":[1,"x",{"app":5},{"app":"keep"}],"moved":{"a":"games"}}"#)
        XCTAssertEqual(l.items, [.app("keep")])
        XCTAssertEqual(l.categoryOverrides, ["a": .category(.games)])
    }
}
