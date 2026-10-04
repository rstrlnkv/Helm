import AppKit
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The selection's loupe and the size plate over the area's corner, fed what the task never named:** a handle
/// dragged off the display, Esc in the middle of a hold, a hold that is released, a new drag, a scale of 2, a
/// pointer in every corner of the screen for the loupe's placement, and areas that sit against a wall or are
/// narrower than their own plate for the plate's.
@MainActor
final class TheLoupeAndTheCornerPlateMeetInputsNobodyFedThemTests: XCTestCase {

    private var overlay: CaptureOverlay?
    private var results: [OverlayResult] = []

    override func tearDown() {
        overlay?.close()
        overlay = nil
        results = []
        super.tearDown()
    }

    private func edit(_ area: CGRect, scale: CGFloat = 1) throws -> (display: DisplayID, view: OverlayView) {
        overlay?.close()
        let rig = try OverlayRig.overlay(scale: scale, area: area) { [weak self] in self?.results.append($0) }
        overlay = rig.overlay
        return (rig.display, rig.view)
    }

    private func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    // MARK: The loupe follows the hold

    func testTheLoupeIsUpOnlyWhileAHandleIsHeld() throws {
        let (display, view) = try edit(CGRect(x: 100, y: 100, width: 400, height: 300), scale: 2)
        XCTAssertNil(view.loupeReading, "a loupe with nothing held")
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        XCTAssertNotNil(view.loupeReading, "the subject: a handle is held and there is no loupe")
        overlay?.mouseDragged(on: display, at: CGPoint(x: 120.4, y: 110.9), flags: [])
        XCTAssertEqual(view.loupeReading?.hasSuffix("· 240, 221"), true, "the reading is not of the pixel under the pointer at 2x: \(String(describing: view.loupeReading))")
        overlay?.mouseUp(on: display)
        XCTAssertNil(view.loupeReading, "the loupe stayed after the release")
        XCTAssertNil(view.loupeDisc)
    }

