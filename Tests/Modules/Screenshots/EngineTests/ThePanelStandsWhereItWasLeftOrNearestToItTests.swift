import CoreGraphics
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// The capture panel's place is one move from where it opens, held inside the screen it appears on: the arithmetic,
/// away from any window. Where the panel really stands is the UI tests'.
final class ThePanelStandsWhereItWasLeftOrNearestToItTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
    private let size = CGSize(width: 420, height: 56)

    func testNoMoveIsBottomCentreAboveTheDock() {
        let origin = PanelPlace.origin(size: size, offset: .zero, in: screen)
        XCTAssertEqual(origin, CGPoint(x: 510, y: 25 + PanelPlace.rise))
    }

    func testAMoveIsAppliedFromThatPlace() {
        let origin = PanelPlace.origin(size: size, offset: PanelOffset(dx: -200, dy: 300), in: screen)
        XCTAssertEqual(origin, CGPoint(x: 310, y: 25 + PanelPlace.rise + 300))
    }

    func testAMoveFromAnotherDeskIsHeldInsideThisOne() {
        let corners: [(PanelOffset, CGPoint)] = [
            (PanelOffset(dx: 5000, dy: 5000), CGPoint(x: 1440 - 420, y: 25 + 850 - 56)),
            (PanelOffset(dx: -5000, dy: -5000), CGPoint(x: 0, y: 25)),
            (PanelOffset(dx: PanelOffset.ceiling, dy: -PanelOffset.ceiling), CGPoint(x: 1440 - 420, y: 25)),
        ]
        for (offset, expected) in corners {
            XCTAssertEqual(PanelPlace.origin(size: size, offset: offset, in: screen), expected, "\(offset)")
        }
    }

    func testEveryOffsetLeavesThePanelWhollyInsideAScreenThatCanFitIt() {
        for dx in stride(from: -3000.0, through: 3000, by: 500) {
            for dy in stride(from: -3000.0, through: 3000, by: 500) {
                let origin = PanelPlace.origin(size: size, offset: PanelOffset(dx: dx, dy: dy), in: screen)
                XCTAssertTrue(screen.contains(CGRect(origin: origin, size: size)), "\(dx), \(dy) put the panel at \(origin)")
            }
        }
    }

    func testAScreenSmallerThanThePanelKeepsItsLowerLeftCornerAndNeverTraps() {
        let tiny = CGRect(x: 100, y: 100, width: 200, height: 30)
        for offset in [PanelOffset.zero, PanelOffset(dx: 1e9, dy: 1e9), PanelOffset(dx: -1e9, dy: -1e9)] {
            XCTAssertEqual(PanelPlace.origin(size: size, offset: offset, in: tiny), CGPoint(x: 100, y: 100))
        }
    }

    func testTheOffsetOfWhereItStandsPutsItThereAgain() {
        let left = CGPoint(x: 777, y: 400)
        let offset = PanelPlace.offset(of: left, size: size, in: screen)
        XCTAssertEqual(PanelPlace.origin(size: size, offset: offset, in: screen), left)
        XCTAssertEqual(PanelPlace.offset(of: PanelPlace.standard(size: size, in: screen), size: size, in: screen), .zero)
    }

    func testAnOffsetFromAnOriginThatIsNoNumberIsNoMove() {
        let offset = PanelPlace.offset(of: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), size: size, in: screen)
        XCTAssertEqual(offset.dx, 0)
        XCTAssertEqual(offset.dy, PanelOffset.ceiling)
    }

    func testTheOffsetRoundTripsThroughTheStoreAndForgetsOnErase() {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        PanelOffset(dx: -12.5, dy: 80).write(to: store)
        XCTAssertEqual(PanelOffset.read(store), PanelOffset(dx: -12.5, dy: 80))
        PanelOffset.erase(from: store)
        XCTAssertEqual(PanelOffset.read(store), .zero)
        XCTAssertNil(store.object(ScreenshotsSettings.Key.panelOffsetX))
        XCTAssertNil(store.object(ScreenshotsSettings.Key.panelOffsetY))
    }
}
