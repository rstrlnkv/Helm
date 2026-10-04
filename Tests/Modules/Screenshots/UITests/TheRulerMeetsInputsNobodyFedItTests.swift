import AppKit
import CoreGraphics
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ruler in the overlay, fed what its first tests did not:** a press on the part of the strip the area does not show,
/// an area narrowed or redrawn under it, a turn gesture that never began or never ended, a ⌥ let go or pressed in the middle of
/// a drag, U in the middle of a stroke and of a drag by the strip, every exit with the ruler on the picture, the editor's memory
/// after a session with it, and the angle's text in each language.
///
/// What it would print if it failed totally: a ruler that reached the file fails `testEveryExitHandsOverTheLayersAloneWithTheRulerOn`
/// by the exit's name; one that reached the store fails the memory test by the key it wrote.
@MainActor
final class TheRulerMeetsInputsNobodyFedItTests: XCTestCase {
    private typealias Rig = (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)
    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []
    private let area = CGRect(x: 100, y: 100, width: 600, height: 400)

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func opened(area: CGRect? = nil, store: NamespacedStore? = nil) throws -> Rig {
        overlay?.close()
        results = []
        let rect = area ?? self.area
        let frames = try OverlayRig.frames(scale: 1)
        let built = CaptureOverlay(freeze: Freeze(displays: frames.map { .image($0) }, windows: []), store: store, pinRoom: { true }) { [weak self] in
            self?.results.append($0)
        }
        XCTAssertTrue(built.build())
        let display = try XCTUnwrap(frames.first?.id)
        built.mouseDown(on: display, at: rect.origin, flags: [])
        built.mouseDragged(on: display, at: CGPoint(x: rect.maxX, y: rect.maxY), flags: [])
        built.mouseUp(on: display)
        overlay = built
        return (built, display, try XCTUnwrap(built.view(for: display)))
    }

    private func drag(_ rig: Rig, _ points: [CGPoint], flags: [NSEvent.ModifierFlags]? = nil) {
        rig.overlay.mouseDown(on: rig.display, at: points[0], flags: flags?[0] ?? [])
        for (index, point) in points.dropFirst().enumerated() {
            rig.overlay.mouseDragged(on: rig.display, at: point, flags: flags.map { $0[min(index + 1, $0.count - 1)] } ?? [])
        }
        rig.overlay.mouseUp(on: rig.display)
    }

    // MARK: the strip and the area