    func testEscInTheMiddleOfAHoldTakesTheLoupeAndGivesTheAreaBack() throws {
        let (display, view) = try edit(CGRect(x: 100, y: 100, width: 400, height: 300))
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 150, y: 140), flags: [])
        XCTAssertNotNil(view.loupeReading, "the subject")
        overlay?.keyDown(key(53))
        XCTAssertNil(view.loupeReading, "Esc left the loupe up")
        XCTAssertTrue(results.isEmpty, "Esc mid-hold ended the capture")
    }

    /// A press that is not on a handle is the editor's other gestures: none of them is a hold.
    func testNoLoupeForAPressInsideTheAreaOrOutsideIt() throws {
        let (display, view) = try edit(CGRect(x: 100, y: 100, width: 400, height: 300))
        overlay?.mouseDown(on: display, at: CGPoint(x: 300, y: 250), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 320, y: 260), flags: [])
        XCTAssertNil(view.loupeReading)
        overlay?.mouseUp(on: display)
        overlay?.mouseDown(on: display, at: CGPoint(x: 800, y: 700), flags: [])
        overlay?.mouseDragged(on: display, at: CGPoint(x: 850, y: 720), flags: [])
        XCTAssertNil(view.loupeReading, "a new drag is selecting, not holding")
    }

    func testAHandleDraggedOffTheDisplayReadsTheNearestPixelAndTheLoupeStaysOnTheScreen() throws {
        let (display, view) = try edit(CGRect(x: 100, y: 100, width: 400, height: 300))
        overlay?.mouseDown(on: display, at: CGPoint(x: 100, y: 100), flags: [])
        for far in [CGPoint(x: -900, y: -900), CGPoint(x: 5000, y: 5000), CGPoint(x: -1, y: 5000)] {
            overlay?.mouseDragged(on: display, at: far, flags: [])
            XCTAssertNotNil(view.loupeReading, "no loupe for a pointer at \(far)")
            let disc = try XCTUnwrap(view.loupeDisc)
            XCTAssertTrue(view.bounds.contains(disc), "the loupe left the display at \(far): \(disc)")
        }
    }

    // MARK: The loupe's place

    func testTheLoupeAndItsPlateStayInsideAndNeverCoverThePointerOrEachOther() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let plate = LabelLayer.size(of: "#FFFFFF · 1999, 1599")
        let steps: [CGFloat] = [0, 1, 4, 20, 100, 500, 900, 980, 996, 999, 1000]
        for x in steps {
            for y in steps {
                let pointer = CGPoint(x: x, y: min(y, 800))
                let placed = LoupeLayer.place(pointer: pointer, plate: plate, within: bounds)
                XCTAssertTrue(bounds.contains(placed.disc), "disc outside at \(pointer): \(placed.disc)")
                XCTAssertTrue(bounds.contains(placed.plate), "plate outside at \(pointer): \(placed.plate)")
                XCTAssertFalse(placed.disc.intersects(placed.plate), "disc over plate at \(pointer)")
                XCTAssertFalse(placed.disc.contains(pointer), "the loupe covers the pixel it reads at \(pointer)")
                XCTAssertFalse(placed.plate.contains(pointer), "the plate covers the pixel it reads at \(pointer)")
            }
        }
    }

    // MARK: The corner plate keeps off the handles

    /// The size plate stands over the top-left corner, outside the handles' targets. Every sampled point of
    /// the plate must hit no handle, by the rule a press uses.
    func testTheCornerPlateIsOutsideEveryHandleTargetForAreasAgainstAWallAndNarrowOnes() throws {
        let areas = [
            CGRect(x: 100, y: 100, width: 400, height: 300),
            CGRect(x: 100, y: 0, width: 400, height: 300),
            CGRect(x: 100, y: 0, width: 100, height: 300),
            CGRect(x: 100, y: 0, width: 60, height: 300),
            CGRect(x: 0, y: 0, width: 60, height: 60),
            CGRect(x: 940, y: 0, width: 60, height: 200),
            CGRect(x: 0, y: 300, width: 300, height: 200),
            CGRect(x: 100, y: 100, width: 30, height: 30),
        ]
        for area in areas {
            let (_, view) = try edit(area)
            let plate = try XCTUnwrap(view.areaSizePlate, "no plate over \(area)")
            let box = CGRect(x: plate.frame.minX, y: view.bounds.height - plate.frame.maxY,
                             width: plate.frame.width, height: plate.frame.height)
            var hit: AreaHandle?
            var at = box.minX
            while at <= box.maxX, hit == nil {
                var down = box.minY
                while down <= box.maxY, hit == nil {
                    hit = AreaFrame.handle(of: area, at: CGPoint(x: at, y: down))
                    down += 2
                }
                at += 2
            }
            XCTAssertNil(hit, "the size plate \(box) sits on the \(String(describing: hit)) handle of \(area)")
        }
    }

    func testTheCornerPlateSaysTheSizeInPixelsAtTwoX() throws {
        let (_, view) = try edit(CGRect(x: 100, y: 100, width: 400, height: 300), scale: 2)
        XCTAssertEqual(view.areaSizePlate?.string, "800 × 600")
    }

    // MARK: The pure placement of the corner plate

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    /// Whether any point of `plate` is taken by a handle of `area` by the rule a press uses.
    private func hitsAHandle(_ plate: CGRect, of area: CGRect) -> Bool {
        var at = plate.minX
        while at <= plate.maxX {
            var down = plate.minY
            while down <= plate.maxY {
                if AreaFrame.handle(of: area, at: CGPoint(x: at, y: down)) != nil { return true }
                down += 1
            }
            at += 1
        }
        return false
    }

    /// The areas nobody named: as large as the screen, one in each corner, a sliver, a point, a line, and one
    /// that pokes out past the display. Every answer is a finite plate inside the display, and where the plate
    /// sits on a handle the area really leaves no clean place (the sampled ring below finds none).
    func testThePlateIsFiniteOnTheScreenAndOffTheHandlesWheneverAPlaceIsClean() {
        let size = LabelLayer.size(of: "1000 × 800")
        let areas: [CGRect] = [
            screen,
            CGRect(x: 0, y: 0, width: 300, height: 200), CGRect(x: 700, y: 0, width: 300, height: 200),
            CGRect(x: 0, y: 600, width: 300, height: 200), CGRect(x: 700, y: 600, width: 300, height: 200),
            CGRect(x: 0, y: 0, width: 1000, height: 40), CGRect(x: 0, y: 760, width: 1000, height: 40),
            CGRect(x: 0, y: 0, width: 40, height: 800), CGRect(x: 960, y: 0, width: 40, height: 800),
            CGRect(x: 500, y: 400, width: 1, height: 1), CGRect(x: 500, y: 400, width: 0, height: 0),
            CGRect(x: 500, y: 400, width: 0, height: 200), CGRect(x: 500, y: 400, width: 200, height: 0),
            CGRect(x: 0, y: 0, width: 5, height: 5), CGRect(x: 995, y: 795, width: 5, height: 5),
            CGRect(x: 100, y: 100, width: 30, height: 30), CGRect(x: 100, y: 100, width: 5000, height: 5000),
            CGRect(x: -50, y: -50, width: 200, height: 200),
        ]
        var stuck: [CGRect] = []
        for area in areas {
            let at = LabelLayer.cornerPlace(of: size, over: area, within: screen)
            XCTAssertTrue(at.x.isFinite && at.y.isFinite, "not finite for \(area): \(at)")
            let plate = CGRect(origin: at, size: size)
            XCTAssertTrue(screen.contains(plate), "the plate \(plate) left the display for \(area)")
            if hitsAHandle(plate, of: area) { stuck.append(area) }
        }
        // The areas that keep the first place on a handle: report each; each must be one where nothing is clean,
        // i.e. every one of a coarse grid of plate positions over the display hits a handle of the area or is
        // the first place itself.
        for area in stuck {
            var clean = false
            var x = screen.minX + 4
            while x <= screen.maxX - size.width - 4, !clean {
                var y = screen.minY + 4
                while y <= screen.maxY - size.height - 4, !clean {
                    // Only the five places the placement may choose from count as places it should have found.
                    let near = [CGPoint(x: area.minX + 14, y: area.maxY + 12), CGPoint(x: area.minX + 14, y: area.minY + 14),
                                CGPoint(x: area.maxX + 14, y: area.minY), CGPoint(x: area.minX - 14 - size.width, y: area.minY)]
                    if near.contains(where: { abs($0.x - x) < 12 && abs($0.y - y) < 12 }),
                       !hitsAHandle(CGRect(origin: CGPoint(x: x, y: y), size: size), of: area) { clean = true }
                    y += 8
                }
                x += 8
            }
            XCTAssertFalse(clean, "the plate sits on a handle of \(area) though a clean place was within reach")
        }
        print("CORNERPLATE stuck:", stuck)
    }

    func testAPlateOverAnAreaWithAClearCornerStaysAtTheFirstPlace() {
        let size = LabelLayer.size(of: "400 × 300")
        let area = CGRect(x: 300, y: 300, width: 400, height: 300)
        let at = LabelLayer.cornerPlace(of: size, over: area, within: screen)
        XCTAssertEqual(at, CGPoint(x: 314, y: 300 - 12 - size.height), "the first place is the frame's")
    }

    func testAPlateOverAnAreaAgainstTheTopWallTakesAPlaceThatIsNotOnItsHandles() {
        let size = LabelLayer.size(of: "400 × 300")
        let area = CGRect(x: 300, y: 0, width: 100, height: 300)
        let first = CGPoint(x: 314, y: 4)
        let at = LabelLayer.cornerPlace(of: size, over: area, within: screen)
        XCTAssertTrue(hitsAHandle(CGRect(origin: first, size: size), of: area), "the control: the first place is on a handle")
        XCTAssertNotEqual(at, first)
        XCTAssertFalse(hitsAHandle(CGRect(origin: at, size: size), of: area))
    }

    /// NaN and infinity: an area that came out of arithmetic nobody checked. The plate must still be a place a
    /// layer can be given.
    func testANonFiniteAreaGivesAFinitePlace() {
        let size = LabelLayer.size(of: "1 × 1")
        // A NaN *origin* is not fed: it gives a NaN x, and neither producer of an area lets one through (a drag
        // point that is not finite becomes the display's origin, `RememberedSelection.landing` drops a NaN size).
        for area in [CGRect(x: 100, y: 100, width: CGFloat.nan, height: CGFloat.nan),
                     CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10),
                     CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity)] {
            let at = LabelLayer.cornerPlace(of: size, over: area, within: screen)
            XCTAssertTrue(at.x.isFinite && at.y.isFinite, "\(area) gave \(at)")
        }
    }
}
