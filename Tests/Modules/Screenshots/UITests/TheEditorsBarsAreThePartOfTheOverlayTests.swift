import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The tool bar and the action row are part of the overlay:** they stand on the display
/// being edited and nowhere else, inside it in every language, they go while an object is
/// drawn and come back on the release, a press on one starts no object and selects no new
/// area, a bar and a key are one meaning, and what was picked is the next object's and the
/// next capture's. The panels are built and never ordered in; each test asserts that the
/// overlay finished before it asserts what it finished with.
@MainActor
final class TheEditorsBarsAreThePartOfTheOverlayTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        super.tearDown()
    }

    private func freeze() throws -> (Freeze, [DisplayID]) {
        var frames: [FrozenDisplay] = []
        for (index, screen) in NSScreen.screens.enumerated() {
            let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32)
            let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            frames.append(FrozenDisplay(id: DisplayID(number),
                                        frame: CGRect(x: 100_000 * CGFloat(index), y: 0, width: 1000, height: 800),
                                        scale: 1, image: try XCTUnwrap(context.makeImage())))
        }
        return (Freeze(displays: frames.map { .image($0) }, windows: []), frames.map(\.id))
    }

    /// The first display's id and the others', with a fresh overlay over every screen.
    @discardableResult
    private func build(store: NamespacedStore? = nil) throws -> (first: DisplayID, others: [DisplayID]) {
        overlay?.close()
        results = []
        let (freeze, ids) = try freeze()
        let built = CaptureOverlay(freeze: freeze, store: store) { [weak self] in self?.results.append($0) }
        XCTAssertTrue(built.build())
        overlay = built
        return (ids[0], Array(ids.dropFirst()))
    }

    private func memory() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    private func select(_ id: DisplayID, _ rect: CGRect? = nil) {
        let rect = rect ?? area
        overlay?.mouseDown(on: id, at: rect.origin, flags: [])
        overlay?.mouseDragged(on: id, at: CGPoint(x: rect.maxX, y: rect.maxY), flags: [])
        overlay?.mouseUp(on: id)
    }

    private func stroke(_ id: DisplayID, from: CGPoint = CGPoint(x: 150, y: 150), to: CGPoint = CGPoint(x: 300, y: 250)) {
        overlay?.mouseDown(on: id, at: from, flags: [])
        overlay?.mouseDragged(on: id, at: to, flags: [])
        overlay?.mouseUp(on: id)
    }

    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private func edited(file: StaticString = #filePath, line: UInt = #line)
        -> (local: CGRect, layers: [Annotation], exit: EditorExit)? {
        XCTAssertEqual(results.count, 1, "the overlay did not finish exactly once: \(results)", file: file, line: line)
        guard case .edited(_, let local, let layers, let exit)? = results.first else {
            XCTFail("\(results)", file: file, line: line)
            return nil
        }
        return (local, layers, exit)
    }

    private func centre(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    // MARK: where they stand

    func testBothBarsStandInsideTheEditedDisplayAndOnNoOtherInEveryLanguage() throws {
        let selections = [area, CGRect(x: 940, y: 740, width: 60, height: 60), CGRect(x: 0, y: 0, width: 1000, height: 800),
                          CGRect(x: 5, y: 700, width: 12, height: 12)]
        AppLanguage.each { current in
            let language = "\(current)"
            do { for selection in selections {
                let (first, others) = try build()
                select(first, selection)
                let chrome = try XCTUnwrap(overlay?.chrome(on: first), "\(language) \(selection): no bars on the edited display")
                let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
                XCTAssertTrue(bounds.contains(chrome.tools), "\(language) \(selection): the tool bar \(chrome.tools) is off the display")
                XCTAssertTrue(bounds.contains(chrome.actions), "\(language) \(selection): the row \(chrome.actions) is off the display")
                XCTAssertFalse(chrome.tools.intersects(chrome.actions), "\(language) \(selection): the bars meet")
                XCTAssertTrue((40...120).contains(chrome.tools.width) && chrome.tools.height > 150 && chrome.tools.height < 600,
                              "\(language): the tool bar measured \(chrome.tools.size)")
                XCTAssertTrue(chrome.actions.width > 100 && chrome.actions.width < 500 && chrome.actions.height > 20,
                              "\(language): the row measured \(chrome.actions.size)")
                XCTAssertTrue(try XCTUnwrap(overlay?.view(for: first)).barsAreShown, "\(language): the bars are not on screen")
                for other in others {
                    XCTAssertNil(overlay?.chrome(on: other), "\(language): bars on a display that is not the edited one")
                    XCTAssertFalse(try XCTUnwrap(overlay?.view(for: other)).barsAreShown)
                }
            } } catch { XCTFail("\(language): \(error)") }
        }
    }

    func testNoBarsBeforeAnAreaExistsOrWhileANewOneIsDragged() throws {
        let (first, _) = try build()
        XCTAssertNil(overlay?.chrome(on: first))
        overlay?.mouseDown(on: first, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: first, at: CGPoint(x: 300, y: 300), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "bars over a selection still being dragged")
        overlay?.mouseUp(on: first)
        XCTAssertNotNil(overlay?.chrome(on: first))
    }

    // MARK: while an object is drawn

    func testTheBarsGoWhileAnObjectIsDrawnAndAreBackOnTheRelease() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.rectangle))
        let view = try XCTUnwrap(overlay?.view(for: first))
        XCTAssertTrue(view.barsAreShown)
        overlay?.mouseDown(on: first, at: CGPoint(x: 150, y: 150), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "the bars stayed up under a press")
        XCTAssertFalse(view.barsAreShown)
        overlay?.mouseDragged(on: first, at: CGPoint(x: 400, y: 350), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "the bars stayed up under the drag")
        XCTAssertFalse(view.barsAreShown)
        XCTAssertEqual(view.drawnShapes.count, 1, "nothing was being drawn, so the test saw nothing")
        overlay?.mouseUp(on: first)
        XCTAssertNotNil(overlay?.chrome(on: first), "the bars did not come back on the release")
        XCTAssertTrue(view.barsAreShown)
    }

    // MARK: a click on a bar

    func testAPressOnABarStartsNoObjectAndSelectsNoNewArea() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        let view = try XCTUnwrap(overlay?.view(for: first))
        for bar in [chrome.tools, chrome.actions] {
            XCTAssertTrue(view.isBar(view.clickTarget(at: centre(bar))), "a click in the middle of a bar reaches the picture")
            // The gap between two buttons is on the bar and not on the picture either.
            overlay?.mouseDown(on: first, at: CGPoint(x: bar.minX + 1, y: bar.minY + 1), flags: [])
            overlay?.mouseDragged(on: first, at: CGPoint(x: bar.minX + 30, y: bar.minY + 30), flags: [])
            overlay?.mouseUp(on: first)
        }
        XCTAssertEqual(view.drawnShapes.count, 0, "a press on a bar drew something")
        overlay?.perform(.exit(.confirm))
        let done = try XCTUnwrap(edited())
        XCTAssertTrue(done.layers.isEmpty, "a press on a bar became a layer: \(done.layers)")
        XCTAssertEqual(done.local, area, "a press on a bar moved the area")
    }

    func testThePictureBesideABarStillDrawsSoTheTestAboveCanSeeADraft() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        stroke(first)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(try XCTUnwrap(edited()).layers.count, 1)
    }

    func testAPressOnABarsBackgroundWithdrawsEscsQuestion() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        stroke(first)
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "Esc with layers closed at once: \(results)")
        // The corner of the bar is background, not a button.
        overlay?.mouseDown(on: first, at: CGPoint(x: chrome.tools.minX + 1, y: chrome.tools.minY + 1), flags: [])
        overlay?.mouseUp(on: first)
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "the press on the bar did not withdraw the question: \(results)")
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    func testAPressOnABarWithNoToolDoesNotReplaceTheArea() throws {
        let (first, _) = try build()
        select(first)
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        // No tool, no layers: a press elsewhere starts a new area; a press on a bar must not.
        overlay?.mouseDown(on: first, at: centre(chrome.tools), flags: [])
        overlay?.mouseDragged(on: first, at: CGPoint(x: 700, y: 700), flags: [])
        overlay?.mouseUp(on: first)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(try XCTUnwrap(edited()).local, area)
    }

    /// A pick that arrives under a live draft — a key or a button — is the next object's and never the
    /// draft's: the draft keeps the tool, colour, thickness and fill it began with, and the object after it
    /// takes the picks. The same rule by key and by button.
    func testAPickUnderALiveDraftIsTheNextObjectsAndNeverTheDrafts() throws {
        for viaKey in [true, false] {
            let (first, _) = try build()
            select(first)
            overlay?.perform(.tool(.rectangle))
            overlay?.mouseDown(on: first, at: CGPoint(x: 150, y: 150), flags: [])
            overlay?.mouseDragged(on: first, at: CGPoint(x: 250, y: 220), flags: [])
            let view = try XCTUnwrap(overlay?.view(for: first))
            XCTAssertEqual(view.drawnShapes.count, 1, "viaKey=\(viaKey): no draft was on screen, so the picks below meet none")
            if viaKey {
                overlay?.keyDown(key(31))     // the ellipse's key
            } else {
                overlay?.bars.perform(.tool(.ellipse))
            }
            overlay?.perform(.color(.blue))
            overlay?.perform(.thickness(.thick))
            overlay?.perform(.toggleFill)
            overlay?.mouseDragged(on: first, at: CGPoint(x: 300, y: 260), flags: [])
            overlay?.mouseUp(on: first)
            stroke(first, from: CGPoint(x: 320, y: 150), to: CGPoint(x: 420, y: 250))
            overlay?.perform(.exit(.confirm))
            let layers = try XCTUnwrap(edited()).layers
            XCTAssertEqual(layers.map(\.tool), [.rectangle, .ellipse], "viaKey=\(viaKey): the draft changed its tool or the next did not take the pick")
            XCTAssertEqual(layers[0].style, .standard, "viaKey=\(viaKey): a pick under the draft reached the draft: \(layers[0].style)")
            XCTAssertEqual(layers[0].end, CGPoint(x: 300, y: 260), "viaKey=\(viaKey): the drag after the picks did not go on")
            XCTAssertEqual(layers[1].style, AnnotationStyle(color: .blue, thickness: .thick, filled: true),
                           "viaKey=\(viaKey): the next object did not take the picks")
        }
    }

    func testAButtonPressedWhileEscsQuestionStandsWithdrawsIt() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        stroke(first)
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "Esc with layers closed at once: \(results)")
        overlay?.bars.perform(.color(.green))
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "the button did not withdraw the question: \(results)")
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    // MARK: a bar and a key

    func testEveryToolIsOnABarAndOnAKeyAndTheTwoAgree() throws {
        let codes: [AnnotationTool: UInt16] = [.arrow: 0, .rectangle: 15, .ellipse: 31, .line: 37, .pencil: 35, .highlighter: 4]
        XCTAssertEqual(Set(codes.keys), Set(AnnotationTool.allCases), "a tool has no key in this test: the bar has a button for it")
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(EditorKeys.action(keyCode: codes[tool]!, flags: []), .tool(tool), "\(tool): the key means another tool")
            var drawn: [AnnotationTool] = []
            for viaKey in [true, false] {
                let (first, _) = try build()
                select(first)
                if viaKey { overlay?.keyDown(key(codes[tool]!)) } else { overlay?.bars.perform(.tool(tool)) }
                XCTAssertEqual(overlay?.bars.tool, tool, "\(tool) viaKey=\(viaKey): the bars do not show the tool")
                stroke(first)
                overlay?.perform(.exit(.confirm))
                drawn += try XCTUnwrap(edited()).layers.map(\.tool)
            }
            XCTAssertEqual(drawn, [tool, tool], "\(tool): the key and the button drew different things")
        }
    }

    func testTheSameToolAgainPutsItDownByKeyAndByButton() throws {
        for viaKey in [true, false] {
            let (first, _) = try build()
            select(first)
            for _ in 0..<2 { if viaKey { overlay?.keyDown(key(35)) } else { overlay?.bars.perform(.tool(.pencil)) } }
            XCTAssertNil(overlay?.bars.tool, "viaKey=\(viaKey): the second press did not put the pencil down")
        }
    }

    func testTheActionRowAndTheExitKeysLeaveTheSameWay() throws {
        for (action, code, flags, how) in [(EditorAction.exit(.copy), UInt16(8), NSEvent.ModifierFlags.command, EditorExit.copy),
                                           (.exit(.save), 1, .command, .save)] {
            for viaKey in [true, false] {
                let (first, _) = try build()
                select(first)
                stroke(first, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
                if viaKey { overlay?.keyDown(key(code, flags: flags)) } else { overlay?.bars.perform(action) }
                XCTAssertEqual(try XCTUnwrap(edited()).exit, how, "viaKey=\(viaKey)")
            }
        }
    }

    func testCloseIsEscsRuleAskingFirstWhenThereIsSomethingToLose() throws {
        let (first, _) = try build()
        select(first)
        overlay?.bars.perform(.close)
        XCTAssertEqual(results.count, 1)
        guard case .cancelled? = results.first else { return XCTFail("\(results)") }

        let (again, _) = try build()
        select(again)
        overlay?.perform(.tool(.pencil))
        stroke(again)
        overlay?.bars.perform(.close)
        XCTAssertTrue(results.isEmpty, "Close threw the work away without asking: \(results)")
        overlay?.bars.perform(.close)
        guard case .cancelled? = results.first else { return XCTFail("the second Close did not close: \(results)") }
    }

    func testUndoAndRedoOnTheBarAreTheKeysAndTheirButtonsKnowWhenTheyCannot() throws {
        let (first, _) = try build()
        select(first)
        XCTAssertFalse(overlay?.bars.canUndo ?? true)
        overlay?.perform(.tool(.line))
        stroke(first)
        XCTAssertTrue(overlay?.bars.canUndo ?? false)
        XCTAssertFalse(overlay?.bars.canRedo ?? true)
        overlay?.bars.perform(.undo)
        XCTAssertFalse(overlay?.bars.canUndo ?? true)
        XCTAssertTrue(overlay?.bars.canRedo ?? false)
        overlay?.keyDown(key(6, flags: [.command, .shift]))
        XCTAssertTrue(overlay?.bars.canUndo ?? false, "⇧⌘Z did not redo what the button undid")
    }

    // MARK: what was picked

    func testAPickedColourThicknessAndFillAreTheNextObjectsAndNotTheEarlierOnes() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.rectangle))
        stroke(first, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 200, y: 200))
        overlay?.bars.perform(.color(.blue))
        overlay?.bars.perform(.thickness(.thick))
        overlay?.bars.perform(.toggleFill)
        stroke(first, from: CGPoint(x: 220, y: 120), to: CGPoint(x: 300, y: 200))
        overlay?.perform(.exit(.confirm))
        let layers = try XCTUnwrap(edited()).layers
        XCTAssertEqual(layers.map(\.style), [.standard, AnnotationStyle(color: .blue, thickness: .thick, filled: true)],
                       "the pick reached the earlier object, or not the next one")
        XCTAssertTrue(layers[1].isFilled)
        XCTAssertEqual(layers[1].fillColor, AnnotationColor.blue.cgColor)
    }

    func testTheLitSwatchIsThePickedColourOrTheToolsOwn() throws {
        let (first, _) = try build()
        select(first)
        XCTAssertEqual(overlay?.bars.lit, .red)
        overlay?.perform(.tool(.highlighter))
        XCTAssertEqual(overlay?.bars.lit, .yellow, "the marker's own colour is not the one shown lit")
        overlay?.bars.perform(.color(.green))
        XCTAssertEqual(overlay?.bars.lit, .green)
        overlay?.perform(.tool(.highlighter))
        XCTAssertEqual(overlay?.bars.lit, .green)
    }

    func testFillMeansSomethingOnlyForTheBoxes() throws {
        let (first, _) = try build()
        select(first)
        for tool in AnnotationTool.allCases {
            overlay?.perform(.tool(tool))
            XCTAssertEqual(overlay?.bars.fillApplies, tool == .rectangle || tool == .ellipse, "\(tool)")
            overlay?.perform(.tool(tool))
        }
    }

    // MARK: what is remembered

    func testTheLastPicksComeBackInTheNextCaptureAndNothingIsReadBeforeTheRelease() throws {
        let kept = memory()
        let (first, _) = try build(store: kept)
        XCTAssertNil(kept.object(ScreenshotsSettings.Key.editorTool), "something was written before anything was picked")
        select(first)
        overlay?.perform(.tool(.ellipse))
        overlay?.bars.perform(.color(.purple))
        overlay?.bars.perform(.thickness(.medium))
        overlay?.bars.perform(.toggleFill)
        overlay?.close()

        let (next, _) = try build(store: kept)
        // The store is read when the area is released, not when the overlay is made.
        EditorMemory.remember(tool: .line, in: kept)
        EditorMemory.remember(style: AnnotationStyle(color: .orange, thickness: .thick, filled: false), in: kept)
        select(next)
        XCTAssertEqual(overlay?.bars.tool, .line, "the tool was read before the release")
        XCTAssertEqual(overlay?.bars.style, AnnotationStyle(color: .orange, thickness: .thick, filled: false))
        stroke(next)
        overlay?.perform(.exit(.confirm))
        let layer = try XCTUnwrap(edited()).layers.first
        XCTAssertEqual(layer?.tool, .line, "the remembered tool did not draw on the first stroke")
        XCTAssertEqual(layer?.style.color, .orange)
    }

    func testWhatWasPickedInOneCaptureIsWhatTheNextOpensWith() throws {
        let kept = memory()
        let (first, _) = try build(store: kept)
        select(first)
        overlay?.perform(.tool(.ellipse))
        overlay?.bars.perform(.color(.purple))
        overlay?.bars.perform(.thickness(.medium))
        overlay?.bars.perform(.toggleFill)
        overlay?.close()

        let (next, _) = try build(store: kept)
        select(next)
        XCTAssertEqual(overlay?.bars.tool, .ellipse)
        XCTAssertEqual(overlay?.bars.style, AnnotationStyle(color: .purple, thickness: .medium, filled: true))
    }

    func testAStoreThatSaysAnythingOpensTheEditorOnTheNearestThingItHas() throws {
        let kept = memory()
        kept.set(Int.max, for: ScreenshotsSettings.Key.editorThickness)
        kept.set("magenta", for: ScreenshotsSettings.Key.editorColor)
        kept.set("laser", for: ScreenshotsSettings.Key.editorTool)
        let (first, _) = try build(store: kept)
        select(first)
        XCTAssertEqual(overlay?.bars.style.thickness, .thick)
        XCTAssertNil(overlay?.bars.style.color)
        XCTAssertNil(overlay?.bars.tool)
    }

    func testAnOverlayWithNoStoreRemembersNothingAndOpensOnTheStandardEditor() throws {
        let (first, _) = try build()
        select(first)
        XCTAssertNil(overlay?.bars.tool)
        XCTAssertEqual(overlay?.bars.style, .standard)
    }

    // MARK: names

    func testEveryNameOnTheBarsIsThereAndDistinctInEveryLanguage() {
        AppLanguage.each { language in
            let groups: [(String, [String])] = [
                ("tools", AnnotationTool.allCases.map(ScStr.tool)),
                ("colours", AnnotationColor.allCases.map(ScStr.ink)),
                ("thicknesses", AnnotationThickness.allCases.map(ScStr.thickness)),
                ("the rest", [ScStr.fill, ScStr.undo, ScStr.redo, ScStr.copy, ScStr.save, ScStr.closeEditor]),
            ]
            for (name, words) in groups {
                XCTAssertFalse(words.contains(where: \.isEmpty), "\(language) \(name)")
                XCTAssertEqual(Set(words).count, words.count, "\(language): two controls share a name among \(name): \(words)")
            }
            XCTAssertEqual(Set(groups.flatMap(\.1)).count, groups.flatMap(\.1).count, "\(language): two controls on the bars share a name")
        }
    }

    func testEveryButtonOnTheBarsIsNamedWhereItIsDeclared() throws {
        let lines = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorBars.swift").components(separatedBy: "\n")
        var seen = 0
        for (index, line) in lines.enumerated() {
            let body = line.trimmingCharacters(in: .whitespaces)
            guard body.contains("Button(action:") || body.contains("Button {") else { continue }
            seen += 1
            let after = lines.dropFirst(index + 1).prefix(14).joined(separator: "\n")
            XCTAssertTrue(after.contains(".accessibilityLabel("), "the button at line \(index + 1) of EditorBars.swift has no accessibility label")
        }
        XCTAssertGreaterThanOrEqual(seen, 4, "the scan found \(seen) buttons: cell, swatch, thickness and the row's are four")
    }
}
