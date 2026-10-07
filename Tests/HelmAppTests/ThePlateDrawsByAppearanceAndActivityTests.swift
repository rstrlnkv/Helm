import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The plate behind a group of a bar's controls draws by the look it is handed and by whether its window is
/// active: Liquid Glass while active under the glass look, otherwise a tint of `HelmSurface.barPlate`
/// that dims as one unit whenever the window is inactive.**
///
/// No window is ordered anywhere; the plate belongs to no window and its appearance is named on the
/// view, so the answer does not depend on this Mac's setting. What the rows read back:
/// - which `NSGlassEffectView`s are among the plate's subviews, and where;
/// - the layer's fill colour, resolved in the plate's own appearance, and its `alphaValue`;
/// - that the content view stays one instance and the last subview through every edge;
/// - that the file asks no stored setting.
///
/// **Not seen on a screen:** the plate with a control on it. Measured on 27.2 in a standalone bench app's
/// window, key and then not key, in the dark appearance, and not on this plate: an `.extraLarge` stock segmented control outside a
/// toolbar draws a capsule track of its own; a bare `NSGlassEffectView` on the window's background loses its rim
/// highlight by itself when its window is neither key nor main; and the brightest pixel of an unselected label of
/// a `.regular` stock segmented control read 229.3 with the window key and 229.3 with it not key, so a stock
/// control does not dim its own ink in an inactive window, only its selection capsule turns grey. That is why an
/// inactive plate dims by the name zone's number under both looks. Assumed: that the flat cell's fixed inks do not
/// dim by themselves in an inactive window, and that a fill at `barPlate` is what AppKit's inactive platter looks
/// like; unseen: how the dimmed glass plate reads beside the name. The rows prove what the plate's views and layer
/// hold, not what a person sees.
@MainActor
final class ThePlateDrawsByAppearanceAndActivityTests: XCTestCase {

    private struct State: CustomStringConvertible {
        let look: HelmBarAppearance
        let active: Bool
        let transparent: Bool
        let appearance: NSAppearance.Name
        var dark: Bool { appearance == .darkAqua }
        var description: String {
            "\(look) \(active ? "active" : "inactive"), transparent titlebar \(transparent), \(appearance.rawValue)"
        }
    }

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func states() -> [State] {
        var all: [State] = []
        for name in Self.appearances {
            for transparent in [true, false] {
                for look in HelmBarAppearance.allCases {
                    for active in [true, false] {
                        all.append(State(look: look, active: active, transparent: transparent, appearance: name))
                    }
                }
            }
        }
        return all
    }

    private func plate(_ state: State, size: NSSize = NSSize(width: 120, height: 36)) -> ShellBarPlate {
        let plate = ShellBarPlate(appearance: state.look, isActive: state.active,
                                  titlebarIsTransparent: state.transparent)
        plate.frame = NSRect(origin: .zero, size: size)
        plate.appearance = NSAppearance(named: state.appearance)
        plate.needsLayout = true
        plate.layoutSubtreeIfNeeded()
        return plate
    }

    private func glasses(in plate: NSView) -> [NSGlassEffectView] {
        plate.subviews.compactMap { $0 as? NSGlassEffectView }
    }

