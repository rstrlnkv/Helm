import Foundation
import XCTest
@testable import Module_Screenshots_Engine

final class ShotNamesTests: XCTestCase {

    private let utc = TimeZone(identifier: "UTC")!

    private var moment: Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 30
        parts.hour = 14; parts.minute = 2; parts.second = 11
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: parts)!
    }

    func testTheNameIsMacOSsShapeWithFullStopsInTheTime() {
        let name = ShotNames.base(date: moment,
                                  naming: ShotNaming(template: "Screenshot %@ at %@", locale: Locale(identifier: "en_GB")),
                                  timeZone: utc)
        XCTAssertEqual(name, "Screenshot 2026-09-30 at 14.02.11")
    }

    func testATimeNeverCarriesAColon() {
        for identifier in ["en_US", "en_GB", "ru_RU", "de_DE", "fr_FR", "ja_JP", "zh_CN", "pt_BR", "es_ES"] {
            let name = ShotNames.base(date: moment,
                                      naming: ShotNaming(template: "S %@ %@", locale: Locale(identifier: identifier)),
                                      timeZone: utc)
            XCTAssertFalse(name.contains(":"), "\(identifier): a colon in a Finder name: \(name)")
            XCTAssertFalse(name.contains("/"), "\(identifier): \(name)")
        }
    }

    func testTheTemplateIsTheCallersAndTheDateIsAlwaysYearFirst() {
        let name = ShotNames.base(date: moment,
                                  naming: ShotNaming(template: "Снимок экрана — %@ в %@", locale: Locale(identifier: "ru_RU")),
                                  timeZone: utc)
        XCTAssertEqual(name, "Снимок экрана — 2026-09-30 в 14.02.11")
    }

    func testTheWallClockIsTheZoneAsked() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let name = ShotNames.base(date: moment,
                                  naming: ShotNaming(template: "%@ %@", locale: Locale(identifier: "en_GB")), timeZone: tokyo)
        XCTAssertEqual(name, "2026-09-30 23.02.11")
    }

    /// `testTheWallClockIsTheZoneAsked` moves the hour and never the day: 14:02
    /// in UTC is still the 30th in Tokyo, so a *date* read in any other zone
    /// between UTC−14 and UTC+9 passes it. Here the zone moves the day as well —
    /// 20:02 UTC is 05:02 on the 1st in Tokyo and 15:02 on the 30th in Chicago —
    /// and both halves of the name have to follow it.
    func testTheZoneAskedMovesTheDayAsWellAsTheHour() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 30
        parts.hour = 20; parts.minute = 2; parts.second = 11
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let evening = calendar.date(from: parts)!
        let naming = ShotNaming(template: "%@ %@", locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(ShotNames.base(date: evening, naming: naming, timeZone: TimeZone(identifier: "Asia/Tokyo")!),
                       "2026-10-01 05.02.11")
        XCTAssertEqual(ShotNames.base(date: evening, naming: naming, timeZone: TimeZone(identifier: "America/Chicago")!),
                       "2026-09-30 15.02.11")
    }

    func testTheLadder() {
        XCTAssertEqual(ShotNames.candidate(base: "a", pathExtension: "png", attempt: 0), "a.png")
        XCTAssertEqual(ShotNames.candidate(base: "a", pathExtension: "png", attempt: 1), "a (1).png")
        XCTAssertEqual(ShotNames.candidate(base: "a", pathExtension: "", attempt: 2), "a (2)")
    }
}
