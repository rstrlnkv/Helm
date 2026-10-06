import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The colour wheel is a control named «All Colours»: it opens a pop-over of all eight inks under it, a pick sets the
/// colour of the tool in hand and closes it, and a colour the grid has no swatch for shows in the wheel's centre.**
///
/// `Architecture/Screenshots.md`, the colour grid and wheel: the grid holds red, yellow, blue, green, black; orange,
/// purple and white are only in the pop-over, and when one of them (or any other colour outside the grid, which the pop-over's wheel test below draws) is the colour it is seen in the centre of the wheel's cell, with no ring
/// on any of the five grid swatches. No frame in `palette-frames/` draws the colours pop-over, so its order is derived:
/// the spectrum `AnnotationColor` already lists (red, orange, yellow, green, blue, purple, black, white); the grid's
/// reading order is the other candidate and is not pinned here. The pop-over's third row (the system's panel and the eyedropper) is
/// pressed in `testEachSwatchOfThePopoverSendsItsInkAndTheViewDrawsThemInTheDeclaredOrder` only as far as what it sends; the panel and the
/// eyedropper themselves are in `TheAllColoursPanelIsAskedAndSentAwayTests` and `ThePipettePicksTheFrozenPixelNotTheLayersTests`.
@MainActor
final class TheColourWheelOpensTheEightInksTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        AppLanguage.override = nil
        super.tearDown()
    }

    static let spectrum: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    static let grid: [AnnotationColor] = [.red, .yellow, .blue, .green, .black]
    static let apart: [AnnotationColor] = [.orange, .purple, .white]

    private func build(store: NamespacedStore? = nil, area: CGRect = CGRect(x: 300, y: 100, width: 400, height: 300))
        throws -> (DisplayID, OverlayView) {
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        overlay = built
        let id = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: id, at: area.origin, flags: [])
        built.mouseDragged(on: id, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        built.mouseUp(on: id)
        return (id, try XCTUnwrap(built.view(for: id)))
    }

    private func esc() -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    }

    /// Presses the wheel's cell, once the palette's layout has reported it; its centre along the palette.
    private func openColours(_ overlay: CaptureOverlay) throws -> CGFloat {
        for _ in 0..<20 where overlay.palette.wheelFrame == .zero { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let wheel = overlay.palette.wheelFrame
        XCTAssertGreaterThan(wheel.width, 20, "control: the palette reported the wheel's cell (\(wheel))")
        overlay.perform(.colours(anchorX: wheel.midX))
        return wheel.midX
    }

    /// An offscreen window, ordered in so SwiftUI takes a press, and a press at `points` (top-left) in it.
    private func press(_ mount: MountedRender, at points: [CGPoint], _ each: (CGPoint) -> Void = { _ in }) throws {
        let window = try XCTUnwrap(mount.window)
        window.alphaValue = 0
        window.ignoresMouseEvents = false
        window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        for point in points {
            each(point)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: type, location: CGPoint(x: point.x, y: mount.host.bounds.height - point.y), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
        }
    }

    // MARK: the pop-over's eight

    func testThePopoverHoldsTheEightInksInTheSpectrumOrder() {
        XCTAssertEqual(EditorColoursPopover.inks, Self.spectrum, "eight, each once, in the derived order")
        XCTAssertEqual(Set(EditorColoursPopover.inks), Set(AnnotationColor.allCases), "control: every ink there is")
    }

    /// What the view sends, read from presses on it: the eight swatches, each a `.color`, drawn in the declared order.
    func testEachSwatchOfThePopoverSendsItsInkAndTheViewDrawsThemInTheDeclaredOrder() throws {
        AppLanguage.override = .en
        let model = EditorBarModel()
        model.show(tool: .pen, style: .standard, canUndo: false, canRedo: false)
        var at = CGPoint.zero
        var first: [AnnotationInk: CGPoint] = [:]
        var odd: [EditorAction] = []
        model.perform = {
            if case .color(let ink) = $0 { if first[ink] == nil { first[ink] = at } } else { odd.append($0) }
        }
        let probe = NSHostingView(rootView: EditorColoursPopover(model: model))
        probe.sizingOptions = [.intrinsicContentSize]
        let size = probe.fittingSize
        XCTAssertGreaterThan(size.width, 60, "control: the pop-over has a body")
        let mount = MountedRender(EditorColoursPopover(model: model), width: size.width, height: size.height, appearance: .aqua)
        mount.settle(20)
        var points: [CGPoint] = []
        for y in stride(from: 2.0, to: size.height, by: 4) { for x in stride(from: 2.0, to: size.width, by: 4) { points.append(CGPoint(x: x, y: y)) } }
        try press(mount, at: points) { at = $0 }
        // The third row's two cells are the wheel and the eyedropper, and nothing else is not a pick.
        XCTAssertTrue(odd.contains(.allColours) && odd.contains(.eyedropper), "the third row's cells cannot be pressed: \(odd)")
        XCTAssertTrue(odd.allSatisfy { $0 == .allColours || $0 == .eyedropper }, "the pop-over sent something other than a pick: \(odd)")
        XCTAssertEqual(Set(first.keys), Set(AnnotationColor.allCases.map(AnnotationInk.init)), "a swatch of the eight cannot be pressed: \(first.keys)")
        let drawn = first.keys.sorted { (first[$0]!.y, first[$0]!.x) < (first[$1]!.y, first[$1]!.x) }
        XCTAssertEqual(drawn, EditorColoursPopover.inks.map(AnnotationInk.init), "the pop-over draws the eight in another order than it declares")
    }

    // MARK: the wheel is a pressable control with a name

    private func palette(lit: AnnotationColor?, appearance: NSAppearance.Name = .aqua)
        throws -> (model: EditorBarModel, mount: MountedRender, rep: NSBitmapImageRep) {
        AppLanguage.override = .en
        let model = EditorBarModel()
        model.show(tool: .pen, style: AnnotationStyle(color: lit.map(AnnotationInk.init)), canUndo: false, canRedo: false)
        let probe = NSHostingView(rootView: EditorPalette(model: model))
        probe.sizingOptions = [.intrinsicContentSize]
        let size = probe.fittingSize
        let mount = MountedRender(EditorPalette(model: model), width: size.width, height: size.height, appearance: appearance)
        mount.settle(20)
        let rep = try XCTUnwrap(mount.host.bitmapImageRepForCachingDisplay(in: mount.host.bounds))
        mount.host.cacheDisplay(in: mount.host.bounds, to: rep)
        return (model, mount, rep)
    }

    func testPressingTheWheelSendsTheColoursAtItsCentre() throws {
        let (model, mount, _) = try palette(lit: nil)
        var sent: [EditorAction] = []
        model.perform = { sent.append($0) }
        let wheel = model.wheelFrame
        XCTAssertGreaterThan(wheel.width, 20, "the palette did not report the wheel's cell")
        try press(mount, at: [CGPoint(x: wheel.midX, y: wheel.midY)])
        XCTAssertEqual(sent.count, 1, "one press on the wheel sends one action, not \(sent)")
        guard case .colours(let anchor)? = sent.first else { return XCTFail("the wheel sent \(sent)") }
        XCTAssertEqual(anchor, wheel.midX, accuracy: 1.5, "the pop-over is centred on the wheel's cell")
    }

    /// That the name is translated is asked in `TheColourWheelsNameIsTranslatedTests`; here, only that no other cell shares it.
    func testTheWheelsNameIsNoneOfTheOtherCells() {
        var seen = 0
        AppLanguage.each { language in
            seen += 1
            let name = ScStr.allColours
            XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): the wheel has no name")
            let others = [ScStr.undo, ScStr.redo, ScStr.tool(.pen), ScStr.tool(.pencil), ScStr.tool(.highlighter), ScStr.done,
                          ScStr.closeEditor, HelmA11y.moreActions] + AnnotationColor.allCases.map { ScStr.ink($0) }
            XCTAssertFalse(others.contains(name), "\(language): another cell is named «\(name)»")
        }
        XCTAssertEqual(seen, 8)
    }

    /// The wheel was drawn `accessibilityHidden(true)` and dimmed to 0.4: a control with a press and no name for it is not that.
    func testTheWheelIsNeitherHiddenNorDimmedAndIsNamedFromTheShippingString() throws {
        let source = SwiftSource.code(try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorPalette.swift"))
        // The wheel view's own declaration, not the first `var wheel…` anywhere: where `wheelFrame` lives is nobody's business here.
        let after = try XCTUnwrap(source.components(separatedBy: "private var wheel: some View").dropFirst().first,
                                  "no `private var wheel: some View` in the palette")
        let body = String(after.prefix(1_800))
        XCTAssertTrue(body.contains("ScStr.allColours"), "the wheel's name is not `ScStr.allColours`")
        XCTAssertFalse(body.contains("accessibilityHidden(true)"), "still hidden from accessibility")
        XCTAssertFalse(body.contains(".opacity(0.4)"), "still drawn as the disabled cell")
    }

    // MARK: the wheel's centre

    private func pixel(_ rep: NSBitmapImageRep, _ point: CGPoint, in host: NSView) throws -> [CGFloat] {
        let scale = CGFloat(rep.pixelsWide) / host.bounds.width
        let colour = try XCTUnwrap(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB))
        return [colour.redComponent, colour.greenComponent, colour.blueComponent, colour.alphaComponent]
    }

    func testTheCentreShowsTheChosenInkWhenItIsOneOfTheThreeApart() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for ink in Self.apart {
                let (model, mount, rep) = try palette(lit: ink, appearance: appearance)
                let wheel = model.wheelFrame
                XCTAssertGreaterThan(wheel.width, 20, "the palette did not report the wheel's cell")
                let got = try pixel(rep, CGPoint(x: wheel.midX, y: wheel.midY), in: mount.host)
                // The honest reference: a plain disc of the same ink through the same mount and readback. The raw constant is
                // not it: the pipeline moves orange to (0.96, 0.66, 0.31) for a bare `Circle` too.
                let disc = MountedRender(Circle().fill(Color(cgColor: ink.cgColor)).frame(width: 24, height: 24),
                                         width: 24, height: 24, appearance: appearance)
                disc.settle(20)
                let discRep = try XCTUnwrap(disc.host.bitmapImageRepForCachingDisplay(in: disc.host.bounds))
                disc.host.cacheDisplay(in: disc.host.bounds, to: discRep)
                let want = try pixel(discRep, CGPoint(x: 12, y: 12), in: disc.host)
                XCTAssertGreaterThan(want[3], 0.9, "control: the reference disc is solid: \(want)")
                for (g, w) in zip(got, want) {
                    XCTAssertEqual(g, w, accuracy: 0.05, "\(ink) \(appearance.rawValue): read \(got), a plain disc reads \(want)")
                }
                // And it is not the bare wheel: the centre is the ink, whatever the angular gradient has there.
                let bare = try palette(lit: nil, appearance: appearance)
                let wheelOnly = try pixel(bare.rep, CGPoint(x: wheel.midX, y: wheel.midY), in: bare.mount.host)
                XCTAssertNotEqual(got, wheelOnly, "\(ink) \(appearance.rawValue): the centre did not change")
                XCTAssertGreaterThan(got[3], 0.9, "\(ink) \(appearance.rawValue): the centre is not solid: \(got)")
            }
        }
    }

    /// The pop-over's own wheel (its third row, first cell) shows a colour none of the eight is at its centre, and shows nothing of the
    /// kind for one of the eight. Read as the pixels that change between the two renderings, so nothing is assumed about where it sits.
    func testThePopoversWheelShowsACustomColourAtItsCentreAndNothingForTheEight() throws {
        AppLanguage.override = .en
        func render(_ ink: AnnotationInk?) throws -> (rep: NSBitmapImageRep, mount: MountedRender) {
            let model = EditorBarModel()
            model.show(tool: .pen, style: AnnotationStyle(color: ink), canUndo: false, canRedo: false)
            let probe = NSHostingView(rootView: EditorColoursPopover(model: model))
            probe.sizingOptions = [.intrinsicContentSize]
            let size = probe.fittingSize
            let mount = MountedRender(EditorColoursPopover(model: model), width: size.width, height: size.height, appearance: .aqua)
            mount.settle(20)
            let rep = try XCTUnwrap(mount.host.bitmapImageRepForCachingDisplay(in: mount.host.bounds))
            mount.host.cacheDisplay(in: mount.host.bounds, to: rep)
            return (rep, mount)
        }
        let custom = try XCTUnwrap(AnnotationInk(red: 0.2, green: 0.4, blue: 0.6))
        let none = try render(AnnotationInk(.red))
        let lit = try render(custom)
        XCTAssertEqual(none.rep.pixelsWide, lit.rep.pixelsWide, "control: the two renderings are the same size")
        // The reference: a plain disc of the ink through the same mount and readback.
        let disc = MountedRender(Circle().fill(Color(cgColor: custom.cgColor)).frame(width: 24, height: 24), width: 24, height: 24, appearance: .aqua)
        disc.settle(20)
        let discRep = try XCTUnwrap(disc.host.bitmapImageRepForCachingDisplay(in: disc.host.bounds))
        disc.host.cacheDisplay(in: disc.host.bounds, to: discRep)
        let want = try pixel(discRep, CGPoint(x: 12, y: 12), in: disc.host)
        func near(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return abs(c.redComponent - want[0]) + abs(c.greenComponent - want[1]) + abs(c.blueComponent - want[2]) < 0.08
        }
        // The pixels that are the ink's colour in the lit rendering and are not in the other: the disc at the wheel's centre.
        var patch: [(Int, Int)] = []
        for y in 0..<lit.rep.pixelsHigh { for x in 0..<lit.rep.pixelsWide where near(lit.rep, x, y) && !near(none.rep, x, y) { patch.append((x, y)) } }
        XCTAssertGreaterThan(patch.count, 30, "the pop-over's wheel shows no solid patch of a colour none of the eight is")
        // One of the eight lights its swatch and leaves the wheel's centre as it was.
        let orange = try render(AnnotationInk(.orange))
        for (x, y) in patch {
            let a = orange.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), b = none.rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            XCTAssertEqual(a?.redComponent ?? -1, b?.redComponent ?? -2, accuracy: 0.03, "one of the eight changed the pop-over's wheel at (\(x), \(y))")
            XCTAssertEqual(a?.blueComponent ?? -1, b?.blueComponent ?? -2, accuracy: 0.03, "one of the eight changed the pop-over's wheel at (\(x), \(y))")
        }
    }

    func testTheCentreShowsNothingForTheFiveAndIsTheSameForAllFive() throws {
        let reference = try palette(lit: nil)
        let wheel = reference.model.wheelFrame
        XCTAssertGreaterThan(wheel.width, 20, "the palette did not report the wheel's cell")
        let at = CGPoint(x: wheel.midX, y: wheel.midY)
        let bare = try pixel(reference.rep, at, in: reference.mount.host)
        for ink in Self.grid {
            let (_, mount, rep) = try palette(lit: ink)
            XCTAssertEqual(try pixel(rep, at, in: mount.host), bare, "\(ink) is on the grid: the wheel's centre must not change")
        }
        // The control: an ink that is not on the grid does change it, so «the same» above compared something.
        let (_, mount, rep) = try palette(lit: .orange)
        XCTAssertNotEqual(try pixel(rep, at, in: mount.host), bare, "control: orange changes the wheel's centre")
    }

    /// No ring on any of the five while the colour is one of the three: outside the wheel's cell the palette is the same
    /// drawing for orange, purple and white; a grid colour rings its swatch, so the comparison has something to see.
    func testNoGridSwatchIsRingedWhileTheColourIsOneOfTheThree() throws {
        // The grid's columns only: the tool objects' tips (x about 64) take the chosen ink by design, and are not a ring.
        // The grid is three cells across, the wheel the last of the second row; 5 pt more than that for a ring's reach.
        func outside(_ ink: AnnotationColor) throws -> [[CGFloat]] {
            let (model, mount, rep) = try palette(lit: ink)
            let wheel = model.wheelFrame.insetBy(dx: -4, dy: -4)
            XCTAssertGreaterThan(wheel.width, 28, "the palette did not report the wheel's cell")
            let left = model.wheelFrame.maxX - (3 * model.wheelFrame.width + 2 * HelmSpace.s4) - 5
            var read: [[CGFloat]] = []
            for y in stride(from: 0.0, to: mount.host.bounds.height, by: 1) {
                for x in stride(from: left.rounded(.down), to: mount.host.bounds.width, by: 1) where !wheel.contains(CGPoint(x: x, y: y)) {
                    read.append(try pixel(rep, CGPoint(x: x, y: y), in: mount.host))
                }
            }
            return read
        }
        let orange = try outside(.orange)
        XCTAssertGreaterThan(orange.count, 2_000, "control: the grid's columns were read")
        XCTAssertEqual(try outside(.purple), orange, "purple rings something outside the wheel")
        XCTAssertEqual(try outside(.white), orange, "white rings something outside the wheel")
        XCTAssertNotEqual(try outside(.red), orange, "control: a grid colour rings its swatch")
    }

    // MARK: the overlay

    func testTheWheelOpensTheColoursUnderThePaletteAtItsCellAndAnotherPressCloses() throws {
        let (id, _) = try build()
        let overlay = try XCTUnwrap(overlay)
        XCTAssertFalse(overlay.coloursAreOpen, "control: closed to begin with")
        let anchor = try openColours(overlay)
        XCTAssertTrue(overlay.coloursAreOpen)
        XCTAssertTrue(overlay.popoverIsOpen, "popoverIsOpen says either is open")
        XCTAssertFalse(overlay.thicknessIsOpen)
        let chrome = try XCTUnwrap(overlay.chrome(on: id))
        let popover = try XCTUnwrap(chrome.popover, "open, and the chrome has no rect for it")
        XCTAssertEqual(popover.minY, chrome.palette.maxY + 8, accuracy: 0.5, "stands under the palette, as the thickness one does")
        XCTAssertEqual(popover.midX, chrome.palette.minX + anchor, accuracy: 1.5, "centred on the wheel")
        XCTAssertTrue(chrome.covers(CGPoint(x: popover.midX, y: popover.midY)), "a press on the pop-over is not a press on the picture")
        overlay.perform(.colours(anchorX: anchor))
        XCTAssertFalse(overlay.coloursAreOpen, "the wheel pressed twice closes it")
    }

    func testTheColoursOpenAboveThePaletteWhereThereIsNoRoomBelow() throws {
        let (id, _) = try build(area: CGRect(x: 300, y: 20, width: 400, height: 760))
        let overlay = try XCTUnwrap(overlay)
        _ = try openColours(overlay)
        let chrome = try XCTUnwrap(overlay.chrome(on: id))
        let popover = try XCTUnwrap(chrome.popover)
        XCTAssertGreaterThan(chrome.palette.maxY + 8 + popover.height + 8, 800, "control: there is no room below the palette")
        XCTAssertLessThan(popover.maxY, chrome.palette.minY, "not above the palette")
        XCTAssertEqual(popover.maxY, chrome.palette.minY - 8, accuracy: 0.5, "above, with the palette's own gap")
        XCTAssertTrue(chrome.covers(CGPoint(x: popover.midX, y: popover.midY)))
    }

    /// With Select the grid's swatches still work: so does the wheel.
    func testTheWheelOpensWithNoToolChosenToo() throws {
        _ = try build()
        let overlay = try XCTUnwrap(overlay)
        _ = try openColours(overlay)
        XCTAssertTrue(overlay.coloursAreOpen, "no tool chosen: the thickness one has nothing to set, the colour does")
    }

    func testAPickSetsTheToolInHandsColourPersistsItAndClosesThePopover() throws {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        _ = try build(store: store)
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        _ = try openColours(overlay)
        overlay.perform(.color(.orange))
        XCTAssertFalse(overlay.coloursAreOpen, "a pick left the pop-over open")
        XCTAssertEqual(overlay.palette.style.color, .orange)
        XCTAssertEqual(EditorMemory.read(store).style(for: .pen).color, .orange, "the pick is in the store, `editorInkByTool`, for the next editor")
        overlay.perform(.tool(.highlighter))
        XCTAssertNil(overlay.palette.style.color, "the colour is the Pen's, not every tool's")
        _ = try openColours(overlay)
        overlay.perform(.color(.blue))
        XCTAssertFalse(overlay.coloursAreOpen)
        XCTAssertEqual(EditorMemory.read(store).style(for: .highlighter).color, .blue)
    }

    // MARK: one pop-over at a time

    func testOpeningTheColoursClosesThicknessAndTheReverse() throws {
        _ = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        XCTAssertTrue(overlay.thicknessIsOpen, "control: thickness open")
        _ = try openColours(overlay)
        XCTAssertTrue(overlay.coloursAreOpen)
        XCTAssertFalse(overlay.thicknessIsOpen, "two pop-overs at once")
        overlay.perform(.thicknessAndOpacity(anchorX: 300))
        XCTAssertTrue(overlay.thicknessIsOpen)
        XCTAssertFalse(overlay.coloursAreOpen, "two pop-overs at once, the other way")
        XCTAssertTrue(overlay.popoverIsOpen)
    }

    func testChoosingAToolClosesTheColours() throws {
        _ = try build()
        let overlay = try XCTUnwrap(overlay)
        _ = try openColours(overlay)
        overlay.perform(.tool(.pencil))
        XCTAssertFalse(overlay.coloursAreOpen, "the thickness pop-over closes on a tool; so does this one")
    }

    // MARK: Esc, right click, outside

    func testEscClosesTheColoursBeforeEscsOwnRule() throws {
        let (id, _) = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.rectangle))
        overlay.mouseDown(on: id, at: CGPoint(x: 350, y: 150), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 450, y: 250), flags: [])
        overlay.mouseUp(on: id)
        _ = try openColours(overlay)
        overlay.keyDown(esc())
        XCTAssertFalse(overlay.coloursAreOpen, "Esc left the colours open")
        XCTAssertTrue(results.isEmpty, "the Esc that closed the pop-over closed the editor")
        overlay.keyDown(esc())
        XCTAssertTrue(results.isEmpty, "the pop-over's Esc was also the rule's first press")
        overlay.keyDown(esc())
        XCTAssertEqual(results.count, 1, "the rule's own second press closes the editor")
    }

    func testTheRightClickClosesTheColours() throws {
        let (_, view) = try build()
        let overlay = try XCTUnwrap(overlay)
        _ = try openColours(overlay)
        view.rightMouseDown(with: NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        XCTAssertFalse(overlay.coloursAreOpen)
        XCTAssertTrue(results.isEmpty)
    }

    func testAClickOutsideClosesTheColoursAndDrawsNothingAndAClickOnItKeepsItOpen() throws {
        let (id, view) = try build()
        let overlay = try XCTUnwrap(overlay)
        overlay.perform(.tool(.pen))
        _ = try openColours(overlay)
        let popover = try XCTUnwrap(overlay.chrome(on: id)?.popover)
        overlay.mouseDown(on: id, at: CGPoint(x: popover.midX, y: popover.midY), flags: [])
        overlay.mouseUp(on: id)
        XCTAssertTrue(overlay.coloursAreOpen, "a press on the pop-over's own body closed it")
        XCTAssertEqual(view.drawnShapes.count, 0, "the press went through to the picture")
        overlay.mouseDown(on: id, at: CGPoint(x: 350, y: 200), flags: [])
        overlay.mouseDragged(on: id, at: CGPoint(x: 600, y: 230), flags: [])
        overlay.mouseUp(on: id)
        XCTAssertFalse(overlay.coloursAreOpen, "a click on the picture left it open")
        XCTAssertEqual(view.drawnShapes.count, 0, "the click that closed it also began a stroke")
        XCTAssertTrue(results.isEmpty)
    }
}
