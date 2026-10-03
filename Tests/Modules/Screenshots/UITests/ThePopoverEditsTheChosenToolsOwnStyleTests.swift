import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmUI
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The thickness-and-opacity pop-over edits the chosen tool's own style, opens from a second click on the chosen
/// row object or from ⋯, and says its numbers in the person's language.**
///
/// Written against these names, which the engineer's change has to carry (or tell the tester the new ones):
/// - `EditorAction.thicknessAndOpacity(anchorX:)` opens the pop-over at a cell's centre (palette-local points) and
///   `EditorAction.opacity(Double)` sets the opacity (0.1…1); `EditorAction.thickness(_)` is the existing step.
/// - `EditorPalette.action(forClickOn:chosen:anchorX:)` is what a click on a row object sends: the tool for a first
///   click, the pop-over for a second one on the chosen object.
/// - `EditorPopover.thicknessText(_:for:)` and `EditorPopover.opacityText(_:)` are the numbers on the right.
/// - `CaptureOverlay.popoverIsOpen` and `EditorChrome.popover` (via `chrome(on:)`).
///
/// The per-tool half of the memory lives in `EachToolKeepsItsOwnThicknessAndOpacityTests`; this file asks the same
/// of the overlay, which is where a pick is written, with a store behind it.
@MainActor
final class ThePopoverEditsTheChosenToolsOwnStyleTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        AppLanguage.override = nil
        super.tearDown()
    }

    private func build(store: NamespacedStore? = nil) throws -> (DisplayID, OverlayView) {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: id, at: CGPoint(x: 100, y: 100), flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: 500, y: 400), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    // MARK: what a click on a row object sends

    func testASecondClickOnTheChosenRowObjectOpensThePopoverAndAFirstClickDoesNot() {
        let rowObjects = EditorPalette.objects.filter { $0.place == .row }.map(\.tool)
        XCTAssertEqual(Set(rowObjects), [.pen, .highlighter, .pencil], "the control: the row is the three the plan names")
        for tool in rowObjects {
            XCTAssertEqual(EditorPalette.action(forClickOn: tool, chosen: tool, anchorX: 120), .thicknessAndOpacity(anchorX: 120),
                           "\(tool): the second click on the chosen one")
            for chosen in [nil] + AnnotationTool.allCases.filter({ $0 != tool }).map({ Optional($0) }) {
                XCTAssertEqual(EditorPalette.action(forClickOn: tool, chosen: chosen, anchorX: 120), .tool(tool),
                               "\(tool): a first click (\(String(describing: chosen)) is chosen) chooses, it does not open")
            }
        }
    }

    // MARK: the overlay

    func testThePopoverOpensForAChosenToolAndNotForSelect() throws {
        let (id, _) = try build()
        let overlay = try XCTUnwrap(overlay)
        XCTAssertFalse(overlay.popoverIsOpen, "control: closed to begin with")
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        XCTAssertFalse(overlay.popoverIsOpen, "no tool is chosen (Select) and Select has no steps")
        XCTAssertNil(overlay.chrome(on: id)?.popover)
        overlay.perform(.tool(.pen))
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        XCTAssertTrue(overlay.popoverIsOpen)
        let popover = try XCTUnwrap(overlay.chrome(on: id)?.popover, "open, and the chrome has no rect for it")
        let palette = try XCTUnwrap(overlay.chrome(on: id)?.palette)
        XCTAssertEqual(popover.minY, palette.maxY + 8, accuracy: 0.5, "stands under the palette")
    }

    /// The menu item is for any tool with steps: the arrow has them and has no cell on the row.
    func testTheMenuRouteOpensItAtTheMoreCellForATableToolWithNoCell() throws {
        let (id, _) = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.arrow))
        for _ in 0..<20 where overlay.bars.moreFrame == .zero { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertGreaterThan(overlay.bars.moreFrame.width, 20, "control: the palette reported ⋯'s cell")
        overlay.perform(.thicknessAndOpacity(anchorX: overlay.bars.moreFrame.midX))
        XCTAssertTrue(overlay.popoverIsOpen)
        let chrome = try XCTUnwrap(overlay.chrome(on: id))
        let popover = try XCTUnwrap(chrome.popover)
        XCTAssertEqual(popover.midX, chrome.palette.minX + overlay.bars.moreFrame.midX, accuracy: 1.5, "centred on ⋯, in display points")
    }

    // MARK: each tool keeps its own

    func testTheOpacityOfOneToolIsNotTheNextToolsAndComesBackWithItsTool() throws {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        _ = try build(store: store)
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.opacity(0.5))
        XCTAssertEqual(overlay.bars.style.opacity, 0.5, accuracy: 0.001, "the pick shows on the palette")
        overlay.perform(.tool(.highlighter))
        XCTAssertEqual(overlay.bars.style.opacity, 1, accuracy: 0.001, "Marker has its own: the Pen's 50 % did not follow")
        overlay.perform(.opacity(0.3))
        overlay.perform(.thickness(.thin))
        overlay.perform(.tool(.pen))
        XCTAssertEqual(overlay.bars.style.opacity, 0.5, accuracy: 0.001, "the Pen got its own back")
        XCTAssertEqual(overlay.bars.style.thickness, .medium, "the Pen never had a step picked")
        overlay.perform(.tool(.highlighter))
        XCTAssertEqual(overlay.bars.style.opacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(overlay.bars.style.thickness, .thin)
        // And in the store, where the next editor reads it from.
        let read = EditorMemory.read(store)
        XCTAssertEqual(read.style(for: .pen).opacity, 0.5, accuracy: 0.001)
        XCTAssertEqual(read.style(for: .pen).thickness, .medium)
        XCTAssertEqual(read.style(for: .highlighter).opacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(read.style(for: .highlighter).thickness, .thin)
        XCTAssertEqual(read.style(for: .pencil).opacity, 1, accuracy: 0.001, "a tool nobody touched stays at full ink")
    }

    func testAnOpacityOutOfRangeOrNotANumberIsHeldToTheRange() throws {
        _ = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pencil))
        for (given, expected) in [(0.01, 0.1), (-3.0, 0.1), (7.0, 1.0), (0.1, 0.1), (1.0, 1.0)] {
            overlay.perform(.opacity(given))
            XCTAssertEqual(overlay.bars.style.opacity, expected, accuracy: 0.001, "given \(given)")
        }
        overlay.perform(.opacity(0.4))
        overlay.perform(.opacity(.nan))
        XCTAssertTrue((0.1...1).contains(overlay.bars.style.opacity), "no number is not a stroke nobody can see: \(overlay.bars.style.opacity)")
    }

    // MARK: the numbers

    /// The number is the step's points from `AnnotationThickness.points(for:)`, for every tool and every step.
    func testTheNumberIsThePointsOfTheStepForEveryToolAndStep() throws {
        AppLanguage.override = .en
        for tool in AnnotationTool.allCases {
            for step in AnnotationThickness.allCases {
                let text = EditorPopover.thicknessText(step, for: tool)
                let unit = Self.macOSPointsUnit(.en)
                XCTAssertTrue(text.hasSuffix(unit), "\(tool) \(step): «\(text)»")
                let number = Self.numberBefore(unit, in: text)
                XCTAssertEqual(Double(number), Double(step.points(for: tool)), "\(tool) \(step): «\(text)»")
            }
        }
    }

    /// Spelled out here, in each of the eight languages: Pen thin is 1.5 pt, Pen medium 3, Marker medium 12, Pencil
    /// medium 3.5. The decimal mark is the language's own; the unit is the language's own (en `pt`, ru «пт», zh «点»).
    func testTheNumberIsInTheLanguagesOwnFormat() {
        var units = Set<String>()
        AppLanguage.each { language in
            let unit = Self.macOSPointsUnit(language)
            units.insert(unit)
            let mark = Locale(identifier: language.rawValue).decimalSeparator ?? "."
            XCTAssertEqual(mark, [.ru, .fr, .de, .es, .pt].contains(language) ? "," : ".", "control: the language's own mark")
            func number(_ text: String) -> String { Self.numberBefore(unit, in: text) }
            for (step, tool, expected) in [(AnnotationThickness.thin, AnnotationTool.pen, "1\(mark)5"),
                                           (.medium, .pen, "3"), (.medium, .highlighter, "12"), (.medium, .pencil, "3\(mark)5")] {
                let text = EditorPopover.thicknessText(step, for: tool)
                XCTAssertTrue(text.hasSuffix(unit), "\(language) \(tool): «\(text)» should end in macOS's «\(unit)»")
                XCTAssertEqual(number(text), expected, "\(language) \(tool) \(step): «\(text)»")
            }
        }
        XCTAssertTrue(units.contains { $0 != "pt" }, "control: macOS itself spells the unit differently in some of the eight: \(units)")
    }

    /// Ruler.loctable names its languages by region where there is more than one: Simplified Chinese, Brazilian Portuguese.
    private nonisolated static func loctableKey(_ language: AppLanguage) -> String {
        switch language { case .zh: return "zh_CN"; case .pt: return "pt_BR"; default: return language.rawValue }
    }

    /// The unit macOS writes for points, read from AppKit's own `Ruler.loctable` key `pt` (an independent source, not the
    /// engineer's table). 
    private nonisolated static func macOSPointsUnit(_ language: AppLanguage) -> String {
        let url = URL(fileURLWithPath: "/System/Library/Frameworks/AppKit.framework/Resources/Ruler.loctable")
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entry = table[Self.loctableKey(language)] as? [String: String], let unit = entry["pt"], !unit.isEmpty else {
            XCTFail("Ruler.loctable has no `pt` for \(language)"); return "?"
        }
        return unit
    }

    /// The text without its unit and without the spaces (breaking or not) between: the unit's length is not assumed.
    private nonisolated static func numberBefore(_ unit: String, in text: String) -> String {
        guard text.hasSuffix(unit) else { return text }
        return String(text.dropLast(unit.count)).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{00A0}\u{202F}")))
    }

    func testTheOpacityIsAWholePercentInEveryLanguage() {
        AppLanguage.each { language in
            for (value, expected) in [(1.0, "100"), (0.5, "50"), (0.1, "10"), (0.55, "55")] {
                let text = EditorPopover.opacityText(value)
                XCTAssertTrue(text.contains("%"), "\(language) \(value): «\(text)»")
                XCTAssertEqual(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces), expected,
                               "\(language) \(value): «\(text)»")
            }
        }
    }
}
