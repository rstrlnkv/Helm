import AppKit
import HelmTestSupport
@testable import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **Follow says its state with its glyph, and with no fill.** The owner
/// (2026-09-30): the button lit in the accent colour stands out of the capsule
/// — «blue is out of place, although it is like the accent» — and asked for two
/// glyphs instead, an open eye and a slashed one. A toggle given a
/// `HelmToolbarToggleFace` draws its own symbol when on, `offSymbol` when off,
/// never the accent, and says following or not following as its accessibility
/// value; a toggle with no face is drawn as it always was.
///
/// **What is asserted is what was drawn, by reference.** The capsule is
/// rendered through the real toolbar channel with one action in it, and the
/// glyph's ink — how much of it there is and what colour it is — is compared
/// against a plain button of the same symbol drawn through the same path: the
/// toggle's «on» must be the plain `eye` and its «off» the plain `eye.slash`,
/// to the pixel's tolerance, in both appearances. A tint would move the colour
/// and not the coverage, so colour is read on its own. The control is the old
/// toggle with no face, whose accent must still read as different from the
/// plain button's ink — without it, «no accent» could pass on a reading that
/// cannot see an accent at all.
///
/// With `HELM_FRAMES_DIR` set, each state in each appearance is also written as
/// a PNG over the window's own background, for a person to look at.
@MainActor
final class TheFollowGlyphIsAnEyeTests: XCTestCase {

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    private struct Reading {
        let coverage: CGFloat
        let red: CGFloat, green: CGFloat, blue: CGFloat
        func colourDistance(to other: Reading) -> CGFloat {
            max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
        }
    }

    private let face = HelmToolbarToggleFace(offSymbol: "eye.slash", onValue: "Following",
                                             offValue: "Not following")

    private var framesDir: String? { ProcessInfo.processInfo.environment["HELM_FRAMES_DIR"] }

