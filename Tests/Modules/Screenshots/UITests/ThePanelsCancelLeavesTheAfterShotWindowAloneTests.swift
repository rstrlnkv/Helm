import AppKit
import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The two doors that end only a press, the capture panel's close control and Esc on the panel, leave the after-shot
/// window and a Copy standing in it alone.** A clipboard-only shot has no file: outside the clipboard, that window is
/// the only place the person still has it, and the capsule's Copy and the pile's Copy All are the person's own last
/// act on it; an Esc meant for a panel they opened to take the next shot is neither of them being asked to go. Only
/// the module's switch takes the window and the Copy with it (`teardown`).
///
/// The window and Copy rows build a `PileScene`: the app's own controller, toast and session over a board that counts
/// writes, a Trash that is a folder and a freeze nobody takes: the bar seam counts the panel's presentation and shows
/// nothing, the toast is built with no window (`windowed: false`) and is never ordered in, the store is in memory and
/// the files' folder a scratch directory. The flash row needs a freeze and an overlay, so it stands on
/// `PanelRig.rig`: the overlay is built and never ordered in, and the thumbnail setting is off there, so its toast
/// shows nothing. In both the Esc is delivered by calling the bar panel's `keyDown` on a panel that is built and never
/// ordered in, as `ThePanelMeetsEveryOtherPressTests` does.
///
/// Doors driven: the close control's action (`bar.model.cancel`, which the xmark's cell calls and which the controller
/// wires to `cancel`) and Esc (`BarPanel.keyDown` with key code 53, which calls the same). Doors only read: the picking
/// overlay's Esc ends in `overlayFinished(.cancelled)`, which never reaches `cancel`.
///
/// Total failure of the subject prints: a window that was never up (each window and Copy row first asserts the shots
/// stand before the door, and the two rows of clipboard-only shots that they have no file), a Copy that never wrote
/// (each Copy row has a control, the same press with no door, that must write), a flash that was over before the door
/// (the flash row asserts it open and leaving twice before the door), a door that did nothing (each door row asserts
/// the machine is free afterwards; the window and Copy rows also that the panel was put up once).
@MainActor
final class ThePanelsCancelLeavesTheAfterShotWindowAloneTests: XCTestCase {

    private enum Door: String, CaseIterable {
        case closeControl = "the close control"
        case esc = "Esc on the panel"
    }

    private final class Presented { var bars = 0 }

    private struct Scene {
        let controller: CaptureController
        let toast: ShotToast
        let board: PileBoard
        let presented: Presented
    }

    private var scenes: [Scene] = []
    private var boxes: [PanelRig.Rig] = []

    override func tearDown() {
        for scene in scenes { scene.controller.teardown(); scene.toast.dismiss() }
        scenes = []
        boxes.forEach { $0.controller.teardown() }
        boxes = []
        super.tearDown()
    }

    private func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func scene(_ target: SaveTarget) throws -> Scene {
        let presented = Presented()
        let pile = try PileScene(self, name: "cancel-doors", presentBar: { _ in presented.bars += 1 })
        pile.store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let made = Scene(controller: pile.controller, toast: pile.toast, board: pile.board, presented: presented)
        scenes.append(made)
        return made
    }

    /// The panel is opened as the shortcut opens it, and stands on the screen of nobody: the press is in progress.
    private func openThePanel(_ s: Scene, _ door: Door) {
        s.controller.begin(.panel)
        XCTAssertTrue(s.controller.isBusy, "\(door.rawValue): the panel's press did not begin")
        XCTAssertEqual(s.presented.bars, 1, "\(door.rawValue): the panel was not put up")
    }

    private func drive(_ door: Door, _ controller: CaptureController) {
        switch door {
        case .closeControl: controller.bar.model.cancel()
        case .esc: controller.bar.makePanel().keyDown(with: key(53, "\u{1b}"))
        }
    }

    private func thePressEnded(_ controller: CaptureController, _ door: Door) {
        XCTAssertFalse(controller.isBusy, "\(door.rawValue): the press was not ended")
    }

