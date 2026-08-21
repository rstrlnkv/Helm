// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// **A headline that runs onto a second line is still centred**, and for one
/// release it was not.
///
/// The figure is a *sentence* at 40 pt — «Der Mac geht wie immer in den
/// Ruhezustand» — and a `Text` with no alignment of its own is drawn flush left
/// inside whatever width it is given. Photographed on the real page at 845 pt,
/// the German idle headline drew its two lines on centres **147.75 pt apart**:
/// one line ranging to the right edge of the column and the word under it
/// hanging off the left. Nothing on this page could see it — every render check
/// here sums ink over a band, and a ragged pair of lines is exactly as many
/// pixels as a centred one.
///
/// **Swept over all eight languages rather than checked in one.** The idle
/// sentence at 40 pt light needs 407 pt in English and 742 in German against a
/// header column of 684, so the language this Mac happens to be set to decides
/// whether the defect is on screen at all — the argument `StringsCoverageTests`
/// makes about a table, made about a layout. The sweep asserts that some
/// language wrapped before it asserts anything about wrapping, because «every
/// wrapped line is centred» is satisfied outright by a headline that never
/// wraps.
@MainActor
final class AWrappedHeadlineIsStillCentredTests: XCTestCase {

    /// **A floor read off the drawing, not a round number.** Two lines of one
    /// centred string do not agree to the pixel: the widest innocent
    /// disagreement measured over both widths and all eight languages is
    /// 4.25 pt, in Japanese, where a glyph's ink sits off-centre inside its
    /// full-width em. The defect this exists for measures 36.5 to 147.75.
    private static let apart: CGFloat = 8

    private var mounted: [MountedRender] = []

    override func tearDown() async throws {
        mounted.forEach { $0.drop() }
        mounted = []
        AppLanguage.override = nil
        try await super.tearDown()
    }

    private func headline(_ language: AppLanguage, width: CGFloat) -> [RenderedLines.Line]? {
        AppLanguage.override = language
        let hero = KeepAwakeHero(state: .idle, now: Date(timeIntervalSince1970: 1_700_000_000),
                                 anyRuleOn: true, defaultDurationMinutes: 60,
                                 suppressed: false, ruleHolds: false,
                                 timerEndsAutomation: false,
                                 batteryStopped: false, batteryFloor: 20,
                                 timedNote: { _ in "" },
                                 start: { _ in }, stop: {}, resume: {}, announce: { _ in })
        let render = MountedRender(hero, width: width, height: 300, appearance: .aqua)
        mounted.append(render)
        render.settle()
        // The bitmap is taken inside the read, so the window has nothing left to
        // hold: sixteen of them alive to the end of the test is sixteen hosting
        // views holding sixteen heroes.
        defer { render.drop() }
        return HeroFigure.lines(of: render.host)
    }

    /// Both widths, because the two answer different questions: the default pane
    /// is what most people see and the narrowest is what the layout has to
    /// survive. Neither is allowed to draw a stepped headline.
    func testEveryWrappedIdleHeadlineIsCentredOnItsOwnColumn() throws {
        for width in HeroFigure.widths {
            var wrapped: [AppLanguage] = []
            for language in AppLanguage.allCases {
                let lines = try XCTUnwrap(headline(language, width: width),
                                          "nothing drew at \(Int(width)) pt — no window server")
                XCTAssertFalse(lines.isEmpty,
                               "\(language.rawValue) drew no headline at all at \(Int(width)) pt")
                guard lines.count > 1 else { continue }
                wrapped.append(language)
                let spread = HeroFigure.spread(lines)
                XCTAssertLessThan(spread, Self.apart, """
                    \(language.rawValue) at \(Int(width)) pt drew its \(lines.count) headline \
                    lines on centres \(String(format: "%.2f", spread)) pt apart — \
                    \(HeroFigure.centres(lines)) — so the sentence is ragged against a column \
                    everything else on the page is centred in
                    """)
            }
            XCTAssertFalse(wrapped.isEmpty, """
                no language wrapped its headline at \(Int(width)) pt, so this sweep proved \
                nothing: the check needs a headline that runs onto a second line before it can \
                say anything about where the second line sits
                """)
        }
    }
}
