import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **The colour of an older Helm is read as the start of a tool with no colour of its own, for as long as no `editorInk` is there, and a pick in the editor never writes it; a stored ink that cannot
/// be read is no colour, and is not mended by the colour before it.** `editorColor` is the swatch's name (the Settings row writes it), `editorInk` is three sRGB
/// numbers. The reader asks `editorInk` first; only a key that is *absent* sends it to the old one. A key that is there and damaged
/// is a property list somebody wrote, and a colour from before it would be a guess shown as the person's pick. A read writes nothing:
/// the store compared whole, before and after, so a write of any key is seen, not only of the two named.
final class TheOldColourIsReadWhileNoInkIsThereTests: XCTestCase {

    private typealias Key = ScreenshotsSettings.Key

    private func made(_ raw: [String: Any] = [:]) -> (NamespacedStore, InMemoryKeyValueStore) {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        for (key, value) in raw { store.set(value, for: key) }
        return (store, backing)
    }

    func testTheOldNameIsReadWhileNoInkIsThere() {
        let (store, _) = made([Key.editorColor: "blue"])
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .blue)
        XCTAssertEqual(EditorMemory.read(store).style(for: .highlighter).color, .blue, "a tool with no ink of its own starts with it")
        for color in AnnotationColor.allCases {
            XCTAssertEqual(EditorMemory.read(made([Key.editorColor: color.rawValue]).0).style(for: .arrow).color, AnnotationInk(color), "\(color)")
        }
    }

    func testAnInkIsWrittenForTheToolAsThreeNumbersAndTheOldKeyIsLeftAsItWas() throws {
        let (store, backing) = made([Key.editorColor: "blue"])
        let ink = try XCTUnwrap(AnnotationInk(red: 0.2, green: 0.4, blue: 0.6))
        EditorMemory.remember(style: AnnotationStyle(color: ink, thickness: .thick, filled: true), for: .arrow, in: store)
        let written = try XCTUnwrap((store.object(Key.editorInkByTool) as? [String: [Double]])?["arrow"], "the ink is not a list of numbers: \(String(describing: store.object(Key.editorInkByTool)))")
        XCTAssertEqual(written, [0.2, 0.4, 0.6])
        XCTAssertNil(store.object(Key.editorInk), "a pick wrote the shared ink")
        XCTAssertEqual(store.object(Key.editorColor) as? String, "blue", "a pick in the editor wrote `editorColor`")
        XCTAssertEqual(backing.raw.keys.filter { $0.contains("editorColor") }.count, 1)
        XCTAssertEqual(EditorMemory.read(store).style(for: .arrow).color, ink, "and the next read is the ink")
    }

    func testAnInkOfASwatchIsWrittenAsItsNumbersToo() {
        for color in AnnotationColor.allCases {
            let (store, _) = made()
            EditorMemory.remember(style: AnnotationStyle(color: AnnotationInk(color)), for: .pen, in: store)
            XCTAssertNil(store.object(Key.editorColor), "\(color): a swatch's pick in the editor wrote `editorColor`")
            XCTAssertEqual(((store.object(Key.editorInkByTool) as? [String: [Double]])?["pen"])?.count, 3, "\(color)")
            XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, AnnotationInk(color), "\(color)")
        }
    }

    func testWhenBothAreThereTheInkWins() throws {
        let ink = try XCTUnwrap(AnnotationInk(red: 0.2, green: 0.4, blue: 0.6))
        let (store, _) = made([Key.editorColor: "blue", Key.editorInk: [0.2, 0.4, 0.6]])
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, ink)
        XCTAssertNotEqual(EditorMemory.read(store).style(for: .pen).color, .blue, "control: the old name says something else")
    }

    func testAnInkThatCannotBeReadIsNoColourAndTheOldNameDoesNotFillIn() {
        let unreadable: [(String, Any)] = [
            ("a string", "0.2,0.4,0.6"), ("two numbers", [0.2, 0.4]), ("four numbers", [0.2, 0.4, 0.6, 1.0]), ("none", [Double]()),
            ("NaN", [Double.nan, 0.4, 0.6]), ("infinity", [0.2, Double.infinity, 0.6]), ("minus infinity", [0.2, 0.4, -Double.infinity]),
            ("a number", 7), ("a table", ["r": 1]), ("words", ["a", "b", "c"]), ("a flag", true),
        ]
        for (name, value) in unreadable {
            let (store, backing) = made([Key.editorColor: "blue", Key.editorInk: value])
            let before = backing.raw as NSDictionary
            XCTAssertNil(EditorMemory.read(store).style(for: .pen).color, "\(name): the ink is damaged and the old colour filled in")
            XCTAssertNil(EditorMemory.read(store).style(for: .highlighter).color, "\(name)")
            XCTAssertEqual(backing.raw as NSDictionary, before, "\(name): a read wrote something back")
        }
    }

    func testAReadWritesNothingBackWhateverIsThere() {
        let shapes: [[String: Any]] = [
            [:], [Key.editorColor: "blue"], [Key.editorColor: "magenta"], [Key.editorColor: 3],
            [Key.editorInk: [0.2, 0.4, 0.6]], [Key.editorInk: [2.0, -1.0, 0.5]], [Key.editorColor: "blue", Key.editorInk: [0.2, 0.4, 0.6]],
        ]
        for raw in shapes {
            let (store, backing) = made(raw)
            let before = backing.raw as NSDictionary
            _ = EditorMemory.read(store)
            XCTAssertEqual(backing.raw as NSDictionary, before, "\(raw): the read changed the store")
        }
    }

    func testANumberOutOfRangeIsTheNearestInk() {
        let (store, _) = made([Key.editorInk: [2.0, -1.0, 0.5]])
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, AnnotationInk(red: 1, green: 0, blue: 0.5))
        XCTAssertNotNil(EditorMemory.read(store).style(for: .pen).color, "control: the ink was read at all")
        for huge in [1e300, -1e300, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(EditorMemory.read(made([Key.editorInk: [huge, huge, huge]]).0).style(for: .pen).color,
                           AnnotationInk(red: huge > 0 ? 1 : 0, green: huge > 0 ? 1 : 0, blue: huge > 0 ? 1 : 0), "\(huge)")
        }
    }

    func testIntegersAreNumbersToo() {
        // A property list that says <integer>1</integer> is as good as 1.0.
        XCTAssertEqual(EditorMemory.read(made([Key.editorInk: [1, 0, 0]]).0).style(for: .pen).color, AnnotationInk(red: 1, green: 0, blue: 0))
        XCTAssertNotEqual(AnnotationInk(red: 1, green: 0, blue: 0), AnnotationInk.red, "control: the swatch red is not pure red")
    }

    func testPuttingNoColourDownWritesNoInk() {
        let (store, backing) = made([Key.editorColor: "blue"])
        EditorMemory.remember(style: AnnotationStyle(color: nil, thickness: .thin, filled: false), for: .pen, in: store)
        XCTAssertNil(store.object(Key.editorInkByTool), "no colour is picked and an ink was written")
        XCTAssertEqual(store.object(Key.editorColor) as? String, "blue")
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .blue, "the old colour is still the one read")
        func spelled(_ key: String) -> String { "module.\(ScreenshotsEngine.moduleID).\(key)" }
        XCTAssertTrue(backing.raw.keys.contains(spelled(Key.editorColor)), "control: this is how the backing spells a key of the store")
        XCTAssertFalse(backing.raw.keys.contains(spelled(Key.editorInk)), "no colour put down, and `editorInk` was written")
    }

    func testAnInkAndNoOldKeyAreReadWhole() throws {
        let ink = try XCTUnwrap(AnnotationInk(red: 0.123456789, green: 0.5, blue: 0.987654321))
        let (store, _) = made()
        EditorMemory.remember(style: AnnotationStyle(color: ink), for: .pen, in: store)
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, ink, "three doubles come back exactly")
    }
}
