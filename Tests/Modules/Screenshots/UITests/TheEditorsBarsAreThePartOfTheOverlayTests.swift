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

/// **The palette is part of the overlay:** it stands on the display
/// being edited and nowhere else, inside it in every language, it goes while an object is
/// drawn and comes back on the release, a press on it starts no object and selects no new
/// area, a cell and a key are one meaning, and what was picked is the next object's and the
/// next capture's. The panels are built and never ordered in; each test asserts that the
/// overlay finished before it asserts what it finished with.
///
/// The class keeps its name because the stage's acceptance filter in the owner's plan names it; it renames with the plan.
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

    func testThePaletteStandsInsideTheEditedDisplayAndOnNoOtherInEveryLanguage() throws {
        let selections = [area, CGRect(x: 940, y: 740, width: 60, height: 60), CGRect(x: 0, y: 0, width: 1000, height: 800),
                          CGRect(x: 5, y: 700, width: 12, height: 12)]
        AppLanguage.each { current in
            let language = "\(current)"
            do { for selection in selections {
                let (first, others) = try build()
                select(first, selection)
                let chrome = try XCTUnwrap(overlay?.chrome(on: first), "\(language) \(selection): no palette on the edited display")
                let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
                XCTAssertTrue(bounds.contains(chrome.palette), "\(language) \(selection): the palette \(chrome.palette) is off the display")
                XCTAssertTrue((300...700).contains(chrome.palette.width) && abs(chrome.palette.height - EditorPalette.height) < 1,
                              "\(language): the palette measured \(chrome.palette.size)")
                XCTAssertTrue(try XCTUnwrap(overlay?.view(for: first)).paletteIsShown, "\(language): the palette is not on screen")
                for other in others {
                    XCTAssertNil(overlay?.chrome(on: other), "\(language): the palette on a display that is not the edited one")
                    XCTAssertFalse(try XCTUnwrap(overlay?.view(for: other)).paletteIsShown)
                }
            } } catch { XCTFail("\(language): \(error)") }
        }
    }

    func testNoPaletteBeforeAnAreaExistsOrWhileANewOneIsDragged() throws {
        let (first, _) = try build()
        XCTAssertNil(overlay?.chrome(on: first))
        overlay?.mouseDown(on: first, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: first, at: CGPoint(x: 300, y: 300), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "the palette over a selection still being dragged")
        overlay?.mouseUp(on: first)
        XCTAssertNotNil(overlay?.chrome(on: first))
    }

    // MARK: while an object is drawn

    func testThePaletteGoesWhileAnObjectIsDrawnAndIsBackOnTheRelease() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.rectangle))
        let view = try XCTUnwrap(overlay?.view(for: first))
        XCTAssertTrue(view.paletteIsShown)
        overlay?.mouseDown(on: first, at: CGPoint(x: 150, y: 150), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "the palette stayed up under a press")
        XCTAssertFalse(view.paletteIsShown)
        overlay?.mouseDragged(on: first, at: CGPoint(x: 400, y: 350), flags: [])
        XCTAssertNil(overlay?.chrome(on: first), "the palette stayed up under the drag")
        XCTAssertFalse(view.paletteIsShown)
        XCTAssertEqual(view.drawnShapes.count, 1, "nothing was being drawn, so the test saw nothing")
        overlay?.mouseUp(on: first)
        XCTAssertNotNil(overlay?.chrome(on: first), "the palette did not come back on the release")
        XCTAssertTrue(view.paletteIsShown)
    }

    // MARK: a click on the palette

    func testAPressOnThePaletteStartsNoObjectAndSelectsNoNewArea() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        let view = try XCTUnwrap(overlay?.view(for: first))
        let palette = chrome.palette
        XCTAssertTrue(view.isPalette(view.clickTarget(at: centre(palette))), "a click in the middle of the palette reaches the picture")
        // The gap between two cells is on the palette and not on the picture either.
        overlay?.mouseDown(on: first, at: CGPoint(x: palette.minX + 1, y: palette.minY + 1), flags: [])
        overlay?.mouseDragged(on: first, at: CGPoint(x: palette.minX + 30, y: palette.minY + 30), flags: [])
        overlay?.mouseUp(on: first)
        XCTAssertEqual(view.drawnShapes.count, 0, "a press on the palette drew something")
        overlay?.perform(.exit(.confirm))
        let done = try XCTUnwrap(edited())
        XCTAssertTrue(done.layers.isEmpty, "a press on the palette became a layer: \(done.layers)")
        XCTAssertEqual(done.local, area, "a press on the palette moved the area")
    }

    func testThePictureBesideThePaletteStillDrawsSoTheTestAboveCanSeeADraft() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        stroke(first)
        overlay?.perform(.exit(.confirm))
        XCTAssertEqual(try XCTUnwrap(edited()).layers.count, 1)
    }

    func testAPressOnThePalettesBackgroundWithdrawsEscsQuestion() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.pencil))
        stroke(first)
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "Esc with layers closed at once: \(results)")
        // The corner of the palette is background, not a button.
        overlay?.mouseDown(on: first, at: CGPoint(x: chrome.palette.minX + 1, y: chrome.palette.minY + 1), flags: [])
        overlay?.mouseUp(on: first)
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "the press on the palette did not withdraw the question: \(results)")
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    func testAPressOnThePaletteWithNoToolDoesNotReplaceTheArea() throws {
        let (first, _) = try build()
        select(first)
        let chrome = try XCTUnwrap(overlay?.chrome(on: first))
        // No tool, no layers: a press elsewhere starts a new area; a press on the palette must not.
        overlay?.mouseDown(on: first, at: centre(chrome.palette), flags: [])
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
                overlay?.palette.perform(.tool(.ellipse))
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
        overlay?.palette.perform(.color(.green))
        overlay?.keyDown(key(53))
        XCTAssertTrue(results.isEmpty, "the button did not withdraw the question: \(results)")
        overlay?.keyDown(key(53))
        guard case .cancelled? = results.first, results.count == 1 else { return XCTFail("\(results)") }
    }

    // MARK: the palette and a key

    func testEveryToolIsOnThePaletteAndOnAKeyAndTheTwoAgree() throws {
        let codes: [AnnotationTool: UInt16] = [.arrow: 0, .rectangle: 15, .ellipse: 31, .line: 37, .pencil: 35, .highlighter: 4, .pen: 45]
        XCTAssertEqual(Set(codes.keys), Set(AnnotationTool.allCases), "a tool has no key in this test: the palette has a cell for it")
        for tool in AnnotationTool.allCases {
            XCTAssertEqual(EditorKeys.action(keyCode: codes[tool]!, flags: []), .tool(tool), "\(tool): the key means another tool")
            var drawn: [AnnotationTool] = []
            for viaKey in [true, false] {
                let (first, _) = try build()
                select(first)
                if viaKey { overlay?.keyDown(key(codes[tool]!)) } else { overlay?.palette.perform(.tool(tool)) }
                XCTAssertEqual(overlay?.palette.tool, tool, "\(tool) viaKey=\(viaKey): the palette does not show the tool")
                stroke(first)
                overlay?.perform(.exit(.confirm))
                drawn += try XCTUnwrap(edited()).layers.map(\.tool)
            }
            XCTAssertEqual(drawn, [tool, tool], "\(tool): the key and the button drew different things")
        }
    }

    /// N is the pen and P is still the pencil: two keys, two tools, by physical code (N is 45, P is 35).
    func testNIsThePenAndPIsStillThePencilAndThePenStandsBeforeTheMarkerInTheRow() {
        XCTAssertEqual(EditorKeys.action(keyCode: 45, flags: []), .tool(.pen))
        XCTAssertEqual(EditorKeys.action(keyCode: 35, flags: []), .tool(.pencil))
        XCTAssertNil(EditorKeys.action(keyCode: 45, flags: .command), "⌘N picked the pen")
        XCTAssertNil(EditorKeys.action(keyCode: 45, flags: [.control]), "⌃N picked the pen")
        XCTAssertEqual(EditorKeys.action(keyCode: 45, flags: .capsLock), .tool(.pen), "Caps Lock read as a chord")
        XCTAssertEqual(EditorPalette.objects.filter { $0.place == .row }.map(\.tool), [.pen, .highlighter, .pencil],
                       "the row is not Pen, Marker, Pencil")
        XCTAssertEqual(Set(EditorPalette.objects.map(\.tool)), Set(AnnotationTool.allCases), "a tool has no cell")
    }

    func testTheSameToolAgainPutsItDownByKeyAndByButton() throws {
        for viaKey in [true, false] {
            let (first, _) = try build()
            select(first)
            for _ in 0..<2 { if viaKey { overlay?.keyDown(key(35)) } else { overlay?.palette.perform(.tool(.pencil)) } }
            XCTAssertNil(overlay?.palette.tool, "viaKey=\(viaKey): the second press did not put the pencil down")
        }
    }

    func testTheActionRowAndTheExitKeysLeaveTheSameWay() throws {
        for (action, code, flags, how) in [(EditorAction.exit(.copy), UInt16(8), NSEvent.ModifierFlags.command, EditorExit.copy),
                                           (.exit(.save), 1, .command, .save)] {
            for viaKey in [true, false] {
                let (first, _) = try build()
                select(first)
                stroke(first, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250))
                if viaKey { overlay?.keyDown(key(code, flags: flags)) } else { overlay?.palette.perform(action) }
                XCTAssertEqual(try XCTUnwrap(edited()).exit, how, "viaKey=\(viaKey)")
            }
        }
    }

    func testCloseIsEscsRuleAskingFirstWhenThereIsSomethingToLose() throws {
        let (first, _) = try build()
        select(first)
        overlay?.palette.perform(.close)
        XCTAssertEqual(results.count, 1)
        guard case .cancelled? = results.first else { return XCTFail("\(results)") }

        let (again, _) = try build()
        select(again)
        overlay?.perform(.tool(.pencil))
        stroke(again)
        overlay?.palette.perform(.close)
        XCTAssertTrue(results.isEmpty, "Close threw the work away without asking: \(results)")
        overlay?.palette.perform(.close)
        guard case .cancelled? = results.first else { return XCTFail("the second Close did not close: \(results)") }
    }

    func testUndoAndRedoOnThePaletteAreTheKeysAndTheirCellsKnowWhenTheyCannot() throws {
        let (first, _) = try build()
        select(first)
        XCTAssertFalse(overlay?.palette.canUndo ?? true)
        overlay?.perform(.tool(.line))
        stroke(first)
        XCTAssertTrue(overlay?.palette.canUndo ?? false)
        XCTAssertFalse(overlay?.palette.canRedo ?? true)
        overlay?.palette.perform(.undo)
        XCTAssertFalse(overlay?.palette.canUndo ?? true)
        XCTAssertTrue(overlay?.palette.canRedo ?? false)
        overlay?.keyDown(key(6, flags: [.command, .shift]))
        XCTAssertTrue(overlay?.palette.canUndo ?? false, "⇧⌘Z did not redo what the button undid")
    }

    // MARK: what was picked

    func testAPickedColourThicknessAndFillAreTheNextObjectsAndNotTheEarlierOnes() throws {
        let (first, _) = try build()
        select(first)
        overlay?.perform(.tool(.rectangle))
        stroke(first, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 200, y: 200))
        overlay?.palette.perform(.color(.blue))
        overlay?.palette.perform(.thickness(.thick))
        overlay?.palette.perform(.toggleFill)
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
        XCTAssertEqual(overlay?.palette.lit, .red)
        overlay?.perform(.tool(.highlighter))
        XCTAssertEqual(overlay?.palette.lit, .yellow, "the marker's own colour is not the one shown lit")
        overlay?.palette.perform(.color(.green))
        XCTAssertEqual(overlay?.palette.lit, .green)
        overlay?.perform(.tool(.highlighter))
        XCTAssertEqual(overlay?.palette.lit, .green)
    }

    func testFillMeansSomethingOnlyForTheBoxes() throws {
        let (first, _) = try build()
        select(first)
        for tool in AnnotationTool.allCases {
            overlay?.perform(.tool(tool))
            XCTAssertEqual(overlay?.palette.fillApplies, tool == .rectangle || tool == .ellipse, "\(tool)")
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
        overlay?.palette.perform(.color(.purple))
        overlay?.palette.perform(.thickness(.medium))
        overlay?.palette.perform(.toggleFill)
        overlay?.close()

        let (next, _) = try build(store: kept)
        // The store is read when the area is released, not when the overlay is made.
        EditorMemory.remember(tool: .line, in: kept)
        EditorMemory.remember(style: AnnotationStyle(color: .orange, thickness: .thick, filled: false), for: .line, in: kept)
        select(next)
        XCTAssertEqual(overlay?.palette.tool, .line, "the tool was read before the release")
        XCTAssertEqual(overlay?.palette.style, AnnotationStyle(color: .orange, thickness: .thick, filled: false))
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
        overlay?.palette.perform(.color(.purple))
        overlay?.palette.perform(.thickness(.medium))
        overlay?.palette.perform(.toggleFill)
        overlay?.close()

        let (next, _) = try build(store: kept)
        select(next)
        XCTAssertEqual(overlay?.palette.tool, .ellipse)
        XCTAssertEqual(overlay?.palette.style, AnnotationStyle(color: .purple, thickness: .medium, filled: true))
    }

    func testAStoreThatSaysAnythingOpensTheEditorOnTheNearestThingItHas() throws {
        let kept = memory()
        kept.set(["pen": Int.max], for: ScreenshotsSettings.Key.editorThicknessByTool)
        kept.set("magenta", for: ScreenshotsSettings.Key.editorColor)
        kept.set("laser", for: ScreenshotsSettings.Key.editorTool)
        let (first, _) = try build(store: kept)
        select(first)
        XCTAssertEqual(overlay?.palette.style.thickness, .thick)
        XCTAssertNil(overlay?.palette.style.color)
        XCTAssertNil(overlay?.palette.tool)
    }

    func testAnOverlayWithNoStoreRemembersNothingAndOpensOnTheStandardEditor() throws {
        let (first, _) = try build()
        select(first)
        XCTAssertNil(overlay?.palette.tool)
        XCTAssertEqual(overlay?.palette.style, .standard)
    }

    // MARK: names

    /// The names the palette's controls carry, in the language in force: the row's tools from the list the row is drawn
    /// from, every ink, and the fixed cells. `testThePaletteDeclaresNoNameThisListDoesNotKnow` ties the fixed part to
    /// the file, so a cell added there without a name here fails and the list cannot drift from the palette.
    private var paletteNames: [(group: String, words: [String])] {
        [
            ("row tools", EditorPalette.objects.filter { $0.place == .row }.map { ScStr.tool($0.tool) }),
            ("inks", AnnotationColor.allCases.map(ScStr.ink) + [ScStr.allColours]),
            ("fixed cells", [ScStr.undo, ScStr.redo, HelmA11y.moreActions, ScStr.done, ScStr.closeEditor]),
        ]
    }

    func testEveryControlOnThePaletteIsNamedAndDistinctInEveryLanguage() {
        AppLanguage.each { language in
            let groups = paletteNames
            XCTAssertEqual(groups[0].words.count, 3, "\(language): the row is Pen, Marker and Pencil")
            for (name, words) in groups {
                XCTAssertFalse(words.contains(where: \.isEmpty), "\(language) \(name)")
                XCTAssertEqual(Set(words).count, words.count, "\(language): two controls share a name among \(name): \(words)")
            }
            let all = groups.flatMap(\.words)
            XCTAssertEqual(Set(all).count, all.count, "\(language): two controls on the palette share a name: \(all)")
        }
    }

    func testThePaletteDeclaresNoNameThisListDoesNotKnow() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift")
        let tokens = Set(try NSRegularExpression(pattern: #"(?:ScStr|HelmA11y)\.[A-Za-z]+"#)
            .matches(in: source, range: NSRange(source.startIndex..., in: source))
            .map { String(source[Range($0.range, in: source)!]) })
        // `select` is the label that shows the chosen tool, not a control.
        let known: Set<String> = ["ScStr.tool", "ScStr.ink", "ScStr.allColours", "ScStr.undo", "ScStr.redo", "HelmA11y.moreActions",
                                  "ScStr.done", "ScStr.closeEditor", "ScStr.select"]
        XCTAssertEqual(tokens, known, "the palette names a control this test does not list, or lists one the palette lost")
    }

    /// The ⋯ menu's items are read from `EditorMenu.items` (Pin included, offered or not), the pop-over's two rows from
    /// the file that declares them.
    func testEveryWordTheMenuAndThePopoversShowIsThereAndDistinctInEveryLanguage() throws {
        let popover = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPopover.swift")
        XCTAssertTrue(popover.contains("ScStr.thicknessLabel") && popover.contains("ScStr.opacityLabel"), "the pop-over lost a row this test names")
        AppLanguage.each { language in
            func titles(_ items: [EditorMenuItem]) -> [String] {
                items.flatMap { item -> [String] in
                    switch item {
                    case .tool(let title, _, _, _), .action(let title, _, _, _): [title]
                    case .submenu(let title, _, let children): [title] + titles(children)
                    case .separator: []
                    }
                }
            }
            let menu = titles(EditorMenu.items(for: EditorBarModel(), pinOffered: true))
            XCTAssertEqual(menu.count, 11, "\(language): Arrow, Shapes, Rectangle, Oval, Line, Filled, Select, Thickness and Opacity, Save, Pin, Share: \(menu)")
            let words = menu + [ScStr.thicknessLabel, ScStr.opacityLabel]
            XCTAssertFalse(words.contains(where: \.isEmpty), "\(language): \(words)")
            XCTAssertEqual(Set(words).count, words.count, "\(language): two words share a name in the menu and pop-overs: \(words)")
        }
    }

    func testEveryButtonOnThePaletteIsNamedWhereItIsDeclared() throws {
        var seen = 0
        // The cells are `GlassCell`, which cannot be built without a name; the swatch is the palette's own button.
        for file in ["EditorPalette.swift", "GlassCell.swift"] {
            let lines = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/\(file)").components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let body = line.trimmingCharacters(in: .whitespaces)
                guard body.contains("Button(action:") || body.contains("Button {") else { continue }
                seen += 1
                let after = lines.dropFirst(index + 1).prefix(14).joined(separator: "\n")
                XCTAssertTrue(after.contains(".accessibilityLabel("), "the button at line \(index + 1) of \(file) has no accessibility label")
            }
        }
        XCTAssertGreaterThanOrEqual(seen, 2, "the scan found \(seen) buttons: the cell and the swatch are two")
    }
}
