import AppKit
import CoreGraphics
import Foundation
import HelmTestSupport
import ImageIO
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **«Copy All» with one shot's file gone puts every shot that is still found on the board in one write, and tells the
/// person which shot is missing; it does not refuse the whole copy.** The owner's decision of 2026-11-11 (option 3:
/// the pile keeps no full picture of a written shot, so a gone file cannot be copied, and is said). The scene is the
/// app's own over real files in a scratch folder; the file is removed or moved on disk before the press.
///
/// Written against API that does not exist yet, and red by compile error until it does:
/// `CaptureRefusal.filesGone([Int])`, the zero-based places, in the list `ShotToast.sources()` hands the session, of the
/// shots whose file was not found; `ScStr.refusal(_:)` words it. The wording is not asserted, the kind and the places are.
///
/// Total failure of the subject prints: a board with nothing on it (the whole-copy refusal of today), a board with all
/// three (a gone file read from nowhere), the missing shot named as another place, nothing told.
@MainActor
final class AShotWhoseFileIsGoneIsNamedAndTheRestIsCopiedTests: XCTestCase {

    private var scenes: [PileScene] = []

    override func tearDown() {
        for scene in scenes { scene.teardown() }
        scenes = []
        super.tearDown()
    }

    private func scene() throws -> PileScene {
        let scene = try PileScene(self, name: "copy-all-gone")
        scenes.append(scene)
        return scene
    }

    private func width(of png: Data) throws -> Int {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil), "a write that is no picture")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
    }

    private func refusalBody(_ s: PileScene) -> String? {
        if case .refusal(_, let body, _)? = s.toast.model.refusal { body } else { nil }
    }

    /// Whichever way the file is gone, and whichever of the three it is, the other two are on the board in the list's order.
    func testAShotWhoseFileWasRemovedOrMovedIsLeftOutNamedAndTheOthersAreCopiedInOneWrite() async throws {
        for (gone, move) in [(1, false), (1, true), (0, false), (2, true)] {
            let s = try scene()
            let widths = [400, 420, 440]
            var shots: [ShotToastModel.Shot] = []
            for width in widths { shots.append(try await s.take(width: width)) }
            let file = try XCTUnwrap(shots[gone].file)
            let singles = s.board.singles
            if move {
                try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("elsewhere.png"))
            } else {
                try FileManager.default.removeItem(at: file)
            }
            s.toast.model.copyAll()
            await waitUntil("\(gone)/\(move): the others were written") { s.board.lists.count >= 1 }
            await grace(0.1)
            XCTAssertEqual(s.board.lists.count, 1, "\(gone)/\(move): the found shots were \(s.board.lists.count) writes")
            XCTAssertEqual(s.board.singles, singles, "\(gone)/\(move): a shot went by the single write")
            XCTAssertEqual(try XCTUnwrap(s.board.lists.first).map(width(of:)),
                           widths.enumerated().filter { $0.offset != gone }.map(\.element),
                           "\(gone)/\(move): not every shot that is found, in the list's order")
            XCTAssertEqual(refusalBody(s), ScStr.refusal(.filesGone([gone])), "\(gone)/\(move): the missing shot was not named")
            XCTAssertEqual(s.toast.model.shots.count, 3, "the notice took the shots with it")
            // The plaque goes by its clock and the shots are back under it, folded.
            XCTAssertFalse(s.toast.advance(by: 8.5))
            XCTAssertFalse(s.toast.advance(by: 0.5))
            XCTAssertNil(s.toast.model.refusal)
            XCTAssertTrue(s.toast.model.isPile)
            XCTAssertEqual(s.toast.sources().count, 3)
        }
    }

    /// Every file gone: nothing to put on the board, and the person is told which ones; no empty write.
    func testAPileWhoseEveryFileIsGoneWritesNothingAndNamesEveryShot() async throws {
        let s = try scene()
        var shots: [ShotToastModel.Shot] = []
        for width in [400, 420] { shots.append(try await s.take(width: width)) }
        let singles = s.board.singles
        for shot in shots { try FileManager.default.removeItem(at: try XCTUnwrap(shot.file)) }
        s.toast.model.copyAll()
        await waitUntil("the person was told") { s.toast.model.refusal != nil }
        XCTAssertEqual(s.board.lists.count, 0)
        XCTAssertEqual(s.board.singles, singles)
        XCTAssertEqual(refusalBody(s), ScStr.refusal(.filesGone([0, 1])))
    }
}
