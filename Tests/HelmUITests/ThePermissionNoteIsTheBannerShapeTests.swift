import XCTest
import SwiftUI
import AppKit
@testable import HelmUI

/// «This needs a permission you have not given» is a statement the page has to
/// make with one verb beside it, which is exactly what `HelmBanner` is — and the
/// permission note was the last pre-v3 shape left on a settings page: a bare
/// `HStack` of a mark, `.caption` text and a button, floating on the page with no
/// field to say the three were one thing. Nine call sites in eight modules drew
/// it that way.
///
/// Measured against the banner rather than against numbers written out again
/// here. A test that spelled 13 pt and 12/8 and 13 % would pass while the two
/// shapes drifted apart, which is the same defect one layer up: the note is not
/// *like* the banner, it **is** the banner, so what is asserted is that the two
/// renders are the same pixels.
///
/// The pre-v3 shape is written out below as a fixture, so the comparison keeps
/// being able to fail after the tree is fixed — a check whose two sides are both
/// production code says nothing about which shape either of them is.
@MainActor
final class ThePermissionNoteIsTheBannerShapeTests: XCTestCase {

    private static let sentence = "Needs Accessibility, or the pointer will not move"

    /// The component under test.
    private var note: some View {
        HelmPermissionNote(text: Self.sentence, openSettings: {})
    }

    /// The shape v3 gives a statement with a verb beside it.
    private var banner: some View {
        HelmBanner(Self.sentence, symbol: "exclamationmark.circle.fill") {
            Button(L("Grant…")) { }
                .controlSize(.small)
        }
    }

    /// What the note used to be: three loose pieces, no field, 10 pt text.
    private var preV3: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HelmSignal.warning)
            Text(Self.sentence)
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Grant…")) { }
                .controlSize(.small)
        }
    }

    /// Every pixel of alpha the view draws, in a window of one fixed size.
    ///
    /// Not a band: two shapes of different heights cannot be compared through a
    /// rectangle chosen for one of them, which is the mistake
    /// `TheStopCaptionIsOnScreenOrNotTests` records making once.
    private func ink<V: View>(_ view: V) -> Int {
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            view
            Spacer(minLength: 0)
        }.frame(width: 460))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 200)
        window.layoutIfNeeded()
        for _ in 0..<20 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        defer { window.contentView = nil }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return -1 }
        var mass = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                mass += Int(data[y * rep.bytesPerRow + x * 4 + 3])
            }
        }
        return mass
    }

    func testTheNoteDrawsTheBannerAndNothingElse() throws {
        let drawn = ink(note)
        let shape = ink(banner)
        try XCTSkipIf(drawn < 0 || shape < 0, "nothing drew — no window server")
        XCTAssertGreaterThan(shape, 0, "the banner drew nothing, so the comparison is empty")

        XCTAssertEqual(drawn, shape,
                       "the permission note is not the banner: \(drawn) vs \(shape) of alpha. "
                       + "Nine call sites in eight modules draw this note, and a shape of its "
                       + "own is nine pages carrying a pre-v3 row")
    }

    /// The probe. Both sides above are production code, so the equality would
    /// hold just as well if `HelmBanner` were flattened into a bare row — this is
    /// the assertion that says the measurement can tell the two shapes apart.
    func testTheMeasurementRecognisesThePreV3Shape() throws {
        let old = ink(preV3)
        let shape = ink(banner)
        try XCTSkipIf(old < 0 || shape < 0, "nothing drew — no window server")

        XCTAssertNotEqual(old, shape,
                          "a bare HStack of a mark, quiet text and a button renders identically "
                          + "to the banner, so the test above cannot fail: \(old) vs \(shape)")
    }
}
