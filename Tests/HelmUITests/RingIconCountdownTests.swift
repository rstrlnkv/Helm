import AppKit
import XCTest
@testable import HelmUI

/// The countdown ring and the chosen shape are two separate promises, and the
/// icon has to keep both.
///
/// `make` sent every style with a countdown to one plain-arc drawing, so a
/// "double ring" became an ordinary ring the moment a timed session started —
/// and `.dot` and `.disc` were excluded from the countdown altogether, so the
/// ring somebody switched on simply never appeared.
///
/// Compared as pixels, because that is the only thing that says two icons look
/// different.
final class RingIconCountdownTests: XCTestCase {

    private func pixels(_ style: MenuBarIconStyle, progress: Double?) -> Data {
        let image = RingIcon.make(style: style, size: .small,
                                  tintToken: "orange", progress: progress)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }

    /// Every shape keeps its own look while the countdown runs.
    func testEachShapeStillLooksLikeItselfMidCountdown() {
        var seen: [MenuBarIconStyle: Data] = [:]
        for style in MenuBarIconStyle.allCases {
            let drawn = pixels(style, progress: 0.5)
            XCTAssertFalse(drawn.isEmpty, "\(style) drew nothing")
            for (other, bytes) in seen where bytes == drawn {
                XCTFail("\(style) and \(other) draw the same icon during a countdown")
            }
            seen[style] = drawn
        }
    }

    /// This used to cover `dot` and `disc`, the two shapes with no ring of
    /// their own, because the countdown setting sat beside them and had to
    /// mean something. Both shapes are gone — that awkwardness is the reason —
    /// so the claim is now about every shape there is, which is the assertion
    /// above. Kept as a note rather than deleted silently: the case it guarded
    /// was real, and reintroducing a ringless shape brings it back.

    /// A countdown that has run down is not the same picture as one that has
    /// not started: the arc is the part that moves.
    func testTheArcMovesWithTheCountdown() {
        for style in MenuBarIconStyle.allCases {
            XCTAssertNotEqual(pixels(style, progress: 0.9), pixels(style, progress: 0.1),
                              "\(style) draws the same arc at 90% and 10%")
        }
    }
}
