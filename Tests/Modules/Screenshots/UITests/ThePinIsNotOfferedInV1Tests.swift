import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import SwiftUI
import Vision
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The pin is in the tree and out of v1: nothing a person can press says "Pin".** The owner's
/// decision of 2026-10-02 keeps the pin's code and hides every way in. This asks what is *offered*,
/// not the switch that hides it. The shot-toast capsule is drawn and the words on it are read back off the
/// picture (text recognition); none is `ScStr.pin`. **The palette's Pin cell is an icon with a name and no printed
/// word**, so the picture cannot see it (measured: `EditorPalette` at `isOffered = true` is 451 pt wide in a hosting
/// view and 419 pt at `false`, and the word read passed at `true`). The palette is therefore asked by presses:
/// one is sent at every second point across its mounted width in a window ordered in, and no press may come out
/// as `.exit(.pin)`; the same sweep must also produce Done's `.exit(.confirm)` and the pencil, so an empty
/// sweep fails in its own words instead of passing (`testNoPressAcrossTheEditorsPaletteSendsPin`).
///
/// **Why the picture and not the accessibility tree.** A hosting view that was never ordered in
/// answers the tree with nothing, and an invisible window ordered in far off every screen answers
/// nothing either (measured: the tree was `[]` for both). An empty tree has no "Pin" in it, so a
/// check on it passes for ever. The picture cannot be empty by accident: each read first demands what is
/// certainly drawn on that very view, and a read that does not find it fails in its own words instead of
/// passing. Where the view has words, they are the demand (the caption on a toast that has one). The palette
/// is icons only, and a toast still working has an invisible caption: for those two the demand is that
/// something was inked on the white, since no word is drawn there to ask for.
///
/// **What this does not reach.** The "⋯" menu is an `NSMenu` and is read by its item titles; it does
/// not exist yet, and its half joins this file when it does.
@MainActor
final class ThePinIsNotOfferedInV1Tests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// The words drawn on `host`, lower-cased, one entry per recognised line. The view is transparent
    /// glass, so its picture is laid on white first, the way a person sees it on a light screen.
    private func words(on mount: MountedRender) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: try onWhite(mount)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }
    }

    /// The view's picture laid on white.
    private func onWhite(_ mount: MountedRender) throws -> CGImage {
        let host = mount.host
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let size = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(try XCTUnwrap(rep.cgImage), in: CGRect(origin: .zero, size: size))
        return try XCTUnwrap(context.makeImage())
    }

    /// How many pixels of the view's picture, laid on white, are not white.
    private func inkedPixels(_ mount: MountedRender) throws -> Int {
        let image = try onWhite(mount)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] < 250 || bytes[$0 + 1] < 250 || bytes[$0 + 2] < 250 }.count
    }

    private func mounted<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> MountedRender {
        let mount = MountedRender(view, width: width, height: height, appearance: .aqua)
        mount.settle(20)
        return mount
    }

    func testNoControlOnTheEditorsPaletteIsLabelledPin() throws {
        AppLanguage.override = .en
        let palette = mounted(EditorPalette(model: EditorBarModel()), width: 700, height: EditorPalette.height)
        XCTAssertGreaterThan(try inkedPixels(palette), 0, "the palette drew nothing on white, so «no Pin» on it means nothing")
        let drawn = try words(on: palette)
        XCTAssertFalse(drawn.contains { $0.contains(ScStr.pin.lowercased()) }, "the palette offers «\(ScStr.pin)»: \(drawn)")
    }

    func testNoPressAcrossTheEditorsPaletteSendsPin() throws {
        for language in AppLanguage.allCases {
            let sent = try actionsAcrossThePalette(language: language)
            XCTAssertTrue(sent.contains { $0.action == .exit(.confirm) }, "\(language): no press reached Done, so «no Pin» on the palette means nothing: \(sent.count) presses")
            XCTAssertTrue(sent.contains { $0.action == .tool(.pencil) }, "\(language): no press reached the pencil, so the sweep did not cover the palette")
            XCTAssertFalse(sent.contains { $0.action == .exit(.pin) }, "\(language): a press on the palette sent the pin exit")
        }
    }

    private func picture() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    func testNoShotToastCapsuleOffersPin() throws {
        AppLanguage.override = .en
        let image = try picture()
        let file = URL(fileURLWithPath: "/tmp/not-opened.png")
        for (name, content) in [("a picture with a file", ShotToastModel.Content.picture(image, caption: ScStr.saved, file: file)),
                                ("a picture still working", .picture(image, caption: nil, file: nil))] {
            let model = ShotToastModel()
            model.content = content
            model.shown = true
            let toast = mounted(ShotToastView(model: model), width: ShotToast.width, height: 300)
            let drawn = try words(on: toast)
            if case .picture(_, let caption?, _) = content {
                XCTAssertTrue(drawn.contains { $0.contains(caption.lowercased()) },
                              "\(name): the read found no «\(caption)» — the picture read empty, so «no Pin» means nothing: \(drawn)")
            } else {
                XCTAssertGreaterThan(try inkedPixels(toast), 0, "\(name): the capsule drew nothing on white, so «no Pin» on it means nothing")
            }
            XCTAssertFalse(drawn.contains { $0.contains(ScStr.pin.lowercased()) }, "\(name): the capsule offers «\(ScStr.pin)»: \(drawn)")
        }
    }
}
