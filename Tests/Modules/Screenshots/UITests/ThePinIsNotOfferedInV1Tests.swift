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
/// not the switch that hides it. The shot-toast capsule is icons only: it is drawn with the pointer over it and its
/// controls are counted in the rendered tree, one per cell of v1's list without Pin (a drawn Pin would be one more).
/// The palette's words are read back off the picture (text recognition); none is `ScStr.pin`. **The palette has no Pin cell any more; Pin is an item of the ⋯ menu
/// (`EditorMenu.swift`)**, and a menu is not in the picture. The palette is therefore asked by presses:
/// one is sent at every second point across its mounted width in a window ordered in, and no press may come out
/// as `.exit(.pin)`; the same sweep must also produce Done's `.exit(.confirm)` and the pencil, so an empty
/// sweep fails in its own words instead of passing (`testNoPressAcrossTheEditorsPaletteSendsPin`).
///
/// **Why the picture and not the accessibility tree.** A hosting view that was never ordered in
/// answers the tree with nothing, and an invisible window ordered in far off every screen answers
/// nothing either (measured: the tree was `[]` for both). An empty tree has no "Pin" in it, so a
/// check on it passes for ever. The picture cannot be empty by accident: each read first demands what is
/// certainly drawn on that very view, and a read that does not find it fails in its own words instead of
/// passing. The palette and the capsule are icons only, so the demand is that something was inked on the white,
/// since no word is drawn there to ask for; and the capsule's is also its control count, which an empty picture
/// cannot give.
///
/// **The "⋯" menu** is read by its items, as values (`EditorMenu.items`) and as the `NSMenu` filled from them, in every
/// language and for every tool (`testNoItemOnTheMoreMenuIsPin`); the item exists only while `isOffered`, which
/// `TheMenuChecksTheToolInUseTests` asks of the builder at `true` as well.
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

    /// **The ⋯ menu is read by its items, built and as an NSMenu.** Every title of every item, submenus included, in
    /// every language, for every tool and for none; and every action: none is `.exit(.pin)`, none is titled
    /// «Pin». The same read must find Save, so an empty menu fails in its own words instead of passing.
    func testNoItemOnTheMoreMenuIsPin() throws {
        func titles(_ items: [EditorMenuItem]) -> [String] {
            items.flatMap { item -> [String] in
                switch item {
                case .tool(let title, _, _, _): [title]
                case .submenu(let title, _, let children): [title] + titles(children)
                case .action(let title, _, _, _), .reading(let title, _, _, _, _): [title]
                case .separator: []
                }
            }
        }
        func actions(_ items: [EditorMenuItem]) -> [EditorAction] {
            items.flatMap { item -> [EditorAction] in
                switch item {
                case .tool(_, _, _, let action): [action]
                case .submenu(_, _, let children): actions(children)
                case .action(_, let action, _, _), .reading(_, _, let action, _, _): [action]
                case .separator: []
                }
            }
        }
        func every(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(every) ?? []) } }
        XCTAssertFalse(PinEntry.isOffered, "the control: this file is about v1, where the pin is hidden")
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            for tool in [nil] + AnnotationTool.allCases.map({ Optional($0) }) {
                let model = EditorBarModel()
                model.show(tool: tool, style: .standard, canUndo: true, canRedo: true)
                let context = "\(language), tool \(String(describing: tool))"
                let items = EditorMenu.items(for: model)
                XCTAssertTrue(titles(items).contains(ScStr.save), "\(context): the read found no Save, so «no Pin» on the menu means nothing: \(titles(items))")
                XCTAssertFalse(titles(items).contains(ScStr.pin), "\(context): the menu offers «\(ScStr.pin)»")
                XCTAssertFalse(actions(items).contains(.exit(.pin)), "\(context): an item sends the pin exit")
                let menu = EditorMenu.make(for: model)
                menu.delegate?.menuNeedsUpdate?(menu)
                let built = every(menu)
                XCTAssertTrue(built.contains { $0.title == ScStr.save }, "\(context): the NSMenu has no Save")
                XCTAssertFalse(built.contains { $0.title == ScStr.pin }, "\(context): the NSMenu offers «\(ScStr.pin)»")
            }
        }
    }

    /// A saved shot's capsule, drawn with the pointer over it: Copy, Show in Finder and ✕, and no fourth control that
    /// could be a Pin. The count is compared with the list v1 offers (`pinOffered: false`), not with the default,
    /// so a view that drew a Pin whatever the list says fails here.
    func testNoShotToastCapsuleOffersPin() throws {
        AppLanguage.override = .en
        XCTAssertFalse(PinEntry.isOffered, "the control: this file is about v1, where the pin is hidden")
        let image = try ShotToastRig.picture(width: 40, height: 30)
        let file = try ShotToastRig.realFile(self)
        let v1 = ShotCapsule.cells(hasFile: true, pinOffered: false)
        XCTAssertEqual(v1, [.copy, .reveal, .close])
        let capsule = ShotToastRig.mount(.picture(image, caption: ScStr.saved, file: file), hovering: true, width: 300)
        XCTAssertGreaterThan(try inkedPixels(capsule.mount), 0, "the thumbnail drew nothing on white, so «no Pin» on it means nothing")
        XCTAssertEqual(capsule.mount.host.everyView(named: "_FocusRingView").count, v1.count,
                       "the capsule draws other controls than v1's cells: a Pin among them")
        XCTAssertFalse(try words(on: capsule.mount).contains { $0.contains(ScStr.pin.lowercased()) })
        XCTAssertFalse(ShotCapsule.cells(hasFile: true).contains(.pin))
        // A thumbnail still working has no capsule at all: nothing to press, so no Pin; it did draw.
        let working = ShotToastRig.mount(.picture(image, caption: nil, file: nil), hovering: true, width: 300)
        XCTAssertGreaterThan(try inkedPixels(working.mount), 0, "the working thumbnail drew nothing on white")
        XCTAssertEqual(working.mount.host.everyView(named: "_FocusRingView").count, 0, "a working thumbnail offers controls")
    }
}
