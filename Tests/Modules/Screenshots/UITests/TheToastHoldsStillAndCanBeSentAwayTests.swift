import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Screenshots_UI

/// **The thumbnail's window does not move or resize when the write's result arrives, and the capsule over it has a
/// ✕.** The panel is pinned by its bottom edge, so a size that changed between the working thumbnail and the finished
/// one (a caption line laid out under the picture was how it once did) would lift the picture a moment after it was
/// shown. The caption is not laid out any more; the check stays on what is true now, the fitting size of the view,
/// for the same picture working and done, with the pointer over it or not. A working thumbnail has no ✕ and leaves
/// by its lifetime; a finished one is sent away by the capsule's ✕, which is a control of its own beside the
/// picture, a drag source and a click target of AppKit's.
@MainActor
final class TheToastHoldsStillAndCanBeSentAwayTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The size the panel is given for this content (`place` sets the content size to this).
    private func size(of content: ShotToastModel.Content, hovering: Bool) -> CGSize {
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        model.hovering = hovering
        let host = NSHostingView(rootView: ShotToastView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: ShotToast.width, height: 400)
        return host.fittingSize
    }

    func testTheSizeIsTheSameBeforeAndAfterTheResultArrives() throws {
        var compared = 0
        for (width, height) in [(520, 300), (1200, 300), (300, 1200), (40, 30)] {
            let image = try ShotToastRig.picture(width: width, height: height)
            for hovering in [false, true] {
                for (caption, file) in [(ScStr.saved, nil), (ScStr.copied, nil), (ScStr.savedAndCopied, try ShotToastRig.realFile(self))] as [(String, URL?)] {
                    let working = size(of: .picture(image, caption: nil, file: nil), hovering: hovering)
                    let done = size(of: .picture(image, caption: caption, file: file), hovering: hovering)
                    XCTAssertGreaterThan(working.height, 0, "\(width)×\(height): nothing was laid out")
                    XCTAssertEqual(working.width, done.width, accuracy: 0.5, "\(width)×\(height), pointer \(hovering): the width changed when «\(caption)» arrived")
                    XCTAssertEqual(working.height, done.height, accuracy: 0.5, "\(width)×\(height), pointer \(hovering): the height changed when «\(caption)» arrived")
                    compared += 1
                }
            }
        }
        XCTAssertEqual(compared, 4 * 2 * 3)
    }

    func testAFinishedPictureHasACloseControlInTheCapsuleAndAWorkingOneNone() throws {
        let image = try ShotToastRig.picture()
        let file = try ShotToastRig.realFile(self)
        let cells = ShotCapsule.cells(hasFile: true)
        XCTAssertTrue(cells.contains(.close), "the capsule has no way away")
        XCTAssertEqual(ShotToastRig.controls(.picture(image, caption: "x", file: file)), cells.count,
                       "the capsule's cells, the way away among them: the picture itself is a drag source and a click target of AppKit's, not a SwiftUI control")
        XCTAssertEqual(ShotToastRig.controls(.picture(image, caption: nil, file: nil)), 0,
                       "a picture whose result is not in has no capsule yet: its Copy and Show in Finder need what was written")
    }

    /// Its name is `NamedControlsTests`' to check — the accessibility tree of a
    /// hosting view that was never ordered in answers nothing, so a read of it
    /// here would be a check that finds no fault in any input — and this holds
    /// what that scan cannot: the name is a word, in every language, and is not
    /// the picture's.
    func testTheCloseControlsNameIsAWordAndNotThePictures() {
        AppLanguage.each { language in
            XCTAssertFalse(ScStr.dismissToast.isEmpty, "\(language)")
            XCTAssertNotEqual(ScStr.dismissToast, ScStr.thumbnailLabel, "\(language)")
        }
    }

    /// The toast model's `dismiss()` takes the picture down. **This does not prove
    /// the close control calls it** — it calls `dismiss()` itself, so it stays
    /// green with the control's action emptied. The press is unproven headless
    /// (see the note on the refusal toast's twin).
    func testDismissingTheModelTakesThePictureDown() throws {
        let toast = ShotToast()
        toast.model.content = .picture(try ShotToastRig.picture(), caption: "x", file: nil)
        toast.model.shown = true
        toast.model.dismiss()
        XCTAssertNil(toast.model.content, "dismiss() left the picture up")
        XCTAssertFalse(toast.model.shown)
    }
}