    /// The glyph in slot 0 of a capsule holding only `action`: its coverage
    /// (every alpha summed, in pixels) and its alpha-weighted mean colour in
    /// sRGB. Nil when nothing was drawn — a reading of a blank is a guess.
    private func reading(of action: HelmToolbarAction, appearance: NSAppearance.Name,
                         name: String) throws -> Reading? {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module("test.follow"),
                                        width: 1060, height: 700, appearance: appearance)
        defer { fx.drop() }
        fx.channel.declare(HelmPageToolbarContent(actions: [action]), token: "test.follow",
                           generation: fx.channel.nextGeneration())
        fx.settle(30)
        let toolbar = try XCTUnwrap(fx.mount.window?.toolbar, "no toolbar")
        let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "helm.actions" },
                                 "no helm.actions item")
        let capsule = try XCTUnwrap(item.view, "no capsule")
        XCTAssertEqual((item.view as? NSHostingView<HelmToolbarActionsCapsule>)?.rootView.model.visibleIDs,
                       [action.id], "the capsule does not hold exactly the action under test")
        guard let rep = capsule.bitmapImageRepForCachingDisplay(in: capsule.bounds) else { return nil }
        capsule.cacheDisplay(in: capsule.bounds, to: rep)
        picture(rep, appearance: appearance, name: name)

        let side = HelmToolbarActionsCapsule.side
        let scale = CGFloat(rep.pixelsWide) / max(capsule.bounds.width, 1)
        let to = min(rep.pixelsWide, Int((side * scale).rounded(.up)))
        var coverage: CGFloat = 0, red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<to {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let alpha = colour.alphaComponent
                coverage += alpha
                red += colour.redComponent * alpha
                green += colour.greenComponent * alpha
                blue += colour.blueComponent * alpha
            }
        }
        guard coverage > 0 else { return nil }
        return Reading(coverage: coverage, red: red / coverage, green: green / coverage,
                       blue: blue / coverage)
    }

    /// **The picture for a person, with `HELM_FRAMES_DIR` set**: slot 0 of the
    /// capsule as measured above. Offscreen the toolbar item's glyphs come out
    /// white on a transparent bitmap in both appearances — the ink SwiftUI gives
    /// a glyph that sits on glass, and glass does not composite here — so the
    /// picture recolours the white ones to the appearance's own label ink,
    /// leaves any other colour (the accent of a toggle with no face) as drawn,
    /// and lays the result on the window's background. A picture of the glyphs,
    /// not of the glass; the assertions do not read it.
    private func picture(_ rep: NSBitmapImageRep, appearance: NSAppearance.Name, name: String) {
        guard let dir = framesDir else { return }
        var background = NSColor.white, ink = NSColor.black
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
            ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
        }
        let side = Int((HelmToolbarActionsCapsule.side * CGFloat(rep.pixelsWide)
                        / max(CGFloat(rep.size.width), 1)).rounded(.up))
        let height = rep.pixelsHigh
        var bytes = [UInt8](repeating: 255, count: side * height * 4)
        func byte(_ value: CGFloat) -> UInt8 { UInt8(max(0, min(255, (value * 255).rounded()))) }
        for y in 0..<height {
            for x in 0..<side {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .clear
                let a = c.alphaComponent
                let white = c.redComponent > 0.95 && c.greenComponent > 0.95 && c.blueComponent > 0.95
                let source = white ? ink : c
                let at = (y * side + x) * 4
                bytes[at] = byte(source.redComponent * a + background.redComponent * (1 - a))
                bytes[at + 1] = byte(source.greenComponent * a + background.greenComponent * (1 - a))
                bytes[at + 2] = byte(source.blueComponent * a + background.blueComponent * (1 - a))
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: side, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(
            "follow-\(name)-\(RenderedInk.label(of: appearance)).png"))
    }

    // MARK: - What is drawn

    func testFollowDrawsAnOpenEyeWhenOnAndASlashedEyeWhenOffWithNoAccent() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let plainEye = try XCTUnwrap(reading(of: HelmToolbarAction(id: "follow", title: "Follow",
                                                                       symbol: "eye") {},
                                                 appearance: appearance, name: "reference-eye"),
                                         "\(screen): the reference eye drew nothing")
            let plainSlash = try XCTUnwrap(reading(of: HelmToolbarAction(id: "follow", title: "Follow",
                                                                         symbol: "eye.slash") {},
                                                   appearance: appearance, name: "reference-slash"),
                                           "\(screen): the reference slashed eye drew nothing")
            XCTAssertGreaterThan(abs(plainSlash.coverage - plainEye.coverage) / plainEye.coverage, 0.05, """
                \(screen): the open and the slashed eye draw the same amount of ink, so matching \
                either proves nothing about which was drawn
                """)

            let on = try XCTUnwrap(reading(of: HelmToolbarAction(id: "follow", title: "Follow",
                                                                 symbol: "eye", isOn: true, face: face) {},
                                           appearance: appearance, name: "on"),
                                   "\(screen): Follow drew nothing when on")
            let off = try XCTUnwrap(reading(of: HelmToolbarAction(id: "follow", title: "Follow",
                                                                  symbol: "eye", isOn: false, face: face) {},
                                            appearance: appearance, name: "off"),
                                    "\(screen): Follow drew nothing when off")

            XCTAssertEqual(on.coverage / plainEye.coverage, 1, accuracy: 0.02, """
                \(screen): Follow on is not the open eye — it draws \(on.coverage / plainEye.coverage) \
                of the plain `eye`'s ink
                """)
            XCTAssertEqual(off.coverage / plainSlash.coverage, 1, accuracy: 0.02, """
                \(screen): Follow off is not the slashed eye — it draws \
                \(off.coverage / plainSlash.coverage) of the plain `eye.slash`'s ink
                """)
            XCTAssertLessThan(on.colourDistance(to: plainEye), 0.03, """
                \(screen): Follow on is drawn in a colour of its own (\(on.red), \(on.green), \(on.blue)) \
                where the capsule's other glyphs draw (\(plainEye.red), \(plainEye.green), \(plainEye.blue))
                """)
            XCTAssertLessThan(off.colourDistance(to: plainSlash), 0.03, "\(screen): Follow off is tinted")
        }
    }

    /// The control for the test above, and the promise that no other page
    /// changes: a toggle with no face is still drawn in the accent, and a
    /// reading that could not tell that from the plain ink would pass the
    /// assertion above on any colour.
    func testAToggleWithNoFaceIsStillDrawnInTheAccent() throws {
        for appearance in RenderedInk.bothAppearances {
            let screen = RenderedInk.label(of: appearance)
            let plain = try XCTUnwrap(reading(of: HelmToolbarAction(id: "mode", title: "Mode",
                                                                    symbol: "text.alignleft") {},
                                              appearance: appearance, name: "control-plain"))
            let lit = try XCTUnwrap(reading(of: HelmToolbarAction(id: "mode", title: "Mode",
                                                                  symbol: "text.alignleft", isOn: true) {},
                                            appearance: appearance, name: "control-lit"))
            XCTAssertGreaterThan(lit.colourDistance(to: plain), 0.15, """
                \(screen): a lit toggle with no face reads as the plain ink — either the accent is \
                gone from every other toggle or this reading cannot see one
                """)
        }
    }

    // MARK: - What is declared and said

    /// Follow as the Log page declares it: the open eye, the slashed eye as its
    /// face, and the value its accessibility carries — following or not
    /// following, in each of the eight languages, two different words, neither
    /// the control's own name.
    func testTheLogDeclaresTheEyesAndTheValueInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let page = LogPageUnderHand(LogPageUnderHand.log())
            defer { page.close() }
            page.pump(0.6)
            let follow = try page.action("follow")
            XCTAssertEqual(follow.symbol, "eye", "\(language.rawValue)")
            let declared = try XCTUnwrap(follow.toggleFace, "\(language.rawValue): Follow has no face")
            XCTAssertEqual(declared.offSymbol, "eye.slash", "\(language.rawValue)")
            XCTAssertEqual(declared.onValue, AppStr.logFollowing, "\(language.rawValue)")
            XCTAssertEqual(declared.offValue, AppStr.logNotFollowing, "\(language.rawValue)")
            XCTAssertNotEqual(declared.onValue, declared.offValue, "\(language.rawValue)")
            XCTAssertNotEqual(declared.onValue, follow.title, "\(language.rawValue): the value repeats the name")
            if language != .en {
                XCTAssertNotEqual(declared.onValue, "Following", "\(language.rawValue): not translated")
                XCTAssertNotEqual(declared.offValue, "Not following", "\(language.rawValue): not translated")
            }
        }
    }

    /// The face survives the trip from the declaration into the capsule's
    /// closure-free model, so what the capsule draws from is what the page
    /// declared.
    func testTheFaceReachesTheCapsulesModel() throws {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module("test.follow"),
                                        width: 1060, height: 700)
        defer { fx.drop() }
        fx.channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "follow", title: "Follow", symbol: "eye", isOn: true, face: face) {}
        ]), token: "test.follow", generation: fx.channel.nextGeneration())
        fx.settle(30)
        let item = try XCTUnwrap(fx.mount.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "helm.actions" })
        let capsule = try XCTUnwrap(item.view as? NSHostingView<HelmToolbarActionsCapsule>)
        let entry = try XCTUnwrap(capsule.rootView.model.declared.first { $0.id == "follow" })
        XCTAssertEqual(entry.toggleFace, face)
        XCTAssertEqual(entry.kind, .toggle(isOn: true))
    }

    /// **The value VoiceOver reads is the state, in words.** The accessibility
    /// tree of a hosted view is empty under the suite (`HelmAccordionTests`'
    /// own header), so the value cannot be read back from the drawn control;
    /// what can be held is the two halves of the wire. The face answers the word
    /// for each state, and the capsule's toggle reads it from the face — with
    /// its own `.isSelected` trait left to the toggles that have no face, since
    /// «selected» beside «Following» says it twice.
    func testTheFaceSaysFollowingOrNotAndTheCapsuleReadsItFromTheFace() throws {
        XCTAssertEqual(face.value(isOn: true), "Following")
        XCTAssertEqual(face.value(isOn: false), "Not following")
        XCTAssertEqual(face.symbol(isOn: true, on: "eye"), "eye")
        XCTAssertEqual(face.symbol(isOn: false, on: "eye"), "eye.slash")

        let source = try RepoSource.text(of: "Sources/HelmUI/DesignSystem/HelmToolbarActions.swift")
        XCTAssertTrue(source.contains(".accessibilityValue(face.value(isOn: isOn))"), """
            the capsule's toggle with a face does not set its accessibility value from the face
            """)
        XCTAssertTrue(source.contains("glyph(entry, symbol: face.symbol(isOn: isOn, on: entry.symbol))"), """
            the capsule's toggle with a face does not draw the face's glyph for the state
            """)
    }
}
