import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **A recessed text colour clears its threshold on every surface it lands on.**
///
/// `HelmText` exists because that is not a judgement anybody makes by eye, and
/// its three opacities each carried the measurement in a doc comment — *"3.54:1
/// / 4.63:1"* — with nothing under it. Prose is not a guard: `faint` was 3.54:1
/// in light against a body floor of 4.5, written down as such, and shipped for
/// months because writing the number is not the same as failing on it.
///
/// `SignalColourContrastTests` next door measures the *signal* colours, which
/// are opaque. These are not: the ink is `labelColor` at an opacity, so the
/// measurement has to composite it onto the surface first — see `Contrast`,
/// which says what happens when it does not.
///
/// **Four surfaces, because a page has four.** The window, a control area, and
/// then the two fills Helm puts on top of them: a card (`cardFill`) and a well
/// inside a card (`wellFill`). In light those *darken* the ground under dark ink
/// and in dark they lighten it under light ink, so both are stricter than the
/// bare background in both appearances — which is the rule v2 carried over from
/// the mockups: ink is measured against the darkest surface it stands on.
///
/// `HelmSurface.onPanelFill` is deliberately not among them. It is one capsule
/// on a *panel* tile, and the panel sits on glass — measuring it against
/// `windowBackgroundColor` would be a number about a pairing the app never
/// draws. Measured for the record while this landed: over the window it takes
/// `quiet` to 4.46:1 and `faint` to 4.59:1.
final class RecessedTextIsReadableTests: XCTestCase {

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    /// The ground a recessed word can find itself on, worst last.
    private func surfaces(_ appearance: NSAppearance.Name) -> [(String, NSColor)] {
        var out: [(String, NSColor)] = []
        for (name, keyPath) in [("window", \NSColor.Type.windowBackgroundColor),
                                ("control", \NSColor.Type.controlBackgroundColor)] {
            let ground = Contrast.system(keyPath, appearance)
            out.append((name, ground))
            out.append(("\(name) + card",
                        Contrast.over(Contrast.resolved(HelmSurface.cardFill, appearance), ground)))
            out.append(("\(name) + well",
                        Contrast.over(Contrast.resolved(HelmSurface.wellFill, appearance), ground)))
        }
        return out
    }

    private func measure(_ ink: Color, on surface: NSColor,
                         _ appearance: NSAppearance.Name) -> Double {
        let resolved = Contrast.resolved(ink, appearance)
        return Contrast.ratio(Contrast.over(resolved, surface), surface)
    }

    private func assertClears(_ ink: Color, _ name: String, _ floor: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        for appearance in Self.appearances {
            for (surface, ground) in surfaces(appearance) {
                let measured = measure(ink, on: ground, appearance)
                XCTAssertGreaterThanOrEqual(
                    measured, floor,
                    "\(name) on \(surface) in \(appearance.rawValue): "
                    + "\(String(format: "%.2f", measured)):1 against a floor of \(floor):1",
                    file: file, line: line)
            }
        }
    }

    /// Captions, and the one that was under its floor: 3.54:1 light at 0.55,
    /// 4.77:1 at 0.65. `Scripts/design/contrast.swift` solves the floor at
    /// opacity 0.631, so 0.65 is the ladder step above what the threshold needs.
    func testFaintClearsTheBodyFloor() {
        assertClears(HelmText.faint, "faint", Contrast.bodyFloor)
    }

    /// Secondary copy inside cards and rows: 4.62:1 light, 5.78:1 dark, and
    /// 4.52:1 on the worst surface of the four.
    func testQuietClearsTheBodyFloor() {
        assertClears(HelmText.quiet, "quiet", Contrast.bodyFloor)
    }

    /// A chevron is a mark, so it answers to 3:1 rather than to nothing.
    func testSeparatorClearsTheMarkFloor() {
        assertClears(HelmText.separator, "separator", Contrast.markFloor)
    }

    // MARK: - The measurement itself

    /// Without the composite every opacity passes: the ink is still `labelColor`
    /// underneath, and that measures 14.94:1 against the window in light. So a
    /// reading that skipped it would have blessed 0.55 — and 0.20.
    func testTheMeasurementCompositesTheInkOntoTheSurface() {
        let window = Contrast.system(\NSColor.Type.windowBackgroundColor, .aqua)
        let ghost = Contrast.resolved(Color.primary.opacity(0.20), .aqua)
        XCTAssertGreaterThan(Contrast.ratio(ghost, window), Contrast.bodyFloor,
                             "read raw, a 20% ink clears the body floor — "
                             + "which is why the raw reading is not the measurement")
        XCTAssertLessThan(Contrast.ratio(Contrast.over(ghost, window), window), 2.0,
                          "composited, a 20% ink is barely visible and must measure so")
    }

    /// And the four surfaces are four. A card fill that resolved to nothing
    /// would make three of them one, and the strictest of them the same reading
    /// as the loosest.
    func testTheSurfacesAreDistinctGrounds() {
        for appearance in Self.appearances {
            let measured = surfaces(appearance).map { Contrast.luminance($0.1) }
            let window = measured[0], card = measured[1], well = measured[2]
            XCTAssertNotEqual(window, card, "the card fill landed on nothing")
            XCTAssertGreaterThan(abs(well - window), abs(card - window),
                                 "a well must be further from the window than a card is")
        }
    }

    /// The rule objects to the shape it was written for. A fixture rather than
    /// the tree, so it goes on saying this after the tokens are right.
    func testTheRuleRejectsAnOpacityChosenByEye() {
        var failures = 0
        for appearance in Self.appearances {
            for (_, ground) in surfaces(appearance) where
                measure(Color.primary.opacity(0.35), on: ground, appearance) < Contrast.bodyFloor {
                failures += 1
            }
        }
        XCTAssertEqual(failures, 12, "0.35 is under the body floor on every surface in both "
                                     + "appearances, and must be reported by all twelve readings")
    }
}
