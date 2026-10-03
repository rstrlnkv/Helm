import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// **The area's handles are offered while the picture has no layer, or Crop is on.** One predicate answers the press and the
/// screen's dots, so a press at a handle's centre is the area's exactly when the predicate says so.
final class TheHandlesComeBackOnlyWithCropTests: XCTestCase {

    private let area = CGRect(x: 100, y: 100, width: 400, height: 300)

    func testTheFourCombinationsOfLayersAndCrop() {
        XCTAssertTrue(AreaFrame.offersHandles(layersExist: false, cropping: false), "a bare picture is held by its handles")
        XCTAssertFalse(AreaFrame.offersHandles(layersExist: true, cropping: false), "a marked picture still offered its handles")
        XCTAssertTrue(AreaFrame.offersHandles(layersExist: true, cropping: true), "Crop did not bring the handles back")
        XCTAssertTrue(AreaFrame.offersHandles(layersExist: false, cropping: true))
    }

    func testAPressTakesAHandleOnlyWhereTheyAreOffered() {
        for place in AreaFrame.handles(of: area) {
            XCTAssertEqual(AreaFrame.handle(of: area, at: place.point), place.handle, "\(place.handle), bare")
            XCTAssertNil(AreaFrame.handle(of: area, at: place.point, layersExist: true), "\(place.handle), marked")
            XCTAssertEqual(AreaFrame.handle(of: area, at: place.point, layersExist: true, cropping: true), place.handle,
                           "\(place.handle), marked and cropping")
        }
    }

    func testAnObjectsHandleStillWinsAnOverlapWhileCropIsOn() {
        let object = drawnAndSelectedRectangle(in: area).selected
        let corner = CGPoint(x: object?.frame.minX ?? 0, y: object?.frame.minY ?? 0)
        // The same press on a copy of the area whose corner is the object's corner: the object's handle is first.
        let held = CGRect(x: corner.x, y: corner.y, width: 200, height: 150)
        XCTAssertNil(AreaFrame.handle(of: held, at: corner, yieldingTo: object, layersExist: true, cropping: true))
        XCTAssertEqual(AreaFrame.handle(of: held, at: corner, layersExist: true, cropping: true), .topLeft)
    }
}
