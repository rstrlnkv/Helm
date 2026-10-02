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

/// **Three corners of the pin's third pass that no earlier check reached:** the limit plate when the action row
/// stands at the top of the display (the branch that puts the plate under the row), in the widest language on
/// a narrow area, and the picture's scale for a pin whose frame is not a 2x one, and after a scroll.
///
/// Total failure of the subject prints: a plate that lies on the row or leaves the display when there is no room
/// above the row, a layer that declares scale 2 on a 1x or 3x selection, a scrolled pin whose picture stays at its
/// own size inside a larger frame.
@MainActor
final class ThePinPlateAndPictureAtTheEdgesTests: XCTestCase {

    private var rigged: (overlay: CaptureOverlay, display: DisplayID, view: OverlayView)?
    override func tearDown() { rigged?.overlay.close(); rigged = nil; super.tearDown() }

    private func refuse(area: CGRect) throws -> (CaptureOverlay, DisplayID, OverlayView) {
        let built = try OverlayRig.overlay(scale: 1, area: area, pinRoom: { false }) { _ in }
        rigged = built
        built.overlay.perform(.exit(.pin))
        return built
    }

    private func check(_ area: CGRect, language: String) throws {
        let (overlay, display, view) = try refuse(area: area)
        let row = try XCTUnwrap(overlay.chrome(on: display)?.actions, "the control: no action row")
        let flipped = CGRect(x: row.minX, y: view.bounds.height - row.maxY, width: row.width, height: row.height)
        let plate = try XCTUnwrap(view.visiblePlates.first { $0.string == ScStr.pinLimit }, "\(language): the refusal was not shown")
        XCTAssertFalse(plate.frame.intersects(flipped), "\(language) \(area): the plate \(plate.frame) lies on the row \(flipped)")
        XCTAssertTrue(view.bounds.contains(plate.frame), "\(language) \(area): the plate \(plate.frame) left the display \(view.bounds)")
    }

    /// The row at the top of the display: no room above it, so the plate goes under it. The control makes sure the
    /// row really stands where the branch is reached.
    func testWithTheRowAtTheTopOfTheDisplayThePlateGoesUnderItAndStaysInside() throws {
        // A selection ending within ~18 points of the top puts the row (8 below it) where less than the plate's
        // height and gaps is left above it.
        for area in [CGRect(x: 100, y: 0, width: 400, height: 12), CGRect(x: 100, y: 0, width: 400, height: 8),
                     CGRect(x: 0, y: 0, width: 300, height: 10), CGRect(x: 700, y: 0, width: 300, height: 10)] {
            let (overlay, display, view) = try refuse(area: area)
            let row = try XCTUnwrap(overlay.chrome(on: display)?.actions)
            let plate = try XCTUnwrap(view.visiblePlates.first { $0.string == ScStr.pinLimit })
            let flipped = CGRect(x: row.minX, y: view.bounds.height - row.maxY, width: row.width, height: row.height)
            XCTAssertGreaterThan(flipped.maxY + HelmSpace.s2 + plate.frame.height + 4, view.bounds.maxY,
                                 "the control: \(area) leaves room above the row \(flipped), the branch is not reached")
            XCTAssertLessThanOrEqual(plate.frame.maxY, flipped.minY, "the plate \(plate.frame) is not under the row \(flipped)")
            XCTAssertGreaterThanOrEqual(plate.frame.minY, 0)
            rigged?.overlay.close()
        }
    }

    /// Every language, a narrow area near the left, the right, the bottom and the top of the display.
    func testInEveryLanguageOnANarrowAreaNearAnEdgeThePlateIsInsideAndOffTheRow() throws {
        let areas = [CGRect(x: 0, y: 300, width: 60, height: 40), CGRect(x: 940, y: 300, width: 60, height: 40),
                     CGRect(x: 480, y: 760, width: 40, height: 40), CGRect(x: 480, y: 0, width: 40, height: 40),
                     CGRect(x: 0, y: 0, width: 30, height: 30), CGRect(x: 970, y: 770, width: 30, height: 30)]
        var widest: CGFloat = 0
        AppLanguage.each { language in
            for area in areas {
                do {
                    try check(area, language: "\(language)")
                    if let plate = rigged?.view.visiblePlates.first { widest = max(widest, plate.frame.width) }
                    rigged?.overlay.close()
                } catch { XCTFail("\(language) \(area): \(error)") }
            }
        }
        XCTAssertGreaterThan(widest, 250, "the control: the widest language was not met (\(widest))")
    }

    /// The Esc question is where it was: at the pointer's offset, not by the row.
    func testTheEscQuestionStaysAtThePointerAndNotByTheRow() throws {
        let built = try OverlayRig.overlay(scale: 1, area: CGRect(x: 100, y: 100, width: 400, height: 300)) { _ in }
        rigged = built
        built.overlay.perform(.tool(.rectangle))
        built.overlay.mouseDown(on: built.display, at: CGPoint(x: 150, y: 150), flags: [])
        built.overlay.mouseDragged(on: built.display, at: CGPoint(x: 250, y: 250), flags: [])
        built.overlay.mouseUp(on: built.display)
        built.overlay.mouseMoved(on: built.display, at: CGPoint(x: 300, y: 200))
        built.overlay.perform(nil)
        built.overlay.rightMouseDown()
        let plate = try XCTUnwrap(built.view.visiblePlates.first { $0.string == ScStr.confirmClose }, "the control: no question")
        XCTAssertEqual(plate.frame.minX, 300 + 14, accuracy: 1, "the question left the pointer's offset: \(plate.frame)")
    }

    // MARK: The picture's scale

    private func picture(_ width: Int, _ height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    /// The layer declares the scale the picture was cut at, whatever it is: 1, 2 and 3.
    func testTheLayerDeclaresTheScaleThePictureWasCutAt() throws {
        for scale: CGFloat in [1, 2, 3] {
            let panel = PinPanel(image: try picture(300, 201), frame: CGRect(x: 10, y: 10, width: 300 / scale, height: 201 / scale))
            let layer = try XCTUnwrap(panel.pinView.layer)
            XCTAssertEqual(layer.contentsScale, scale, accuracy: 0.001, "a \(scale)x pin declares \(layer.contentsScale)")
            XCTAssertEqual(layer.contentsGravity, .topLeft, "a pin at 1:1 is not stretched at \(scale)x")
        }
    }

    /// The first scroll scale makes the picture follow the frame: it is stretched to it, not left at its own size.
    func testAScrolledPinStillStretchesItsPictureToItsFrame() throws {
        let board = PinBoard(present: { _ in }, screens: { [(DisplayID(1), CGRect(x: 0, y: 0, width: 4000, height: 3000))] })
        let pin = board.open(try picture(400, 200), frame: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(pin.pinView.layer?.contentsGravity, .topLeft, "the control: 1:1 before the scroll")
        let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 30, wheel2: 0, wheel3: 0))
        pin.pinView.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        XCTAssertGreaterThan(pin.frame.width, 200, "the control: the scroll grew the pin")
        XCTAssertEqual(pin.pinView.layer?.contentsGravity, .resize, "the scrolled pin keeps its picture at its own size in a larger frame")
    }
}
