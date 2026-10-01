import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import Module_Screenshots_UI

/// **The thumbnail does not move when its caption arrives, and there is a way
/// off the screen that does not open the file.** The toast is pinned by its
/// bottom edge, so a caption line that appeared after the picture lifted the
/// picture by its own height a moment after it was shown. And the whole plate
/// was one target that opens the file, for six seconds over whatever was
/// beneath it: a click meant for that opened the shot.
@MainActor
final class TheToastHoldsStillAndCanBeSentAwayTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private func picture() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 520, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    private func height(of content: ShotToastModel.Content) -> CGFloat {
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        let host = NSHostingView(rootView: ShotToastView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: ShotToast.width, height: 400)
        return host.fittingSize.height
    }

    func testTheHeightIsTheSameBeforeAndAfterTheCaptionArrives() throws {
        let image = try picture()
        var compared = 0
        AppLanguage.each { language in
            for caption in [ScStr.saved, ScStr.copied, ScStr.savedAndCopied] {
                let working = height(of: .picture(image, caption: nil, file: nil))
                let done = height(of: .picture(image, caption: caption, file: nil))
                XCTAssertGreaterThan(working, 0, "\(language): nothing was laid out")
                XCTAssertEqual(working, done, accuracy: 0.5,
                               "\(language): the toast was \(working) pt before «\(caption)» and \(done) pt after")
                compared += 1
            }
        }
        XCTAssertEqual(compared, AppLanguage.allCases.count * 3)
    }

    /// Counted off the rendered tree, where a control drawn by SwiftUI is a focus-ring view.
    private func controls(_ content: ShotToastModel.Content) -> Int {
        let model = ShotToastModel()
        model.content = content
        model.shown = true
        let mount = MountedRender(ShotToastView(model: model), width: ShotToast.width, height: 300, appearance: .aqua)
        mount.settle(20)
        return mount.host.everyView(named: "_FocusRingView").count
    }

    func testAPictureToastHasACloseControlBesideTheOpenTarget() throws {
        let image = try picture()
        let file = URL(fileURLWithPath: "/tmp/not-opened.png")
        XCTAssertEqual(controls(.picture(image, caption: "x", file: file)), 2,
                       "the open target and a way away from it")
        XCTAssertEqual(controls(.picture(image, caption: nil, file: nil)), 1,
                       "a picture with no file yet still has the way away")
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
        toast.model.content = .picture(try picture(), caption: "x", file: nil)
        toast.model.shown = true
        toast.model.dismiss()
        XCTAssertNil(toast.model.content, "dismiss() left the picture up")
        XCTAssertFalse(toast.model.shown)
    }
}
