import XCTest
import AppKit
@testable import Module_Layout_UI
@testable import Module_Layout_Engine
import HelmUI

/// «Размер» decides how tall the menu-bar badge is. «Вид» must not.
///
/// **It used to decide it more.** Measured before this guard: at 15 pt asked
/// for, «Буквы» drew 15, «Буквы на плашке» and «Буквы в рамке» drew 17, and
/// «Флаг, системный» drew 19 — while the whole Size range is 11 → 15. So one
/// style at the smallest size was taller than any style at the largest, and the
/// size picker was a suggestion. `MenuBarIconSize` had already been cut from
/// five sizes to three because the extremes «made Helm look wrong beside
/// everything else in the bar»; Style was quietly undoing that.
///
/// Two causes, both arithmetic rather than taste: a framed badge added 2 for a
/// stroke its own `insetBy(0.5)` already keeps inside, and the emoji took the
/// glyph's *line height* — which is not its point size — as the canvas.
@MainActor
final class SizeIsTheOnlyThingThatChangesTheHeightTests: XCTestCase {

    func testEveryStyleIsExactlyTheHeightThatWasAskedFor() {
        for size in MenuBarIconSize.allCases {
            for style in BadgeStyle.allCases {
                let image = BadgeImage.make(label: "RU", region: "RU",
                                            style: style, points: size.points)
                XCTAssertEqual(image.size.height, size.points, accuracy: 0.01,
                               "\(style.rawValue) at \(size.rawValue): asked for "
                               + "\(size.points) pt and drew \(image.size.height). A style that "
                               + "moves the badge as far as the size picker does makes the size "
                               + "picker a suggestion.")
            }
        }
    }

    /// The fallback path too: a layout that names no country never reaches the
    /// flag drawing at all, and that branch has its own canvas.
    func testAFlagWithNoCountryIsTheHeightThatWasAskedFor() {
        for size in MenuBarIconSize.allCases {
            for style in [BadgeStyle.flagDrawn] {
                let image = BadgeImage.make(label: "RU", region: nil,
                                            style: style, points: size.points)
                XCTAssertEqual(image.size.height, size.points, accuracy: 0.01,
                               "\(style.rawValue) with no country at \(size.rawValue)")
            }
        }
    }

    /// **`flagEmoji` is gone**, and the test that lived here went with it. It
    /// asserted that the two flag styles fell back to the *same* drawing — they
    /// differed, 24.0 × 15.0 against 32.4 × 17.0, until 2026-08-30 — because
    /// the page's note under both of them promised «letters in a frame the same
    /// size as a flag». There is one flag style now, so the promise has nothing
    /// to disagree with: «Flag» and «Flag, system» were one idea under two
    /// names, and nobody could tell them apart from the words.
}
