// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmUI

/// **macOS spells an age three ways and one of them is not an age.**
///
/// `RelativeDateTimeFormatter` offers `.full`, `.short` and `.abbreviated`.
/// The third is the trap, and its name is exactly what a reader reaching for a
/// shorter form would pick: measured on macOS 27 across Helm's eight, it prints
/// «-1 мин» in Russian and «-1 min» in French — a signed *delta*, not an age,
/// and the tile it would sit in stands under a figure that is itself two signed
/// readings. So the parameter is `HelmDates.AgeStyle`, which has two cases and
/// cannot spell the third; this file is the guard under the mapping, because an
/// enum stops a caller choosing wrong and does not stop the enum being wired to
/// the wrong system style.
final class AnAgeIsNotASignedDeltaTests: XCTestCase {

    /// Every language, every unit boundary the speed tile can sit at: a minute,
    /// most of an hour, an hour, a day, a fortnight, a week.
    private let deltas: [TimeInterval] = [-70, -2400, -3700, -90_000, -1_036_800, -1_100_000]

    private func each(_ body: (String, TimeInterval, String) -> Void) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for language in AppLanguage.allCases.map(\.rawValue) {
            for delta in deltas {
                body(language, delta, HelmDates.relative(now.addingTimeInterval(delta), to: now,
                                                         style: .short, language: language))
            }
        }
    }

    /// **The rule the enum exists for.** Wire `.short` to the system's
    /// `.abbreviated` and Russian and French start with a minus sign; nothing
    /// else in this file would notice.
    func testAShortAgeIsNeverWrittenAsASignedNumber() {
        each { language, delta, age in
            XCTAssertFalse(age.hasPrefix("-") || age.hasPrefix("\u{2212}"), """
                \(language) writes an age \(-delta) s old as «\(age)» — a signed \
                delta, which draws under a speed figure that is already two \
                signed readings
                """)
        }
    }

    /// And it says *ago* rather than merely naming a unit: an age with its
    /// direction cut off is a duration, which is what the column beside it is.
    func testAShortAgeStillCarriesADigitAndItsUnit() {
        each { language, delta, age in
            XCTAssertTrue(age.contains(where: \.isNumber), """
                \(language) writes an age \(-delta) s old as «\(age)», with no \
                figure in it at all
                """)
        }
    }

    /// **Shorter is the whole point**, and in two of the eight it is the same
    /// string: Japanese and Chinese spell «1 分前» either way. Asserted as «never
    /// longer» rather than «always shorter» so that neither language has to be
    /// filtered out of its own guard.
    func testTheShortFormIsNeverLongerThanTheFullOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for language in AppLanguage.allCases.map(\.rawValue) {
            for delta in deltas {
                let then = now.addingTimeInterval(delta)
                let short = HelmDates.relative(then, to: now, style: .short, language: language)
                let full = HelmDates.relative(then, to: now, style: .full, language: language)
                XCTAssertLessThanOrEqual(short.count, full.count,
                                         "\(language): «\(short)» is longer than «\(full)»")
            }
        }
    }

    /// The Russian the owner reported and asked for by name, at the boundary
    /// the speed tile crosses first. A concrete spelling because this one is on
    /// somebody's screen: «1 минуту назад» is 120.1 pt and wraps the column,
    /// and the shorter form is why the parameter exists.
    func testTheRussianMinuteIsTheShortFormTheOwnerAskedFor() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(HelmDates.relative(now.addingTimeInterval(-70), to: now,
                                          style: .short, language: "ru"),
                       "1 мин. назад")
    }

    /// **Nobody else's dates were reworded.** `relative` has four other callers
    /// — the scan rows, the update check, Disk's «measured» line, the key
    /// table — and none of them is in a 143 pt column. The parameter defaults
    /// to what they have always drawn.
    func testTheStyleNobodyAsksForIsStillTheFullOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for language in AppLanguage.allCases.map(\.rawValue) {
            for delta in deltas {
                let then = now.addingTimeInterval(delta)
                XCTAssertEqual(HelmDates.relative(then, to: now, language: language),
                               HelmDates.relative(then, to: now, style: .full,
                                                  language: language),
                               "\(language): the default stopped being the full form")
            }
        }
    }

    /// One formatter per language **and per style**, and the cache keyed by
    /// both: keyed by language alone, the first style a language was asked for
    /// is the style it answers in for the life of the process — so the speed
    /// tile's `.short` would reword the About page's «last checked» on any Mac
    /// that opened the VPN page first.
    func testAskingForOneStyleDoesNotRewordTheOther() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let then = now.addingTimeInterval(-70)
        let short = HelmDates.relative(then, to: now, style: .short, language: "ru")
        let full = HelmDates.relative(then, to: now, style: .full, language: "ru")
        XCTAssertNotEqual(short, full, "precondition: Russian spells the two the same")
        XCTAssertEqual(HelmDates.relative(then, to: now, style: .short, language: "ru"), short)
        XCTAssertEqual(HelmDates.relative(then, to: now, style: .full, language: "ru"), full)
    }
}
