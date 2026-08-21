// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmUI

/// **`HelmDates.relative` refuses nothing, and it has five callers.**
///
/// The VPN page printed «Мбит/с · через 5 мин.» — a forecast under a figure
/// taken in the past — because a reading stamped ahead of the clock has a
/// negative age and the tile drew it anyway. That was repaired at the tile
/// (`VPNTunnelFacts.speedShowsItsAge`), and the function underneath was left
/// able to do the same for everybody else. Two of its callers gate the stamp
/// themselves before they reach it — `UpdateCheck.lastChecked` refuses a future
/// number outright, `VPNTunnelFacts` refuses a negative age — and three do not:
/// `GeneralSettingsPage`'s scan row, `DiskResultView`'s «measured» line and
/// `KeysTable`'s modification date each hand the function a stamp they have not
/// looked at.
///
/// Every one of the five draws an **age**: «Checked …», «Measured …», «Last
/// scan …», how old a key file is, how old a speed reading is. Not one of them
/// ever wants a forecast, so a function that can answer with one has a range
/// wider than every use of it.
///
/// **Two reachable ways it draws the future**, both measured on macOS 27 across
/// all eight languages:
///
/// 1. A stamp genuinely ahead of the clock. Trivially real: a file copied from
///    a Mac whose clock is ahead carries a modification date in the future, and
///    `KeysTable` draws exactly that. So does a scan row after an NTP step.
/// 2. **A stamp in the past by less than half a second**, which needs no skew at
///    all. `RelativeDateTimeFormatter` rounds the interval to the nearest second
///    and renders a rounded zero in the *future* voice: −0.4 s comes back as
///    «через 0 секунд», "in 0 seconds", «dentro de 0 segundos» — in every one of
///    the eight. A scan that has just finished, or a key file written a moment
///    ago, is drawn as something still to come. A repair written as
///    `guard date <= now` does not touch this one, which is why it is pinned
///    separately.
///
/// Parameterized by language explicitly and never by `AppLanguage.current`: this
/// Mac is set to Russian, so an assertion gated on the current language would
/// exercise one of the eight and silently never the one it was written for.
final class AForecastIsNotAnAgeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let languages = AppLanguage.allCases.map(\.rawValue)
    private let styles: [(name: String, style: HelmDates.AgeStyle)] = [
        ("full", .full), ("short", .short),
    ]

    /// Magnitudes either side of the seam: the sub-second rounding case, the
    /// second, the five minutes the owner saw, a day, a year.
    private let magnitudes: [TimeInterval] = [0.1, 0.4, 0.6, 1, 70, 300, 90_000, 31_000_000]

    /// How macOS itself writes a time still to come, asked of the system rather
    /// than spelled out here — the eight spellings are CLDR's and change with
    /// the OS, and a test carrying its own copy of them would be pinning this
    /// machine's macOS instead of the app's behaviour.
    private func systemForecasts(language: String,
                                 style: RelativeDateTimeFormatter.UnitsStyle) -> Set<String> {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.unitsStyle = style
        return Set(magnitudes.map {
            formatter.localizedString(for: now.addingTimeInterval($0), relativeTo: now)
        })
    }

    /// The app's two cases in the system's vocabulary, spelled out here rather
    /// than read off `AgeStyle.system` — that mapping is itself the subject of
    /// `AnAgeIsNotASignedDeltaTests`, and a comparison whose two sides read one
    /// constant agrees with itself whatever the constant says.
    private func system(_ style: HelmDates.AgeStyle) -> RelativeDateTimeFormatter.UnitsStyle {
        switch style {
        case .full: .full
        case .short: .short
        }
    }

    // MARK: - The stamp that is really ahead of the clock

    /// **A stamp in the future has no age, so nothing is drawn for it.**
    ///
    /// Nothing rather than something invented, which is what every other
    /// refusal in this tree already does with the same input:
    /// `HelmExpectedWait.Claim.at` falls to `.unknown` because «a negative
    /// elapsed time … is evidence that the stamp cannot be trusted»,
    /// `UpdateCheck.lastChecked` answers `nil`, `VPNTunnelFacts.speedShowsItsAge`
    /// answers `false` and the unit stands alone.
    ///
    /// **A clamp is not the repair and this says so.** «0 seconds ago» for a
    /// file dated next March is wrong in a way nothing on screen can show and
    /// no test can catch, because «just now» is also what a true fresh reading
    /// says. The absence is the only answer a reader can tell apart.
    ///
    /// Written as `as String?` on purpose: it holds under today's `String` and
    /// under the `String?` this asks for, so the repair does not have to arrive
    /// in the same commit as its guard.
    func testAStampAheadOfTheClockHasNoAgeToDraw() {
        for language in languages {
            for (name, style) in styles {
                for ahead in magnitudes {
                    let drawn = HelmDates.relative(now.addingTimeInterval(ahead), to: now,
                                                   style: style, language: language)
                    XCTAssertTrue((drawn as String?)?.isEmpty ?? true, """
                        \(language)/\(name) draws «\(drawn)» for a stamp \(ahead) s ahead of \
                        the clock — a time still to come, under a line that says how old \
                        something is
                        """)
                }
            }
        }
    }

    // MARK: - And the one that needs no skew at all

    /// **A reading taken a moment ago is written in the future voice**, because
    /// the formatter rounds to the nearest second and renders a rounded zero as
    /// «in 0 seconds».
    ///
    /// The precondition is asserted first and it is not decoration: this is a
    /// test of an *absence*, and «the app's answer is not one of the system's
    /// forecasts» is trivially true if the set of forecasts is empty or the
    /// app's answer is compared against nothing.
    func testAReadingTakenAMomentAgoIsNotWrittenAsAForecast() {
        for language in languages {
            for (name, style) in styles {
                let forecasts = systemForecasts(language: language, style: system(style))
                XCTAssertGreaterThan(forecasts.count, 3,
                                     "\(language)/\(name): macOS wrote \(forecasts.count) "
                                     + "distinct forecasts for eight magnitudes, so this "
                                     + "comparison is not the one it was written to make")
                XCTAssertFalse(forecasts.contains(""), "\(language)/\(name): a blank forecast")

                for behind in magnitudes {
                    let drawn = HelmDates.relative(now.addingTimeInterval(-behind), to: now,
                                                   style: style, language: language)
                    XCTAssertFalse(forecasts.contains(drawn), """
                        \(language)/\(name) writes a reading \(behind) s **old** as \
                        «\(drawn)», which is how macOS writes a time still to come
                        """)
                }
            }
        }
    }

    // MARK: - Neither pin may be satisfied by drawing nothing at all

    /// The floor under both tests above. «Return nothing, always» passes every
    /// assertion in this file and empties four lines of the app, so the ages
    /// that are real have to stay real: a figure, its unit, and the word for
    /// «ago» in that language.
    ///
    /// Two seconds and up, deliberately — the first half second is what
    /// `testAReadingTakenAMomentAgoIsNotWrittenAsAForecast` is about, and a
    /// repair is free to draw nothing there rather than round the wrong way.
    func testAnAgeThatIsRealIsStillDrawn() {
        for language in languages {
            for (name, style) in styles {
                for behind in magnitudes.filter({ $0 >= 2 }) {
                    let drawn = HelmDates.relative(now.addingTimeInterval(-behind), to: now,
                                                   style: style, language: language)
                    XCTAssertTrue(drawn.contains(where: \.isNumber), """
                        \(language)/\(name) draws «\(drawn)» for a reading \(behind) s old, \
                        with no figure in it — the refusal has been widened over the ages \
                        that are true
                        """)
                }
            }
        }
    }

    /// And the same floor said about the boundary itself: the instant the clock
    /// and the stamp agree is not the future, and a scan row that has this
    /// moment's stamp is a scan row with an age of zero — not a forecast, and
    /// not a blank line either if the repair keeps a zero form.
    ///
    /// Asserted as «not a forecast» rather than as a spelling, because the two
    /// honest answers at exactly zero — «just now» and nothing at all — are both
    /// the writer's to choose and neither is a time still to come.
    func testTheInstantTheStampAndTheClockAgreeIsNotAForecast() {
        for language in languages {
            for (name, style) in styles {
                let forecasts = systemForecasts(language: language, style: system(style))
                XCTAssertFalse(forecasts.isEmpty, "\(language)/\(name): nothing to compare with")
                let drawn = HelmDates.relative(now, to: now, style: style, language: language)
                XCTAssertFalse(forecasts.contains(drawn), """
                    \(language)/\(name) writes «\(drawn)» for a stamp taken at this very \
                    instant, which is how macOS writes a time still to come
                    """)
            }
        }
    }
}
