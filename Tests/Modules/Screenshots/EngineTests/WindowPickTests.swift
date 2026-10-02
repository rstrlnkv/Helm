import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

final class WindowPickTests: XCTestCase {

    private func window(_ id: UInt32, _ frame: CGRect, layer: Int = 0) -> FrozenWindow {
        FrozenWindow(id: id, frame: frame, layer: layer)
    }

    func testTheFrontmostWindowUnderThePointerWins() {
        let windows = [window(1, CGRect(x: 100, y: 100, width: 200, height: 200)),
                       window(2, CGRect(x: 0, y: 0, width: 800, height: 600))]
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: windows)?.id, 1)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 500, y: 500), in: windows)?.id, 2)
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 900, y: 900), in: windows))
    }

    func testTheWallpaperAndTinyHelperWindowsAreNotPicked() {
        let windows = [window(1, CGRect(x: 0, y: 0, width: 4, height: 4)),
                       window(2, CGRect(x: 0, y: 0, width: 800, height: 600), layer: -2147483623),
                       window(3, CGRect(x: 0, y: 0, width: 300, height: 300))]
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 2, y: 2), in: windows)?.id, 3)
    }

    func testAWindowStraddlingTwoDisplaysIsCutFromTheOneThatHoldsMore() {
        let displays = [(id: DisplayID(1), frame: CGRect(x: 0, y: 0, width: 1000, height: 800)),
                        (id: DisplayID(2), frame: CGRect(x: 1000, y: 0, width: 1000, height: 800))]
        let home = WindowPick.home(of: CGRect(x: 900, y: 100, width: 400, height: 300), among: displays)
        XCTAssertEqual(home?.id, DisplayID(2))
        XCTAssertEqual(home?.part, CGRect(x: 1000, y: 100, width: 300, height: 300))
        XCTAssertNil(WindowPick.home(of: CGRect(x: 5000, y: 0, width: 10, height: 10), among: displays))
    }
}
