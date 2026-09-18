import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// The colours a module can be, measured rather than chosen.
///
/// Two thresholds, and the system palette fails one of them. `ModuleCategory`
/// handed plates `.orange`, `.teal` and `.green`, which measure **2,31 / 2,16 /
/// 2,22** against the white glyph drawn on them — the same defect `HelmSignal`
/// exists to close, one class of colour over. And `.red` against `.pink` sits
/// 0,107 apart, which is two modules the eye cannot separate at 22 pt.
final class ModuleTintTests: XCTestCase {

    // MARK: - The white glyph has to read

    /// `HelmIconPlate` draws the symbol in white on the tint, so the tint
    /// answers to the 3:1 floor for a mark that carries meaning. The gradient
    /// darkens downward, so the top of the plate is the worst case and the raw
    /// value is what must clear it.
    func testEveryTintCarriesAWhiteGlyph() {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            for tint in ModuleTint.allCases {
                let ratio = whiteRatio(tint.colour(increased: false), in: appearance)
                XCTAssertGreaterThanOrEqual(
                    ratio, 3.0,
                    "\(tint) in \(appearance.rawValue) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    // MARK: - One colour per module

    /// Far enough apart to be told apart. The number is the point of the whole
    /// change: a colour four modules share distinguishes nothing.
    func testEveryPairIsDistinguishable() {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            let all = ModuleTint.allCases
            for i in all.indices {
                for j in all.indices where j > i {
                    let d = distance(all[i].colour(increased: false),
                                     all[j].colour(increased: false), in: appearance)
                    XCTAssertGreaterThan(
                        d, 0.15,
                        "\(all[i]) and \(all[j]) in \(appearance.rawValue) differ by "
                        + String(format: "%.3f", d))
                }
            }
        }
    }

    /// One case per module, so a module added later cannot quietly share.
    func testThereIsOneTintPerModule() {
        XCTAssertEqual(ModuleTint.allCases.count, 10)
    }

    // MARK: - And the same two questions under Increase Contrast

    /// Apple asks a custom colour for an increased-contrast option "that
    /// provides a significantly higher amount of visual differentiation". The
    /// higher floor is 4,5:1 for the white glyph rather than 3:1, and it is the
    /// same solve — the smallest blend toward black that reaches it.
    func testEveryIncreasedTintCarriesAWhiteGlyphAtTheHigherFloor() {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            for tint in ModuleTint.allCases {
                let ratio = whiteRatio(tint.colour(increased: true), in: appearance)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    "\(tint) in \(appearance.rawValue) is \(String(format: "%.2f", ratio)):1")
            }
        }
    }

    /// Re-measured rather than inherited: blending ten colours toward one point
    /// moves them toward each other, so the set that clears the higher contrast
    /// floor has to be shown to still be ten distinguishable colours.
    func testEveryIncreasedPairIsStillDistinguishable() {
        for appearance: NSAppearance.Name in [.aqua, .darkAqua] {
            let all = ModuleTint.allCases
            for i in all.indices {
                for j in all.indices where j > i {
                    let d = distance(all[i].colour(increased: true),
                                     all[j].colour(increased: true), in: appearance)
                    XCTAssertGreaterThan(
                        d, 0.15,
                        "\(all[i]) and \(all[j]) in \(appearance.rawValue) differ by "
                        + String(format: "%.3f", d))
                }
            }
        }
    }

    /// A tint already past the higher floor keeps its ordinary value, and one
    /// that was not moves. Without this the two sets could be identical and
    /// every assertion above would still pass.
    func testTheIncreasedSetMovesTheTintsThatNeededIt() {
        let moved = ModuleTint.allCases.filter {
            distance($0.colour(increased: false), $0.colour(increased: true), in: .aqua) > 0.001
        }
        XCTAssertTrue(moved.contains(.duplicates), "duplicates read 3,03:1 and had to move")
        XCTAssertFalse(moved.contains(.hosts), "hosts reads 5,91:1 and owes no second value")
        XCTAssertGreaterThanOrEqual(moved.count, 7)
    }

    // MARK: - Measuring

    /// Resolved inside one appearance rather than whichever is current.
    /// `NSColor(Color)` returns a dynamic colour, and resolving it outside the
    /// block measures whatever the environment happened to hold — the trap
    /// `HelmMetricStrip.legible` documents after being caught by it.
    private func resolved(_ colour: Color, in appearance: NSAppearance.Name) -> NSColor {
        var out = NSColor.black
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            out = NSColor(colour).usingColorSpace(.sRGB) ?? .black
        }
        return out
    }

    private func whiteRatio(_ colour: Color, in appearance: NSAppearance.Name) -> Double {
        let c = resolved(colour, in: appearance)
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(c.redComponent)
                      + 0.7152 * channel(c.greenComponent)
                      + 0.0722 * channel(c.blueComponent)
        return (1.0 + 0.05) / (luminance + 0.05)
    }

    private func distance(_ a: Color, _ b: Color, in appearance: NSAppearance.Name) -> Double {
        let (x, y) = (resolved(a, in: appearance), resolved(b, in: appearance))
        let dr = Double(x.redComponent - y.redComponent)
        let dg = Double(x.greenComponent - y.greenComponent)
        let db = Double(x.blueComponent - y.blueComponent)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
