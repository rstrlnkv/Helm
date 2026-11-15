import CoreGraphics
import XCTest
@testable import Module_Screenshots_UI

/// **The pointer over one shot's view moves the capsule to that shot in the row, and folded only the newest shot's view
/// counts.** The model alone, three shots added by hand, the toast's clock told by `hoverChanged`.
///
/// Total failure of the subject prints: the capsule on a shot the pointer left, a sliver under the newest sheet taking
/// the capsule, the toast's clock not told of the pointer.
///
/// Mutants, red here: `focus == id` becomes `focus != id`; `id == shots.last?.id` becomes `id != shots.last?.id`;
/// `focus = id` becomes `focus = nil`.
@MainActor
final class ThePointerOverAShotMovesTheCapsuleToThatShotTests: XCTestCase {

    private func model() throws -> (model: ShotToastModel, ids: [ShotToastModel.Shot.ID], told: () -> [Bool]) {
        let model = ShotToastModel()
        var told: [Bool] = []
        model.hoverChanged = { told.append($0) }
        let picture = try ShotToastRig.picture(width: 40, height: 30)
        let ids = (0..<3).map { _ in model.add(picture, caption: "c", file: nil) }
        return (model, ids, { told })
    }

    func testInTheRowTheCapsuleFollowsThePointerFromShotToShotAndLeavesWithIt() throws {
        let (model, ids, told) = try model()
        model.unfolded = true
        model.pointer(over: true, shot: ids[0])
        XCTAssertEqual(model.focus, ids[0], "the capsule did not come to the shot entered")
        model.pointer(over: true, shot: ids[1])
        XCTAssertEqual(model.focus, ids[1])
        model.pointer(over: false, shot: ids[0])
        XCTAssertEqual(model.focus, ids[1], "the exit of a shot already left took the capsule from the one entered")
        model.pointer(over: false, shot: ids[1])
        XCTAssertNil(model.focus, "the capsule stayed on a shot the pointer left")
        XCTAssertEqual(told(), [], "the row's shots told the toast's clock of the pointer")
    }

    func testFoldedOnlyTheNewestShotsViewCountsAndItTellsTheClock() throws {
        let (model, ids, told) = try model()
        model.pointer(over: true, shot: ids[0])
        XCTAssertFalse(model.hovering, "a sliver under the newest sheet raised the capsule")
        XCTAssertEqual(told(), [])
        model.pointer(over: true, shot: ids[2])
        XCTAssertTrue(model.hovering)
        XCTAssertEqual(told(), [true])
        model.pointer(over: false, shot: ids[0])
        XCTAssertTrue(model.hovering, "a sliver's exit took the capsule from under the pointer")
        model.pointer(over: false, shot: ids[2])
        XCTAssertFalse(model.hovering)
        XCTAssertEqual(told(), [true, false])
        XCTAssertNil(model.focus, "folded, the pointer set a shot of the row")
    }
}
