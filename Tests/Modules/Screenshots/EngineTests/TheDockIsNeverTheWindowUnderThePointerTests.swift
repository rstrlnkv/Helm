import CoreGraphics
import XCTest
@testable import Module_Screenshots_Engine

/// The list `CGWindowListCopyWindowInfo` gave on the owner's Mac, front to back:
/// the Dock keeps a full-screen transparent sheet at layer 20 above every normal
/// window, so a rule of "layer 0 and above" picked the Dock at every point.
final class TheDockIsNeverTheWindowUnderThePointerTests: XCTestCase {

    private func owners(extra: [FrozenWindow] = []) -> [FrozenWindow] {
        extra + [
            FrozenWindow(id: 24, frame: CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24, ownerName: "Window Server"),
            FrozenWindow(id: 20, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), layer: 20, ownerName: "Dock"),
            FrozenWindow(id: 101, frame: CGRect(x: 100, y: 80, width: 700, height: 500), layer: 0, ownerName: "Просмотр"),
            FrozenWindow(id: 102, frame: CGRect(x: 500, y: 300, width: 900, height: 600), layer: 0, ownerName: "Finder"),
            FrozenWindow(id: 103, frame: CGRect(x: 50, y: 400, width: 600, height: 450), layer: 0, ownerName: "Музыка"),
        ]
    }

    func testAPointOverANormalWindowPicksThatWindow() {
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 200, y: 150), in: owners())?.id, 101)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 1200, y: 800), in: owners())?.id, 102)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 100, y: 700), in: owners())?.id, 103)
    }

    func testAPointOverOnlyTheDesktopPicksNothing() {
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 1450, y: 100), in: owners()))
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 700, y: 15), in: owners()))
    }

    func testNoPointOnTheScreenPicksTheDockOrTheWindowServer() {
        for x in stride(from: 0, to: 1512, by: 37) {
            for y in stride(from: 0, to: 982, by: 29) {
                let id = WindowPick.window(at: CGPoint(x: x, y: y), in: owners())?.id
                XCTAssertNotEqual(id, 20, "the Dock at \(x),\(y)")
                XCTAssertNotEqual(id, 24, "the Window Server at \(x),\(y)")
            }
        }
    }

    func testAFloatingApplicationPanelIsPickable() {
        let panel = FrozenWindow(id: 150, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                 layer: Int(CGWindowLevelForKey(.floatingWindow)), ownerName: "Palette")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [panel]))?.id, 150)
    }

    func testAStatusLevelItemIsNotPickable() {
        let status = FrozenWindow(id: 160, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                  layer: Int(CGWindowLevelForKey(.statusWindow)), ownerName: "SomeMenuExtra")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [status]))?.id, 101)
    }

    func testTheDockIsRefusedByNameEvenAtAnOrdinaryLevel() {
        let dock = FrozenWindow(id: 170, frame: CGRect(x: 0, y: 0, width: 400, height: 400), layer: 0, ownerName: "Dock")
        XCTAssertNil(WindowPick.window(at: CGPoint(x: 10, y: 10), in: [dock]))
    }
    /// The owner's second reading: with the Dock off the desktop the pick was right.
    /// So the Dock's presence must change nothing — at every point, the pick over
    /// the list with the Dock's sheet equals the pick over the same list without it.
    func testThePickIsTheSameWithAndWithoutTheDock() {
        let withDock = owners()
        let withoutDock = withDock.filter { $0.ownerName != "Dock" }
        XCTAssertEqual(withoutDock.count, withDock.count - 1, "the fixture lost the Dock's sheet")
        var picked = Set<UInt32>()
        var differing: [String] = []
        for x in stride(from: 0, to: 1512, by: 37) {
            for y in stride(from: 0, to: 982, by: 29) {
                let point = CGPoint(x: x, y: y)
                let with = WindowPick.window(at: point, in: withDock)?.id
                let without = WindowPick.window(at: point, in: withoutDock)?.id
                if with != without { differing.append("\(x),\(y): \(String(describing: with)) vs \(String(describing: without))") }
                if let without { picked.insert(without) }
            }
        }
        XCTAssertEqual(differing, [], "the Dock changed the pick at \(differing.count) points")
        // The comparison above passes for a rule that picks nothing anywhere; the
        // sweep has to have reached every application window, and only those.
        XCTAssertEqual(picked, [101, 102, 103])
    }

    func testAWindowJustAboveTheFloatingLevelIsNotPickable() {
        let above = FrozenWindow(id: 151, frame: CGRect(x: 120, y: 100, width: 200, height: 300),
                                 layer: WindowPick.highestLevel + 1, ownerName: "Palette")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [above]))?.id, 101)
    }

    func testAWindowWithNoOwnerNameIsStillAnApplicationWindow() {
        let nameless = FrozenWindow(id: 180, frame: CGRect(x: 120, y: 100, width: 200, height: 300), layer: 0)
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [nameless]))?.id, 180)
    }

    func testATinyOrOffScreenWindowInFrontIsPassedOver() {
        // A zero-size frame contains no point at all, so it would pass with the size
        // bound deleted; a sliver under the bound that does contain the point would not.
        let sliver = FrozenWindow(id: 190, frame: CGRect(x: 148, y: 148, width: WindowPick.smallest - 1,
                                                         height: WindowPick.smallest - 1),
                                  layer: 0, ownerName: "Ghost")
        let away = FrozenWindow(id: 191, frame: CGRect(x: -5000, y: -5000, width: 800, height: 600), layer: 0, ownerName: "Away")
        XCTAssertEqual(WindowPick.window(at: CGPoint(x: 150, y: 150), in: owners(extra: [sliver, away]))?.id, 101)
    }
}
