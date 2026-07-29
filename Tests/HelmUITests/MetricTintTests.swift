import XCTest
import AppKit
import SwiftUI
@testable import HelmUI

/// The strip darkens a system tint so the figure stays legible in light
/// appearance. How far it darkens it is a contrast decision, so it is measured.
///
/// The blend was 0.30, chosen against `.tertiary` rather than against a floor:
/// green 3.85:1, orange 3.99:1, teal 3.76:1 at 16 pt medium, which is body text
/// by every threshold there is. This is the same defect `HelmSignal` was built
/// to end, surviving in the one place that had solved it first.
final class MetricTintTests: XCTestCase {

    /// 16 pt medium is not large text: the body floor applies.
    private static let floor = 4.5

    /// The tints a strip is actually given (Keep Awake, VPN and Layout pass
    /// green and orange), plus teal, which the blend treats worst of the three.
    private static let tints: [(String, Color)] = [("green", .green), ("orange", .orange),
                                                   ("teal", .teal)]

    func testEveryStripTintClearsTheBodyFloorInLight() {
        for (name, tint) in Self.tints {
            let measured = ratio(resolved(HelmMetricStrip.legible(tint, in: .light), .aqua),
                                 windowBackground(.aqua))
            XCTAssertGreaterThanOrEqual(
                measured, Self.floor,
                "\(name) figure on the window in light: \(String(format: "%.2f", measured)):1")
        }
    }

    /// The numbers written into `legible`'s comment, measured. A comment
    /// carrying a ratio is a claim, and this is the only thing that keeps it
    /// one — the previous one said 2.03:1 for a green that measures 2.22:1.
    func testTheDocumentedRatiosAreTheOnesItMeasures() {
        let documented = ["green": 4.80, "orange": 4.97, "teal": 4.69]
        for (name, tint) in Self.tints {
            let measured = ratio(resolved(HelmMetricStrip.legible(tint, in: .light), .aqua),
                                 windowBackground(.aqua))
            XCTAssertEqual(measured, documented[name]!, accuracy: 0.01,
                           "\(name) measures \(String(format: "%.2f", measured)):1 — "
                           + "update the comment in `legible` with it")
        }
    }

    /// The one that fails by luck rather than by measurement: `legible` reads
    /// the appearance from the SwiftUI environment and `NSColor(Color)` reads it
    /// from `NSAppearance.current`, and for a while those were two different
    /// answers — the blend darkened dark mode's brighter green and called the
    /// result a light-mode colour, landing at 4.43:1 while claiming 4.80:1.
    /// Whatever appearance this process is in, the answer must be the same.
    func testTheAnswerDoesNotDependOnTheAmbientAppearance() {
        for (name, tint) in Self.tints {
            var underDark: Color = .clear
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                underDark = HelmMetricStrip.legible(tint, in: .light)
            }
            var underLight: Color = .clear
            NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
                underLight = HelmMetricStrip.legible(tint, in: .light)
            }
            XCTAssertEqual(resolved(underDark, .aqua), resolved(underLight, .aqua),
                           "\(name) darkened a different colour depending on "
                           + "which appearance happened to be current")
        }
    }

    /// The blend must not "fix" dark, where the system palette already passes
    /// and is the palette people recognise.
    func testDarkKeepsTheSystemTint() {
        for (name, tint) in Self.tints {
            let mine = resolved(HelmMetricStrip.legible(tint, in: .dark), .darkAqua)
            let theirs = resolved(tint, .darkAqua)
            XCTAssertEqual(Double(mine.redComponent), Double(theirs.redComponent), accuracy: 0.001, name)
            XCTAssertEqual(Double(mine.greenComponent), Double(theirs.greenComponent), accuracy: 0.001, name)
            XCTAssertEqual(Double(mine.blueComponent), Double(theirs.blueComponent), accuracy: 0.001, name)
        }
    }

    /// The measurement that makes the first test mean something: undarkened,
    /// these tints are under the floor, so it is not passing on leniency.
    func testTheUndarkenedTintsWouldNotPass() {
        for (name, tint) in Self.tints {
            let measured = ratio(resolved(tint, .aqua), windowBackground(.aqua))
            XCTAssertLessThan(measured, Self.floor,
                              "\(name) no longer needs darkening: \(String(format: "%.2f", measured)):1")
        }
    }

    // MARK: - Measurement

    private func luminance(_ c: NSColor) -> Double {
        let s = c.usingColorSpace(.sRGB)!
        func linear(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(s.redComponent)
             + 0.7152 * linear(s.greenComponent)
             + 0.0722 * linear(s.blueComponent)
    }

    private func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> NSColor {
        var out: NSColor = .clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB)!
        }
        return out
    }

    private func windowBackground(_ appearance: NSAppearance.Name) -> NSColor {
        var out: NSColor = .clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            out = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
        }
        return out
    }
}