    // MARK: A clipboard-only shot in the window

    func testAClipboardOnlyShotStandsInTheWindowWhenThePanelIsClosedOrEscaped() async throws {
        for door in Door.allCases {
            let s = try scene(.clipboard)
            await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: 400), kind: .area))
            XCTAssertEqual(s.toast.model.shots.count, 1, "\(door.rawValue): the shot never stood in the window")
            XCTAssertNil(s.toast.model.shots.first?.file, "\(door.rawValue): the shot is not a clipboard-only one")
            XCTAssertEqual(s.board.singles, 1, "\(door.rawValue): the shot was not copied")
            XCTAssertTrue(s.toast.model.shown, "\(door.rawValue): the window is not up")
            openThePanel(s, door)

            drive(door, s.controller)

            thePressEnded(s.controller, door)
            XCTAssertTrue(s.toast.model.shown, "\(door.rawValue): the window went with the press")
            XCTAssertEqual(s.toast.model.shots.count, 1, "\(door.rawValue): the clipboard-only shot was lost")
            XCTAssertNotNil(s.toast.fullPicture(), "\(door.rawValue): the shot no longer holds its picture")
        }
    }

    func testAPileOfClipboardOnlyShotsStandsWhenThePanelIsClosedOrEscaped() async throws {
        for door in Door.allCases {
            let s = try scene(.clipboard)
            for width in [400, 420, 440] {
                await s.controller.handOff(CapturedShot(image: try ShotToastRig.picture(width: width), kind: .area))
            }
            XCTAssertEqual(s.toast.model.shots.count, 3, "\(door.rawValue): the pile never stood")
            XCTAssertTrue(s.toast.model.isPile, "\(door.rawValue): the shots are not a pile")
            XCTAssertTrue(s.toast.model.shots.allSatisfy { $0.file == nil }, "\(door.rawValue): a shot has a file")
            openThePanel(s, door)

            drive(door, s.controller)

            thePressEnded(s.controller, door)
            XCTAssertTrue(s.toast.model.shown, "\(door.rawValue): the window went with the press")
            XCTAssertEqual(s.toast.model.shots.count, 3, "\(door.rawValue): the pile was lost")
        }
    }

    // MARK: A Copy in flight

    /// The capsule's Copy is pressed and the panel's door is driven in the same turn: the Copy's task has been made and
    /// has not reached the board (the board is written after an encode off the cooperative pool and a check of the
    /// task), which is the state an Esc finds for as long as that encode is out. The session's ports hold nothing before
    /// that write, so the press is held by being in the turn it was made in.
    func testACopyFromTheCapsuleStillLandsWhenThePanelIsClosedOrEscaped() async throws {
        let control = try scene(.clipboard)
        control.toast.showDone(try ShotToastRig.picture(width: 400), caption: ScStr.copied, file: nil)
        control.toast.model.copy()
        await waitUntil("the control Copy was written") { control.board.singles >= 1 }

        for door in Door.allCases {
            let s = try scene(.clipboard)
            s.toast.showDone(try ShotToastRig.picture(width: 400), caption: ScStr.copied, file: nil)
            XCTAssertEqual(s.toast.model.shots.count, 1, "\(door.rawValue): the shot never stood in the window")
            XCTAssertEqual(s.board.singles, 0, "\(door.rawValue): the board was written before the Copy")
            s.toast.model.copy()
            XCTAssertEqual(s.board.singles, 0, "\(door.rawValue): the Copy had landed before the door, so it was not in flight")
            openThePanel(s, door)

            drive(door, s.controller)

            thePressEnded(s.controller, door)
            await waitUntil("\(door.rawValue): the Copy was written") { s.board.singles >= 1 }
            await grace(0.1)
            XCTAssertEqual(s.board.singles, 1, "\(door.rawValue): the Copy in flight was cut, or written twice")
            XCTAssertEqual(s.toast.model.shots.count, 1, "\(door.rawValue): the shot was lost with the press")
        }
    }

    func testACopyAllFromThePileStillLandsWhenThePanelIsClosedOrEscaped() async throws {
        let control = try scene(.clipboard)
        for width in [300, 310, 320] { control.toast.showDone(try ShotToastRig.picture(width: width), caption: ScStr.copied, file: nil) }
        control.toast.model.copyAll()
        await waitUntil("the control group was written") { control.board.lists.count >= 1 }

        for door in Door.allCases {
            let s = try scene(.clipboard)
            for width in [300, 310, 320] { s.toast.showDone(try ShotToastRig.picture(width: width), caption: ScStr.copied, file: nil) }
            XCTAssertEqual(s.toast.model.shots.count, 3, "\(door.rawValue): the pile never stood")
            XCTAssertEqual(s.board.lists.count, 0, "\(door.rawValue): the board was written before the Copy All")
            s.toast.model.copyAll()
            XCTAssertEqual(s.board.lists.count, 0, "\(door.rawValue): the Copy All had landed before the door, so it was not in flight")
            openThePanel(s, door)

            drive(door, s.controller)

            thePressEnded(s.controller, door)
            await waitUntil("\(door.rawValue): the group was written") { s.board.lists.count >= 1 }
            await grace(0.1)
            XCTAssertEqual(s.board.lists.count, 1, "\(door.rawValue): the Copy All in flight was cut, or written twice")
            XCTAssertEqual(s.toast.model.shots.count, 3, "\(door.rawValue): the pile was lost with the press")
        }
    }

    // MARK: A flash still up

    /// A shot is taken from the panel and delivered, and the machine is free again while its overlay is still lighting the
    /// area: a second panel opens in that window and its door is driven. The flash is the last press's, which was delivered,
    /// so the door leaves it to close itself. The flash lasts one interface duration, so a precondition that finds the
    /// overlay already closed names itself and does not pass for the door's doing.
    func testTheDoorLeavesTheLastShotsFlashToCloseItself() async throws {
        for door in Door.allCases {
            let box = try PanelRig.rig()
            boxes.append(box)
            box.controller.begin(.panel)
            box.controller.bar.model.choose(.area)
            await waitUntil("\(door.rawValue): the overlay opened") { box.held.overlay != nil }
            let overlay = try XCTUnwrap(box.held.overlay)
            overlay.reducesMotion = { false }
            PanelRig.drag(overlay, on: box.display, PanelRig.area)
            box.controller.capture(from: .area)
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "\(door.rawValue): the subject: the shot is flashing")
            await waitUntil("\(door.rawValue): the shot was delivered and the machine is free") { !box.controller.isBusy }
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "\(door.rawValue): the flash was over before the door, so nothing was proved")
            box.controller.begin(.panel)
            XCTAssertTrue(box.controller.isBusy, "\(door.rawValue): the second panel was not opened")

            drive(door, box.controller)

            thePressEnded(box.controller, door)
            XCTAssertTrue(overlay.isOpen && overlay.leaving, "\(door.rawValue): the door closed the last shot's flash")
            await waitUntil("\(door.rawValue): the flash ended by itself") { !overlay.isOpen }
        }
    }

    // MARK: What the module's end still does

    /// The control of the window and Copy rows: the module's switch takes the window and cuts the Copy.
    func testTheModuleEndingStillTakesTheWindowAndCutsTheCopy() async throws {
        let s = try scene(.clipboard)
        for width in [300, 310] { s.toast.showDone(try ShotToastRig.picture(width: width), caption: ScStr.copied, file: nil) }
        XCTAssertEqual(s.toast.model.shots.count, 2, "the pile never stood")
        s.toast.model.copyAll()
        XCTAssertEqual(s.board.lists.count, 0, "the Copy All had landed before the module went off")
        s.controller.begin(.panel)

        s.controller.teardown()

        await grace(0.3)
        XCTAssertFalse(s.controller.isBusy)
        XCTAssertFalse(s.toast.model.shown, "the module went off and its window stayed")
        XCTAssertTrue(s.toast.model.shots.isEmpty, "the module went off and its shots stayed")
        XCTAssertEqual(s.board.lists.count, 0, "a Copy All was written after the module went off")
    }
}
