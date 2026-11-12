import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The toast's single Copy of a shot whose file is gone says the file is gone; it draws no picture.** The
/// owner's decision of 2026-11-11 (option 3). The shot is taken through the app's own controller over a real file in a
/// scratch folder, and the file is removed before the press.
///
/// The kind is asserted, not the wording: `CaptureRefusal.fileGone` (one shot's file was not found), worded by
/// `ScStr.refusal(_:)`.
///
/// Total failure of the subject prints: a press that does nothing and says nothing, a copy of a blank picture.
@MainActor
final class TheCopyOfAShotWhoseFileIsGoneIsToldNotDrawnBlankTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "copy-gone")
        scenes.append(scene)
        return scene
    }

    private func refusalBody(_ s: PileScene) -> String? {
        if case .refusal(_, let body, _)? = s.toast.model.refusal { body } else { nil }
    }

    /// The full picture is what Copy and the Share-less drag ask for: for a gone file it is none, not a blank one,
    /// and the single Copy says the sentence.
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
