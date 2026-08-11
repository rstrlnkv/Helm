import XCTest
import AppKit
import HelmTestSupport
import SwiftUI
@testable import HelmUI

/// The colours that mean something, measured against the surfaces they land on.
///
/// `HelmText` was built because a recessed text colour is a contrast decision
/// nobody can make by eye, and it was never generalised past text. The warning
/// marks kept using `Color.orange`, `.green` and `.red` straight from the
/// system palette — which is tuned for dark, where all three are comfortable,
/// and fails in light. Measured on this machine before the token existed:
///
///     light   orange 2.31:1   green 2.22:1   red 3.57:1
///     dark    orange 7.47:1   green 8.25:1   red 4.86:1
///
/// 4.5:1 is the body-text floor and 3:1 the floor for a mark that carries
/// meaning. So in light appearance the app's most important warning — the icon
/// on every "needs a permission" banner — was its least visible mark, and
/// `HotkeyRecorder`'s "this shortcut does nothing" note was real body text at
/// 2.31:1.
///
/// One token, one threshold: these are used for icons *and* for body text, so
/// they answer to the stricter of the two everywhere rather than to whichever
/// one the current call site happens to need.
final class SignalColourContrastTests: XCTestCase {

    private static let bodyTextFloor = Contrast.bodyFloor

    /// The arithmetic, and the two traps in it, are `Contrast`'s — in
    /// `HelmTestSupport`, where three more test files were spelling the same four
    /// functions out. These tokens are opaque, so nothing here composites.
    private func ratio(_ a: NSColor, _ b: NSColor) -> Double { Contrast.ratio(a, b) }

    private func resolved(_ color: Color, _ appearance: NSAppearance.Name) -> NSColor {
        Contrast.resolved(color, appearance)
    }

    private func background(_ keyPath: KeyPath<NSColor.Type, NSColor>,
                            _ appearance: NSAppearance.Name) -> NSColor {
        Contrast.system(keyPath, appearance)
    }

    private func assertReadable(_ color: Color, _ name: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let ink = resolved(color, appearance)
            for (surface, keyPath) in [("window", \NSColor.Type.windowBackgroundColor),
                                       ("control", \NSColor.Type.controlBackgroundColor)] {
                let measured = ratio(ink, background(keyPath, appearance))
                XCTAssertGreaterThanOrEqual(
                    measured, Self.bodyTextFloor,
                    "\(name) on \(surface) in \(appearance.rawValue): "
                    + "\(String(format: "%.2f", measured)):1",
                    file: file, line: line)
            }
        }
    }

    func testTheWarningTokenIsReadableInBothAppearances() {
        assertReadable(HelmSignal.warning, "warning")
    }

    func testTheSuccessTokenIsReadableInBothAppearances() {
        assertReadable(HelmSignal.success, "success")
    }

    func testTheDangerTokenIsReadableInBothAppearances() {
        assertReadable(HelmSignal.danger, "danger")
    }

    /// The measurement that makes the three above mean something: the raw
    /// system colours these replace do *not* clear the floor, so the assertions
    /// are not passing on the strength of a lenient threshold.
    func testTheRawSystemColoursWouldNotPass() {
        var failures = 0
        for (name, raw) in [("orange", Color.orange), ("green", Color.green), ("red", Color.red)] {
            let ink = resolved(raw, .aqua)
            let measured = ratio(ink, background(\NSColor.Type.windowBackgroundColor, .aqua))
            if measured < Self.bodyTextFloor { failures += 1 }
            XCTAssertLessThan(measured, Self.bodyTextFloor,
                              "\(name) no longer needs the token: \(String(format: "%.2f", measured)):1")
        }
        XCTAssertEqual(failures, 3, "all three system colours are why this token exists")
    }

    /// In dark appearance the system colours are already fine, so the token
    /// must not "fix" what was not broken — the palette macOS ships is the one
    /// people recognise.
    func testDarkAppearanceKeepsTheSystemColours() {
        for (name, token, raw) in [("warning", HelmSignal.warning, Color.orange),
                                   ("success", HelmSignal.success, Color.green),
                                   ("danger", HelmSignal.danger, Color.red)] {
            let mine = resolved(token, .darkAqua), theirs = resolved(raw, .darkAqua)
            // Component-wise: two sRGB colours with identical channels can be
            // unequal as objects — one carries an HDR headroom marker and the
            // other does not, which is not a difference anybody can see.
            XCTAssertEqual(Double(mine.redComponent), Double(theirs.redComponent), accuracy: 0.001, name)
            XCTAssertEqual(Double(mine.greenComponent), Double(theirs.greenComponent), accuracy: 0.001, name)
            XCTAssertEqual(Double(mine.blueComponent), Double(theirs.blueComponent), accuracy: 0.001, name)
        }
    }
}
