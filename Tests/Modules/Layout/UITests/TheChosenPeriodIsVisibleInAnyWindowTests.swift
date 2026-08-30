import XCTest
import SwiftUI
@testable import Module_Layout_UI
@testable import Module_Layout_Engine
import HelmUI
import HelmTestSupport

/// The hero's period row shows which period it is on, in a window that is not
/// key as well as in one that is.
///
/// **This is the defect that briefly turned the row into a menu.**
/// `.borderedProminent` takes `NSColor.controlAccentColor`, and macOS greys that
/// the moment the window stops being key — so all five buttons drew identically
/// and the only surviving cue was the period's name inside the caption. The fill
/// is drawn by the module now, and an explicit colour has no key-state variant.
///
/// **The bench is the right instrument by accident and by construction.**
/// `MountedRender` holds a window that is never key, so it reproduces the
/// failing condition every time rather than needing somebody to click away from
/// the app. A row that reads correctly here reads correctly in front too.
@MainActor
final class TheChosenPeriodIsVisibleInAnyWindowTests: XCTestCase {

    private func totals() -> ConversionTotals {
        let figures = LedgerFigures(words: 25, characters: 170)
        return ConversionTotals(today: figures, week: figures, month: figures,
                                year: figures, allTime: figures, since: nil, recent: [])
    }

    /// The band the buttons occupy, in points from the top of the hero. The
    /// figure and the caption are above it, so a difference measured here is a
    /// difference in the row and not in the words.
    private let buttons = 90...117

    private func ink(_ period: ConversionPeriod) throws -> Int {
        let render = MountedRender(LayoutHero(totals: totals(), suspended: false,
                                              watching: true, period: .constant(period)),
                                   width: 700, height: 400, appearance: .aqua)
        defer { render.drop() }
        return try XCTUnwrap(render.settledInk(buttons))
    }

    /// Every period draws the same five words in the same order, so if the
    /// chosen one were not filled the row would be pixel-identical whichever
    /// period is in force. It is not.
    func testMovingTheChoiceChangesWhatIsDrawn() throws {
        let month = try ink(.month)
        for other in ConversionPeriod.allCases where other != .month {
            XCTAssertNotEqual(month, try ink(other),
                              "the row looks the same on «\(other)» as on «month»: nothing marks "
                              + "the chosen period, which is what `.borderedProminent` did in a "
                              + "window that is not key")
        }
    }
}
