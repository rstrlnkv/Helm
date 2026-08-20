// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmUI
import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// **The clock-skew case is decided in `VPNTunnelFacts` and then drawn as its
/// opposite.**
///
/// `VPNTunnelFacts.speedIsStale` handles a reading stamped in the future on
/// purpose, and says why in its own words: «true for a negative age, which is
/// the clock-skew case `init` already refuses for `since`: **a figure stamped in
/// the future has no age to show**». `TheTilesSayWhatIsKnownTests` holds that
/// `true`.
///
/// `VPNTunnelStrip.speedTile` is that property's only reader, and what it does
/// with `true` is *show the age* — `HelmDates.relative(speed.at, to: now,
/// style: .short)`, which for a stamp ahead of the clock is not an age at all
/// but a forecast: «Мбит/с · через 5 мин.», "Mbit/s · in 5 min." under a figure
/// that was taken in the past. So the branch written to protect against clock
/// skew is the branch that prints the skew.
///
/// **The input is a state this feature already agreed it has to survive.**
/// `HelmExpectedWait.Claim.at` refuses a negative elapsed time in so many words
/// — «a clock that went backwards under the run — an NTP step, a laptop
/// resuming — … a negative elapsed time is not a small fraction, it is evidence
/// that the stamp cannot be trusted» — and answers `unknown` rather than
/// drawing something. The reading's `at` comes off the same clock, over the
/// wire, and can be ahead of the page's `now` by exactly that much.
///
/// Asserted in all eight languages, because the shape of a future relative date
/// is a fact about each of them and this Mac is set to one
/// (CLAUDE.md § a test parameterized by an explicit language).
final class AnAgeIsNeverAheadOfTheClockTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func tunnel(speed: VPNSpeedReading) -> VPNTunnelState {
        VPNTunnelState(name: "incy", interface: "utun4",
                       since: now.addingTimeInterval(-3600),
                       bytesIn: 1_200_000_000, bytesOut: 210_000_000,
                       exit: .throughTunnel(countryCode: "NL"), speed: speed)
    }

    private func speedNote(_ at: Date) -> String? {
        VPNTunnelStrip(tunnel(speed: VPNSpeedReading(down: 212, up: 95, rpm: 340, at: at)),
                       now: now)
            .tiles.first { $0.kind == .speed }?.note
    }

    /// Five minutes ahead: an NTP step, a resume, a payload that crossed the
    /// wire while the clock moved.
    private var ahead: Date { now.addingTimeInterval(300) }

    func testAReadingStampedAheadOfTheClockIsNotDrawnAsATimeToCome() {
        AppLanguage.each { language in
            let note = speedNote(ahead)
            // The absence below is free on a strip that drew no speed tile at
            // all, which is a different defect and must not read as this one.
            XCTAssertNotNil(note, "precondition: \(language.rawValue) drew no speed tile")
            XCTAssertNotEqual(note, VPNStr.speedNote(HelmDates.relative(ahead, to: now,
                                                                       style: .short)), """
                \(language.rawValue) drew «\(note ?? "")» — the note under the \
                figure is a time still to come. `VPNTunnelFacts.speedIsStale` \
                answers `true` here precisely because «a figure stamped in the \
                future has no age to show», and its only reader takes that `true` \
                as «show the age»
                """)
        }
    }

    /// **The control, and it is what stops the assertion above being a rule
    /// about nothing.** An ordinary stale reading — three minutes old — must go
    /// on carrying exactly the age it carries today. A repair that dropped the
    /// age line for every stale figure would satisfy the test above and lose the
    /// thing the age line is for.
    func testAnOrdinaryStaleReadingStillCarriesItsAge() {
        let behind = now.addingTimeInterval(-180)
        AppLanguage.each { language in
            XCTAssertEqual(speedNote(behind),
                           VPNStr.speedNote(HelmDates.relative(behind, to: now, style: .short)),
                           "\(language.rawValue): a three-minute-old figure lost its age")
        }
    }

    /// And a fresh one still stands on the unit alone, which is the other half
    /// of `speedIsStale`'s contract.
    func testAFreshReadingIsUnaffected() {
        AppLanguage.each { language in
            XCTAssertEqual(speedNote(now.addingTimeInterval(-5)), VPNStr.speedUnit,
                           "\(language.rawValue): a five-second-old figure gained a line")
        }
    }
}
