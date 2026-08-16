import AppKit
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// Follow lost its word to keep the filter row on one line, and a word was the
/// only thing a toggle can afford to lose. The state cannot go with it: a
/// glyph-only control whose on and off draw the same pixels tells its state to
/// the tooltip and to nobody's eyes.
///
/// So the two states are rendered and compared, in both appearances — a reading
/// has a screen — and each side asserts it drew anything at all first, because a
/// difference between two empty bitmaps is zero and would pass a broken render
/// for free.
@MainActor
final class TheFollowGlyphShowsItsStateTests: XCTestCase {

    private var mounted: [MountedRender] = []

    override func tearDown() {
        mounted.forEach { $0.drop() }
        mounted = []
        super.tearDown()
    }

    private func ink(on: Bool, in appearance: NSAppearance.Name) throws -> Int {
        let render = MountedRender(LogFollowToggle(isOn: .constant(on)).padding(8),
                                   width: 60, height: 50, appearance: appearance)
        mounted.append(render)
        render.settle()
        return try XCTUnwrap(render.settledInk(),
                             "the follow glyph never settled — the reading is a guess")
    }

    func testTheOnStateIsVisibleWithoutTheWord() throws {
        for appearance in RenderedInk.bothAppearances {
            let off = try ink(on: false, in: appearance)
            let on = try ink(on: true, in: appearance)
            let screen = RenderedInk.label(of: appearance)

            XCTAssertGreaterThan(off, 0, "the follow glyph drew nothing at all in \(screen) — "
                + "the comparison below is then between two blanks")
            // A fifth of the quieter state: antialiasing wobbles a reading by
            // 14 % of itself at most (RenderedInk's own measurement), so a
            // fifth is over the noise while any real fill clears it by times,
            // not percents.
            XCTAssertGreaterThan(abs(on - off), min(on, off) / 5, """
                the follow glyph reads \(on) ink pressed and \(off) released in \(screen) — \
                the two states draw the same, so with the word gone nothing on screen says \
                whether the log is being followed
                """)
        }
    }
}