    func testAPressOnThePartOfTheStripTheAreaDoesNotShowIsNotTheRulers() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        drag(rig, [CGPoint(x: 400, y: 300), CGPoint(x: 700, y: 300)])
        let strip = try XCTUnwrap(rig.overlay.rulerOnThePicture)
        XCTAssertEqual(strip.center.x, 700, "the fixture did not take the ruler to the area's right edge")
        // The strip reaches 150 pt past the area there; the layer is clipped to the area, so nothing is drawn at x 780.
        XCTAssertTrue(strip.contains(CGPoint(x: 780, y: 300)))
        rig.overlay.perform(.tool(.pen))
        drag(rig, [CGPoint(x: 780, y: 300), CGPoint(x: 790, y: 330)])
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, strip.center,
                       "a press the person could not see the strip at took it along: the ruler moved from \(strip.center)")
    }

    func testANarrowedAreaTakesTheCentreBackAndANewOneTheStripToItsMiddleLevel() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        drag(rig, [CGPoint(x: 400, y: 300), CGPoint(x: 520, y: 480)])
        drag(rig, [CGPoint(x: 520, y: 480), CGPoint(x: 520 + 80, y: 480 + 80)], flags: [[.option], [.option]])
        // The area's right edge is dragged in to x 200: the centre must come back inside.
        drag(rig, [CGPoint(x: 700, y: 300), CGPoint(x: 200, y: 300)])
        let strip = try XCTUnwrap(rig.overlay.rulerOnThePicture)
        XCTAssertTrue(strip.center.x <= 200 && strip.center.x >= 100, "the centre stayed outside the narrowed area: \(strip.center)")
        // Redrawn: no tool, no layers, a press outside the area and a new one released. The strip is level in the new middle, short enough.
        rig.overlay.perform(.select)
        let fresh = CGRect(x: 600, y: 600, width: 100, height: 60)
        drag(rig, [fresh.origin, CGPoint(x: fresh.maxX, y: fresh.maxY)])
        let again = try XCTUnwrap(rig.overlay.rulerOnThePicture)
        XCTAssertEqual(again.center, CGPoint(x: fresh.midX, y: fresh.midY))
        XCTAssertEqual(again.angle, 0)
        XCTAssertEqual(again.length, 80, accuracy: 1e-9)
    }

    func testAnAreaSmallerThanTheStripStillTakesTheRulerAwayWithU() throws {
        let tiny = CGRect(x: 300, y: 300, width: 20, height: 20)
        let rig = try opened(area: tiny)
        rig.overlay.perform(.toggleRuler)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.length ?? 0, 16, accuracy: 1e-9)
        rig.overlay.perform(.tool(.pen))
        drag(rig, [CGPoint(x: 302, y: 302), CGPoint(x: 318, y: 318)])
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "the strip over a 20 pt area took no press as its own")
        rig.overlay.perform(.toggleRuler)
        XCTAssertNil(rig.overlay.rulerOnThePicture)
        drag(rig, [CGPoint(x: 302, y: 302), CGPoint(x: 318, y: 312), CGPoint(x: 318, y: 318)])
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "with the ruler lowered a stroke in the small area was not drawn")
    }

    // MARK: the gestures

    func testAGestureThatEndsWithoutBeginningTurnsNothingAndOneThatNeverBeganStartsFromTheAngleItFinds() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        rig.overlay.rotateRuler(by: 30, phase: .ended)
        rig.overlay.rotateRuler(by: 30, phase: .cancelled)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle, 0, "an end with no begin turned the ruler")
        rig.overlay.rotateRuler(by: -30, phase: .changed)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle, 30)
        rig.overlay.rotateRuler(by: 0, phase: .ended)
        rig.overlay.rotateRuler(by: 10, phase: [])
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle ?? 0, 20, accuracy: 1e-9, "an event with no phase did not turn from the angle the ruler has")
    }

    func testANumberThatIsNoneAndAHugeOneNeitherTurnNorPoisonTheGesture() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        rig.overlay.rotateRuler(by: -20, phase: .began)
        for none in [CGFloat.nan, .infinity, -.infinity] {
            rig.overlay.rotateRuler(by: none, phase: .changed)
            XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle, 20, "\(none) turned the ruler")
        }
        rig.overlay.rotateRuler(by: -10, phase: .changed)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle ?? 0, 30, accuracy: 1e-9, "a number after a NaN was not read")
        rig.overlay.rotateRuler(by: CGFloat.greatestFiniteMagnitude, phase: .changed)
        rig.overlay.rotateRuler(by: CGFloat.greatestFiniteMagnitude, phase: .changed)
        rig.overlay.rotateRuler(by: -12, phase: .changed)
        rig.overlay.rotateRuler(by: 0, phase: .ended)
        let angle = try XCTUnwrap(rig.overlay.rulerOnThePicture).angle
        XCTAssertTrue(angle > -90 && angle <= 90 && angle.isFinite)
        // The next gesture is free of what the huge ones did.
        rig.overlay.rotateRuler(by: 0, phase: .began)
        rig.overlay.rotateRuler(by: -5, phase: .changed)
        rig.overlay.rotateRuler(by: 0, phase: .ended)
        XCTAssertNotEqual(rig.overlay.rulerOnThePicture?.angle, angle, "a gesture after the huge ones turned nothing")
    }

    func testAGestureThatBeganAgainWithoutHavingEndedStartsFromTheAngleTheRulerHasNow() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        rig.overlay.rotateRuler(by: -20, phase: .began)
        rig.overlay.rotateRuler(by: -20, phase: .changed)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle ?? 0, 40, accuracy: 1e-9)
        // No end came (the panel lost key, say); the person turns the strip by ⌥-dragging it to 70°, then the gesture begins again.
        let centre = try XCTUnwrap(rig.overlay.rulerOnThePicture).center
        drag(rig, [CGPoint(x: centre.x + 60, y: centre.y + 30), CGPoint(x: centre.x + 60, y: centre.y + 100)], flags: [[.option], [.option]])
        let now = try XCTUnwrap(rig.overlay.rulerOnThePicture).angle
        XCTAssertNotEqual(now, 40, "the fixture's ⌥-drag turned nothing")
        rig.overlay.rotateRuler(by: 0, phase: .began)
        rig.overlay.rotateRuler(by: -5, phase: .changed)
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.angle ?? 0, now + 5, accuracy: 1e-6,
                       "a new gesture began from the angle the last one left (40°+5°), not from the ruler's own (\(now)°)")
    }

    // MARK: the drags

    func testAnOptionLetGoMidDragStillTurnsAndOneTakenMidDragStillMoves() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        let centre = CGPoint(x: 400, y: 300)
        drag(rig, [CGPoint(x: centre.x + 60, y: centre.y), CGPoint(x: centre.x + 60, y: centre.y + 60), CGPoint(x: centre.x + 60, y: centre.y + 120)],
             flags: [[.option], [], []])
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, centre, "an ⌥ let go in the middle turned the drag into a move")
        XCTAssertNotEqual(rig.overlay.rulerOnThePicture?.angle, 0)
        var level = try XCTUnwrap(rig.overlay.rulerOnThePicture)
        level.rotate(to: 0)
        drag(rig, [CGPoint(x: 400, y: 300), CGPoint(x: 420, y: 320), CGPoint(x: 440, y: 340)], flags: [[], [.option], [.option]])
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, CGPoint(x: 440, y: 340), "an ⌥ taken in the middle turned the move into a turn")
    }

    func testUInTheMiddleOfAStrokeAndInTheMiddleOfADragByTheStripLeavesNothingBroken() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        let upper = try XCTUnwrap(rig.overlay.rulerOnThePicture).edges[0].from.y
        rig.overlay.perform(.tool(.pen))
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 300, y: upper - 5), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 350, y: upper - 30), flags: [])
        rig.overlay.perform(.toggleRuler)
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 450, y: upper - 60), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "a stroke with U in the middle of it is not one layer")
        rig.overlay.perform(.undo)
        XCTAssertEqual(rig.view.drawnShapes.count, 0)
        XCTAssertFalse(rig.overlay.palette.canUndo)
        // On: a stroke that began free stays free to its end.
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 150, y: 150), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 200, y: 170), flags: [])
        rig.overlay.perform(.toggleRuler)
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 260, y: 150), flags: [])
        rig.overlay.mouseUp(on: rig.display)
        rig.overlay.perform(.exit(.copy))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("not an edit: \(results)") }
        XCTAssertEqual(layers.count, 1)
        XCTAssertGreaterThan(layers.first?.points.count ?? 0, 2, "a free stroke was straightened by a ruler raised in the middle of it")

        let again = try opened()
        again.overlay.perform(.toggleRuler)
        again.overlay.mouseDown(on: again.display, at: CGPoint(x: 400, y: 300), flags: [])
        again.overlay.mouseDragged(on: again.display, at: CGPoint(x: 420, y: 300), flags: [])
        again.overlay.perform(.toggleRuler)
        again.overlay.mouseDragged(on: again.display, at: CGPoint(x: 460, y: 330), flags: [])
        again.overlay.mouseUp(on: again.display)
        XCTAssertNil(again.overlay.rulerOnThePicture)
        XCTAssertFalse(again.overlay.palette.canUndo)
        XCTAssertEqual(again.view.drawnShapes.count, 0)
    }

    func testAPressOnTheEdgeItselfAndOnePointInsideTheStripTakeTheRulerAndOnePointOutsideDrawsAlongIt() throws {
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        rig.overlay.perform(.tool(.pen))
        let upper = try XCTUnwrap(rig.overlay.rulerOnThePicture).edges[0].from.y
        drag(rig, [CGPoint(x: 400, y: upper - 1), CGPoint(x: 450, y: upper - 40)])
        XCTAssertEqual(rig.view.drawnShapes.count, 1, "a press 1 pt outside the strip did not draw")
        rig.overlay.perform(.undo)
        drag(rig, [CGPoint(x: 400, y: upper + 1), CGPoint(x: 400, y: upper + 40)])
        XCTAssertEqual(rig.view.drawnShapes.count, 0, "a press 1 pt inside the strip drew")
        XCTAssertEqual(rig.overlay.rulerOnThePicture?.center, CGPoint(x: 400, y: 339), "the press inside the strip did not carry it by the drag's own distance")
    }

    // MARK: the exits, the memory, the text

    func testEveryExitHandsOverTheLayersAloneWithTheRulerOnThePicture() throws {
        for how in [EditorExit.confirm, .copy, .save, .pin] {
            let rig = try opened()
            rig.overlay.perform(.tool(.pencil))
            rig.overlay.perform(.toggleRuler)
            let upper = try XCTUnwrap(rig.overlay.rulerOnThePicture).edges[0].from.y
            drag(rig, [CGPoint(x: 300, y: upper - 5), CGPoint(x: 400, y: upper - 30), CGPoint(x: 500, y: upper - 5)])
            // Another stroke still under the pointer, with the ruler being dragged: nothing of it is a layer.
            rig.overlay.perform(.exit(how))
            guard case .edited(_, let local, let layers, let exit)? = results.first else { return XCTFail("\(how): not an edit: \(results)") }
            XCTAssertEqual(exit, how)
            XCTAssertEqual(local, area)
            XCTAssertEqual(layers.count, 1, "\(how): the ruler is among the layers or the stroke is gone")
            XCTAssertEqual(layers.first?.tool, .pencil)
            XCTAssertEqual(layers.first?.points.count, 2)
            XCTAssertEqual(layers.first?.start.y ?? 0, upper, accuracy: 1e-9)
        }
        let rig = try opened()
        rig.overlay.perform(.toggleRuler)
        rig.overlay.mouseDown(on: rig.display, at: CGPoint(x: 400, y: 300), flags: [])
        rig.overlay.mouseDragged(on: rig.display, at: CGPoint(x: 450, y: 330), flags: [])
        rig.overlay.perform(.exit(.copy))
        guard case .edited(_, _, let layers, _)? = results.first else { return XCTFail("not an edit: \(results)") }
        XCTAssertEqual(layers, [], "an exit in the middle of a drag by the strip handed a layer over")
    }

    func testTheEditorsMemoryHoldsNothingOfTheRulerAndANewSessionOpensWithoutIt() throws {
        func session(withRuler: Bool) throws -> [String: Any] {
            let backing = InMemoryKeyValueStore()
            let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
            let rig = try opened(store: store)
            rig.overlay.perform(.tool(.pen))
            if withRuler {
                rig.overlay.perform(.toggleRuler)
                drag(rig, [CGPoint(x: 400, y: 300), CGPoint(x: 450, y: 330)])
                rig.overlay.rotateRuler(by: -20, phase: .began)
            }
            rig.overlay.perform(.exit(.copy))
            let reopened = try opened(store: store)
            XCTAssertNil(reopened.overlay.rulerOnThePicture, "a session opened with the ruler of the last one")
            XCTAssertFalse(reopened.overlay.palette.ruler)
            return backing.raw
        }
        let with = try session(withRuler: true), without = try session(withRuler: false)
        XCTAssertFalse(with.isEmpty, "the session wrote nothing: the comparison reads nothing")
        XCTAssertEqual(Set(with.keys), Set(without.keys), "the ruler wrote a key")
        XCTAssertFalse(with.keys.contains { $0.lowercased().contains("ruler") })
        XCTAssertEqual(NSDictionary(dictionary: with), NSDictionary(dictionary: without), "the ruler changed what was stored")
    }

    func testTheAnglePlateSaysAWholeNumberWithADegreeSignInEveryLanguageAndNeverAMinusZero() {
        AppLanguage.each { language in
            for (degrees, shown) in [(CGFloat(45), "45"), (-45, "45"), (90, "90"), (30, "30"), (-30, "30")] {
                let text = RulerLayer.text(degrees: degrees)
                XCTAssertTrue(text.contains("°"), "\(language): \(degrees) → «\(text)» has no degree sign")
                XCTAssertTrue(text.contains(shown), "\(language): \(degrees) → «\(text)» lost the number")
                XCTAssertFalse(text.contains("."), "\(language): \(degrees) → «\(text)» has a fraction")
            }
            XCTAssertTrue(RulerLayer.text(degrees: -45) != RulerLayer.text(degrees: 45), "\(language): -45° reads as 45°")
            for none in [CGFloat(0), -0.0, -0.3, 0.4] {
                let text = RulerLayer.text(degrees: none)
                XCTAssertFalse(text.contains("-") || text.contains("−") || text.contains("+"), "\(language): \(none) → «\(text)» has a sign")
                XCTAssertTrue(text.contains("0"))
            }
        }
    }
}
