import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The toast's Pin and full picture of a shot whose file is gone say the file is gone; they draw no picture.** The
/// owner's decision of 2026-11-11 (option 3). The shot is taken through the app's own controller over a real file in a
/// scratch folder, and the file is removed or moved before the press. A pin that was handed a picture is counted by
/// `onPin`; a blank one is a picture too, so none must arrive.
///
/// Written against API that does not exist yet, and red by compile error until it does: `CaptureRefusal.fileGone`
/// (one shot's file was not found), worded by `ScStr.refusal(_:)`; the wording is not asserted, the kind is.
///
/// Total failure of the subject prints: a press that does nothing and says nothing (today's Pin), a pin that opens
/// on a blank picture, the refusal said for a file that is there.
@MainActor
final class APinOfAShotWhoseFileIsGoneIsToldNotDrawnBlankTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "pin-gone")
        scenes.append(scene)
        return scene
    }

    private func refusalBody(_ s: PileScene) -> String? {
        if case .refusal(_, let body, _)? = s.toast.model.refusal { body } else { nil }
    }

    func testPinOfAShotWhoseFileWasRemovedOrMovedIsToldAndOpensNoPicture() async throws {
        for move in [false, true] {
            let s = try scene()
            var pinned = 0
            s.toast.onPin = { _, _ in pinned += 1 }
            let shot = try await s.take(width: 400)
            let file = try XCTUnwrap(shot.file)
            // The control: the file is there, nothing is said (no window here, so no pin either).
            XCTAssertNotNil(s.toast.fullPicture(), "the control: a file that is there gave no picture")
            s.toast.model.pin()
            XCTAssertNil(s.toast.model.refusal, "the control: a pin of a file that is there was refused")
            if move {
                try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("elsewhere.png"))
            } else {
                try FileManager.default.removeItem(at: file)
            }
            s.toast.model.pin()
            XCTAssertEqual(refusalBody(s), ScStr.refusal(.fileGone), "move \(move): the press said nothing of the gone file")
            XCTAssertEqual(pinned, 0, "move \(move): a pin was opened on a picture that is not there")
        }
    }

    /// The full picture is what Copy, Share-less drag and Pin ask for: for a gone file it is none, not a blank one,
    /// and the single Copy says the same sentence.
    func testTheFullPictureOfAGoneFileIsNilAndTheCopyOfItSaysTheFileIsGone() async throws {
        let s = try scene()
        let shot = try await s.take(width: 400)
        try FileManager.default.removeItem(at: try XCTUnwrap(shot.file))
        let singles = s.board.singles
        XCTAssertNil(s.toast.fullPicture())
        s.toast.model.copy()
        await waitUntil("the person was told") { s.toast.model.refusal != nil }
        XCTAssertEqual(refusalBody(s), ScStr.refusal(.fileGone))
        XCTAssertEqual(s.board.singles, singles, "a gone file was copied")
    }
}
