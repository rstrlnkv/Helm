import Foundation
import HelmTestSupport
import XCTest
@testable import HelmUI

/// `HelmDates`' long day, since its formatters were keyed by the zone as well
/// as the language so the Log's headings follow a zone changed under a
/// running app.
///
/// Two things that change touches besides the Log. A *stored* day
/// ("2026-07-28", the changelog's entries on the About page) is a calendar day
/// and not a moment: it is parsed at midnight in one zone, so written in any
/// other it reads as the day before or after — it has to be written in the
/// zone it was read in, whatever zone the process is in now. And a cache keyed
/// by something that changes can grow with it: the key has to be one that
/// repeats, or every call builds a formatter and keeps it.
final class ADayKeepsItsZoneAndItsCacheTests: XCTestCase {

    /// Kiritimati is UTC+14 and Honolulu UTC−10: a midnight parsed in one of
    /// them is the previous or next day in the other, whichever zone this Mac is
    /// in, so the pair separates a wrong zone on any machine.
    private let zones = ["Pacific/Kiritimati", "Pacific/Honolulu", "UTC"]
        .map { TimeZone(identifier: $0)! }

    func testAStoredDayReadsTheSameInEveryZoneTheProcessMovesTo() {
        let before = NSTimeZone.default
        addTeardownBlock { NSTimeZone.default = before }
        for language in AppLanguage.allCases {
            // Read first where the process started, as the About page is.
            let home = HelmDates.day("2026-07-28", language: language.rawValue)
            let dayBefore = HelmDates.day("2026-07-27", language: language.rawValue)
            // The subject: the stored form was turned into a day at all, and
            // two neighbouring days read differently.
            XCTAssertNotEqual(home, "2026-07-28", "\(language): the stored day was not parsed")
            XCTAssertNotEqual(home, dayBefore, "\(language): two days read alike")
            for zone in zones {
                NSTimeZone.default = zone
                XCTAssertEqual(HelmDates.day("2026-07-28", language: language.rawValue), home,
                               "\(language): the stored day moved when the process moved to "
                               + zone.identifier)
            }
            NSTimeZone.default = before
        }
        NSTimeZone.default = before
        XCTAssertEqual(HelmDates.day("2026-07-28", language: AppLanguage.en.rawValue),
                       "July 28, 2026")
    }

    /// A moment is written in the zone the process is in now: the same instant
    /// is a different day in Kiritimati and in Honolulu. Without this the test
    /// above could pass by the formatter ignoring the zone altogether.
    func testAMomentIsWrittenInTheZoneTheProcessIsInNow() {
        let before = NSTimeZone.default
        addTeardownBlock { NSTimeZone.default = before }
        // 12:00 UTC on 28 July: the 29th in Kiritimati, the 28th in Honolulu.
        let noon = Date(timeIntervalSince1970: 1_785_240_000)
        NSTimeZone.default = zones[0]
        let east = HelmDates.day(noon, language: AppLanguage.en.rawValue)
        NSTimeZone.default = zones[1]
        let west = HelmDates.day(noon, language: AppLanguage.en.rawValue)
        XCTAssertEqual(east, "July 29, 2026")
        XCTAssertEqual(west, "July 28, 2026")
    }

    /// The cache is keyed by language and zone *identifier*: coming back to a
    /// zone — through a fresh `TimeZone` value, as every read of the default is
    /// — has to find the formatter built the first time. Measured by what the
    /// calls ask the allocator for: the call that meets a zone builds a
    /// formatter, and a call after it in the same zone must ask for a small
    /// fraction of that. The default is set outside the measurement, because
    /// setting it is itself expensive and is not what is being measured.
    func testReturningToAZoneBuildsNothingNew() throws {
        let before = NSTimeZone.default
        addTeardownBlock { NSTimeZone.default = before }
        let moment = Date(timeIntervalSince1970: 1_785_240_000)
        // A zone no other test in this process uses, so the first call builds.
        NSTimeZone.default = TimeZone(identifier: "Asia/Kathmandu")!
        let first = try ThreadAllocations.during(countingBlocksOfAtLeast: 1 << 20) {
            HelmDates.day(moment, language: AppLanguage.de.rawValue)
        }
        // Away and back, through a new value naming the same zone.
        NSTimeZone.default = TimeZone(identifier: "UTC")!
        NSTimeZone.default = TimeZone(identifier: "Asia/Kathmandu")!
        let calls = 100
        let again = try ThreadAllocations.during(countingBlocksOfAtLeast: 1 << 20) {
            (0..<calls).map { _ in HelmDates.day(moment, language: AppLanguage.de.rawValue) }
        }
        XCTAssertEqual(Set(again.result), [first.result])
        // The subject: the first call did build something worth measuring.
        XCTAssertGreaterThan(first.reading.requested, 32 * 1024,
                             "the first call in a new zone asked for \(first.reading.requested) "
                             + "bytes — it built no formatter, so the comparison proves nothing")
        let perCall = again.reading.requested / calls
        XCTAssertLessThan(perCall * 10, first.reading.requested, """
            a call in a zone already met asked for \(perCall) bytes against \
            \(first.reading.requested) for the one that met it — the cache missed
            """)
    }
}
