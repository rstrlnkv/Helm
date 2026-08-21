// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **The scan row has three answers and «never» is not one of them twice.**
///
/// `HelmDates.age` refuses a stamp it cannot word — one ahead of the clock, and
/// one younger than the second the system formatter needs before it says «ago»
/// — and the row underneath a scan's name then has a case it did not have
/// before: a scan that *has* run, with no age to draw for it.
///
/// The wrong answer is `AppStr.scanNeverRun`, and it is wrong in the way that
/// is hardest to see: «Не запускалось» is a sentence, it fits the row, and it
/// contradicts nothing on the page except the switch beside it, which is on
/// and which the coordinator has just used. The right answer is the second
/// line not being drawn at all.
///
/// Parameterized by an explicit language: this Mac is Russian, so a test gated
/// on `AppLanguage.current` would exercise one of the eight and never the seven
/// it was written for.
final class AScanRowWithNoAgeSaysNothingTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A scan that has never run says so — the case that was there before any
    /// of this and has to survive it.
    func testAScanThatNeverRanStillSaysSo() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(MenuBarSettingsView.scanCaption(lastRun: nil, now: now,
                                                           language: language),
                           AppStr.scanNeverRun(language: language),
                           "\(language.rawValue): a scan with no stamp lost its caption")
        }
    }

    /// A scan that came back a moment ago — the settings page open while a
    /// background scan finishes, which needs no broken clock at all.
    func testAScanThatCameBackThisSecondDrawsNothingRatherThanNever() {
        for language in AppLanguage.allCases {
            for age in [0.0, 0.4, 0.9] {
                let caption = MenuBarSettingsView.scanCaption(
                    lastRun: now.addingTimeInterval(-age), now: now, language: language)
                XCTAssertNil(caption, """
                    \(language.rawValue) draws «\(caption ?? "")» for a scan that came back \
                    \(age) s ago — either a time still to come or a claim that it never ran
                    """)
            }
        }
    }

    /// And a stamp an NTP step or a fast clock has left ahead of now.
    func testAStampAheadOfTheClockDrawsNothingRatherThanNever() {
        for language in AppLanguage.allCases {
            let caption = MenuBarSettingsView.scanCaption(
                lastRun: now.addingTimeInterval(300), now: now, language: language)
            XCTAssertNil(caption,
                         "\(language.rawValue) draws «\(caption ?? "")» for a scan stamped "
                         + "five minutes into the future")
        }
    }

    /// The floor under the three above: «draw nothing, always» passes every
    /// assertion in this file that is about an absence, and empties the row for
    /// every scan on the page.
    func testAScanWithARealAgeStillSaysWhenItRan() {
        for language in AppLanguage.allCases {
            for age in [70.0, 90_000.0] {
                let caption = MenuBarSettingsView.scanCaption(
                    lastRun: now.addingTimeInterval(-age), now: now, language: language)
                let drawn = try? XCTUnwrap(caption, "\(language.rawValue): nothing for \(age) s")
                XCTAssertEqual(drawn?.isEmpty, false)
                XCTAssertEqual(drawn?.contains(where: \.isNumber), true,
                               "\(language.rawValue) draws «\(drawn ?? "")» for a scan \(age) s "
                               + "old, with no figure in it")
                XCTAssertNotEqual(drawn, AppStr.scanNeverRun(language: language),
                                  "\(language.rawValue) called a scan that ran a scan that "
                                  + "never ran")
            }
        }
    }
}
