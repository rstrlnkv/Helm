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
                let ratio = whiteRatio(tint.colour, in: appearance)
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
                    let d = distance(all[i].colour, all[j].colour, in: appearance)
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
