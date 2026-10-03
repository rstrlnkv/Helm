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
/// row object or from ⋯, and says its words and percent in the person's language.**
///
/// - `EditorAction.thicknessAndOpacity(anchorX:)` opens the pop-over at a cell's centre (palette-local points) and
///   `EditorAction.opacity(Double)` sets the opacity (0.1…1); `EditorAction.thickness(_)` is the existing step.
/// - `EditorPalette.action(forClickOn:chosen:anchorX:)` is what a click on a row object sends: the tool for a first
///   click, the pop-over for a second one on the chosen object.
/// - `ScStr.thickness(_:)` (the step's word) and `EditorPopover.opacityText(_:)` are what stands on the right.
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
        XCTAssertEqual(Set(rowObjects), [.pen, .highlighter, .pencil, .spotlight], "the control: the row is the three pens and the spotlight")
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
        for _ in 0..<20 where overlay.palette.moreFrame == .zero { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertGreaterThan(overlay.palette.moreFrame.width, 20, "control: the palette reported ⋯'s cell")
        overlay.perform(.thicknessAndOpacity(anchorX: overlay.palette.moreFrame.midX))
        XCTAssertTrue(overlay.popoverIsOpen)
        let chrome = try XCTUnwrap(overlay.chrome(on: id))
        let popover = try XCTUnwrap(chrome.popover)
        XCTAssertEqual(popover.midX, chrome.palette.minX + overlay.palette.moreFrame.midX, accuracy: 1.5, "centred on ⋯, in display points")
    }

    // MARK: each tool keeps its own

    func testTheOpacityOfOneToolIsNotTheNextToolsAndComesBackWithItsTool() throws {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
        _ = try build(store: store)
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.opacity(0.5))
        XCTAssertEqual(overlay.palette.style.opacity, 0.5, accuracy: 0.001, "the pick shows on the palette")
        overlay.perform(.tool(.highlighter))
        XCTAssertEqual(overlay.palette.style.opacity, 1, accuracy: 0.001, "Marker has its own: the Pen's 50 % did not follow")
        overlay.perform(.opacity(0.3))
        overlay.perform(.thickness(.thin))
        overlay.perform(.tool(.pen))
        XCTAssertEqual(overlay.palette.style.opacity, 0.5, accuracy: 0.001, "the Pen got its own back")
        XCTAssertEqual(overlay.palette.style.thickness, .medium, "the Pen never had a step picked")
        overlay.perform(.tool(.highlighter))
        XCTAssertEqual(overlay.palette.style.opacity, 0.3, accuracy: 0.001)
        XCTAssertEqual(overlay.palette.style.thickness, .thin)
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
            XCTAssertEqual(overlay.palette.style.opacity, expected, accuracy: 0.001, "given \(given)")
        }
        overlay.perform(.opacity(0.4))
        overlay.perform(.opacity(.nan))
        XCTAssertTrue((0.1...1).contains(overlay.palette.style.opacity), "no number is not a stroke nobody can see: \(overlay.palette.style.opacity)")
    }

    // MARK: the words and the percent

    /// The thickness is said as the step's word, as the frame has it («Средняя»), and the card reads it from `ScStr.thickness`;
    /// the points are not said. (The marks under the slider are measured on the render, in `ThePopoverSliderAndTheOpenMenusReturnKeyTests`.)
    func testTheThicknessIsAWordNotPoints() throws {
        let card = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPopover.swift")
        XCTAssertTrue(card.contains("number: ScStr.thickness(model.picked.thickness)"), "the thickness row does not say the step's word")
        XCTAssertFalse(card.contains("points(for:"), "the card still says points")
    }

    /// The word is there in each of the eight languages, a different one for each step; Russian is the frame's.
    func testTheStepsWordIsThereAndDistinctInEveryLanguage() {
        AppLanguage.each { language in
            let words = AnnotationThickness.allCases.map(ScStr.thickness)
            XCTAssertFalse(words.contains(where: \.isEmpty), "\(language): \(words)")
            XCTAssertEqual(Set(words).count, words.count, "\(language): \(words)")
            if language == .ru { XCTAssertEqual(words, ["Тонкая", "Средняя", "Толстая"]) }
        }
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