    /// The fill the plate is expected to hold, resolved by the same expression in the same appearance.
    private func expectedFill(in name: NSAppearance.Name) throws -> NSColor {
        var resolved: CGColor?
        try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            resolved = NSColor(HelmSurface.barPlate).cgColor
        }
        let color = try XCTUnwrap(resolved.flatMap { NSColor(cgColor: $0) }?.usingColorSpace(.sRGB))
        return color
    }

    private func components(_ color: NSColor) -> [CGFloat] {
        guard let c = color.usingColorSpace(.sRGB) else { return [] }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    func testAFlatPlateDrawsNoGlassAndAGlassPlateDrawsNoTint() throws {
        // The subject happened first: in every state the plate holds a subview or a layer fill. A plate
        // that draws nothing would pass every "no glass" and "no tint" row below by drawing nothing.
        for state in states() {
            let plate = plate(state)
            let drew = !plate.subviews.isEmpty || plate.layer?.backgroundColor != nil
            XCTAssertTrue(drew, """
                the plate has no subview and no layer fill (\(state)): "no glass" was true because \
                nothing was drawn
                """)
        }

        for state in states() {
            let plate = plate(state)
            let layer = try XCTUnwrap(plate.layer, "\(state): the plate has no layer")
            XCTAssertEqual(layer.cornerCurve, .continuous, "\(state): corner curve")
            XCTAssertEqual(layer.cornerRadius, plate.bounds.height / 2, accuracy: 0.001,
                           "\(state): corner radius is not half the height")
            XCTAssertFalse(layer.masksToBounds, "\(state): the plate clips")

            let glass = glasses(in: plate)
            let tinted = state.look == .flat || !state.active
            if tinted {
                XCTAssertEqual(glass.count, 0, "\(state): a glass view is drawn where the tint belongs")
                let fill = try XCTUnwrap(layer.backgroundColor.flatMap { NSColor(cgColor: $0) },
                                         "\(state): no layer fill")
                let want = try expectedFill(in: state.appearance)
                for (a, b) in zip(components(fill), components(want)) {
                    XCTAssertEqual(a, b, accuracy: 0.002, "\(state): fill is not barPlate resolved in its appearance")
                }
                let alpha = components(fill)[3]
                XCTAssertGreaterThan(alpha, 0, "\(state): the fill is invisible")
                XCTAssertLessThan(alpha, 0.1, "\(state): the fill is a heavy tint, not a plate")
            } else {
                XCTAssertEqual(glass.count, 1, "\(state): glass views among subviews: \(glass.count)")
                XCTAssertTrue(plate.subviews.first === glass.first, "\(state): the glass is not at subviews[0]")
                XCTAssertNil(layer.backgroundColor, "\(state): a tint is drawn on top of the glass")
                if let view = glass.first {
                    XCTAssertEqual(view.style, .regular, "\(state): glass style")
                    XCTAssertEqual(view.frame, plate.bounds, "\(state): glass frame")
                    XCTAssertEqual(view.cornerRadius, plate.bounds.height / 2, accuracy: 0.001,
                                   "\(state): glass corner radius")
                }
            }

            let dimmed = !state.active
            let wantAlpha = dimmed
                ? CGFloat(helmNameZoneInactiveOpacity(dark: state.dark, titlebarIsTransparent: state.transparent))
                : 1
            XCTAssertEqual(plate.alphaValue, wantAlpha, accuracy: 0.0001, "\(state): alphaValue")
        }

        // The tint follows the appearance: black ink on light, white on dark.
        let light = components(try expectedFill(in: .aqua))
        let dark = components(try expectedFill(in: .darkAqua))
        XCTAssertNotEqual(light[0], dark[0], accuracy: 0.1, "barPlate resolves to one colour in both appearances")
        let flatLight = plate(State(look: .flat, active: true, transparent: true, appearance: .aqua))
        let flatDark = plate(State(look: .flat, active: true, transparent: true, appearance: .darkAqua))
        let lightRed = components(try XCTUnwrap(flatLight.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }))[0]
        let darkRed = components(try XCTUnwrap(flatDark.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }))[0]
        XCTAssertNotEqual(lightRed, darkRed, accuracy: 0.1, "the plate's fill did not follow its appearance")
    }

    func testAnEdgeSwapsTheDrawingAndKeepsWhatThePlateHolds() throws {
        let plate = plate(State(look: .flat, active: true, transparent: true, appearance: .aqua))
        let content = NSView()
        plate.content = content

        // The subject happened first: the content is in the plate.
        XCTAssertTrue(plate.subviews.contains { $0 === content }, """
            content was never added: "still last" held of an empty subview list
            """)

        func check(_ step: String, glassCount: Int) {
            plate.needsLayout = true
            plate.layoutSubtreeIfNeeded()
            XCTAssertTrue(plate.content === content, "\(step): the content instance changed")
            XCTAssertTrue(plate.subviews.last === content, "\(step): the content is not the last subview")
            XCTAssertTrue(content.superview === plate, "\(step): the content was reparented")
            XCTAssertEqual(content.frame, plate.bounds, "\(step): the content is not framed to the plate")
            XCTAssertEqual(glasses(in: plate).count, glassCount, "\(step): glass views")
            if glassCount == 1 {
                XCTAssertTrue(plate.subviews.first is NSGlassEffectView, "\(step): the glass is not at subviews[0]")
            }
        }

        check("flat active", glassCount: 0)
        plate.barAppearance = .liquidGlass
        check("glass active", glassCount: 1)
        plate.isActive = false
        check("glass inactive", glassCount: 0)
        XCTAssertLessThan(plate.alphaValue, 1, "glass inactive does not dim: the ink stays at full strength on the fill")
        plate.isActive = true
        check("glass active again", glassCount: 1)
        XCTAssertEqual(plate.alphaValue, 1, accuracy: 0.0001, "glass active after inactive does not return to 1")
        plate.barAppearance = .flat
        check("flat active again", glassCount: 0)
        plate.isActive = false
        check("flat inactive", glassCount: 0)
        XCTAssertLessThan(plate.alphaValue, 1, "flat inactive does not dim")
        plate.isActive = true
        XCTAssertEqual(plate.alphaValue, 1, accuracy: 0.0001, "flat active after inactive does not return to 1")

        // The corner is computed from the height, not a literal.
        plate.barAppearance = .liquidGlass
        plate.frame = NSRect(x: 0, y: 0, width: 200, height: 44)
        check("glass resized", glassCount: 1)
        XCTAssertEqual(plate.layer?.cornerRadius ?? -1, 22, accuracy: 0.001, "layer corner after resize")
        XCTAssertEqual(glasses(in: plate).first?.cornerRadius ?? -1, 22, accuracy: 0.001, "glass corner after resize")
        XCTAssertEqual(glasses(in: plate).first?.frame, plate.bounds, "glass frame after resize")
    }

    /// The inputs the first two rows do not feed: no size, a swapped and a removed content, values set to
    /// what they already hold, and an appearance that changes after the plate was built.
    func testAZeroPlateASwappedContentARepeatedValueAndALateAppearance() throws {
        // Zero size: a glass plate still holds one glass, with no corner and no frame to speak of.
        let zero = plate(State(look: .liquidGlass, active: true, transparent: true, appearance: .aqua),
                         size: .zero)
        let zeroContent = NSView()
        zero.content = zeroContent
        zero.layoutSubtreeIfNeeded()
        XCTAssertEqual(glasses(in: zero).count, 1, "zero size: glass views")
        XCTAssertEqual(zero.layer?.cornerRadius ?? -1, 0, accuracy: 0.001, "zero size: corner radius")
        XCTAssertEqual(zeroContent.frame, .zero, "zero size: content frame")
        XCTAssertFalse(zero.layer?.masksToBounds ?? true, "zero size: the plate clips")

        // Content swapped, then removed, under the glass: the glass stays first, the new one last.
        let swapped = plate(State(look: .liquidGlass, active: true, transparent: true, appearance: .aqua))
        let first = NSView()
        let second = NSView()
        swapped.content = first
        let glass = try XCTUnwrap(glasses(in: swapped).first, "no glass to start from")
        swapped.content = second
        swapped.layoutSubtreeIfNeeded()
        XCTAssertNil(first.superview, "the replaced content is still in the plate")
        XCTAssertTrue(swapped.subviews.last === second, "the new content is not the last subview")
        XCTAssertTrue(swapped.subviews.first === glass, "the glass moved when the content was swapped")
        XCTAssertEqual(second.frame, swapped.bounds, "the new content is not framed")
        swapped.content = nil
        swapped.layoutSubtreeIfNeeded()
        XCTAssertNil(second.superview, "the removed content is still in the plate")
        XCTAssertEqual(swapped.subviews.count, 1, "subviews after the content was removed")
        XCTAssertTrue(swapped.subviews.first === glass, "the glass is gone with the content")

        // Values set to what they already hold change nothing: the same glass instance stays.
        swapped.isActive = true
        swapped.barAppearance = .liquidGlass
        XCTAssertTrue(glasses(in: swapped).first === glass, "a repeated value rebuilt the glass")
        XCTAssertEqual(glasses(in: swapped).count, 1, "a repeated value added a glass")

        // The appearance changes after the plate was built: the fill and the dim follow it.
        let late = plate(State(look: .flat, active: false, transparent: true, appearance: .aqua))
        let lightFill = components(try XCTUnwrap(late.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }))
        XCTAssertEqual(late.alphaValue,
                       CGFloat(helmNameZoneInactiveOpacity(dark: false, titlebarIsTransparent: true)),
                       accuracy: 0.0001, "light dim before the change")
        late.appearance = NSAppearance(named: .darkAqua)
        late.layoutSubtreeIfNeeded()
        let darkFill = components(try XCTUnwrap(late.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }))
        let want = components(try expectedFill(in: .darkAqua))
        for (a, b) in zip(darkFill, want) {
            XCTAssertEqual(a, b, accuracy: 0.002, "the fill did not follow a later appearance change")
        }
        XCTAssertNotEqual(lightFill[0], darkFill[0], accuracy: 0.1, "the fill is the same in both appearances")
        XCTAssertEqual(late.alphaValue,
                       CGFloat(helmNameZoneInactiveOpacity(dark: true, titlebarIsTransparent: true)),
                       accuracy: 0.0001, "the dim did not follow a later appearance change")
    }

    func testThePlateAsksNoSetting() throws {
        let text = (try? RepoSource.text(of: "Sources/HelmApp/ShellBarPlate.swift")) ?? ""
        XCTAssertFalse(text.isEmpty, "the file read back empty")
        XCTAssertFalse(SwiftSource.code(text).contains("AppSettings"),
                       "the plate reads a stored setting: the look and the activity are handed in")
    }
}
