import CoreGraphics
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// The area's size plate keeps off the palette: a narrow area at the top of the display has no room above its
/// corner, and the place under it is where the palette stands.
final class TheCornerPlateKeepsOffThePaletteTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testThePlateTakesAnotherPlaceWhereTheUnderPlaceIsThePalette() {
        let size = LabelLayer.size(of: "60 × 300")
        let area = CGRect(x: 100, y: 0, width: 60, height: 300)
        let palette = CGRect(x: 40, y: area.maxY + EditorChrome.gap, width: 180, height: 44)
        let free = LabelLayer.cornerPlace(of: size, over: area, within: screen)
        XCTAssertTrue(CGRect(origin: free, size: size).intersects(palette), "the control: with no palette told, it lands on it")
        let at = LabelLayer.cornerPlace(of: size, over: area, within: screen, clearOf: [palette])
        XCTAssertFalse(CGRect(origin: at, size: size).intersects(palette), "the plate is under the palette at \(at)")
        XCTAssertTrue(screen.contains(CGRect(origin: at, size: size)))
    }

    func testAPlateWithAClearFirstPlaceKeepsItWhateverThePaletteIs() {
        let size = LabelLayer.size(of: "400 × 300")
        let area = CGRect(x: 300, y: 300, width: 400, height: 300)
        let palette = CGRect(x: 350, y: area.maxY + EditorChrome.gap, width: 300, height: 44)
        XCTAssertEqual(LabelLayer.cornerPlace(of: size, over: area, within: screen, clearOf: [palette]),
                       LabelLayer.cornerPlace(of: size, over: area, within: screen))
    }
}
