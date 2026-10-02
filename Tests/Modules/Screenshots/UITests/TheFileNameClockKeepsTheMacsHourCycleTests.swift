import XCTest
import HelmUI
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The file name's clock keeps the Mac's own hour cycle, not only its region.**
/// `TheNameIsMacOSsInEveryLanguageTests` pins the language and the region; the
/// 24-hour switch in System Settings is neither — on this Mac `Locale.current`
/// reads `ru_RU@…hours=h23`, the switch arriving as a keyword on the locale — so
/// a locale rebuilt from language and region alone passes that test and names a
/// file "10.25.33 PM" on a US Mac whose menu-bar clock says 22:25.
final class TheFileNameClockKeepsTheMacsHourCycleTests: XCTestCase {

    private var moment: Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 30; parts.hour = 22; parts.minute = 25; parts.second = 33
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: parts)!
    }

    func testAForcedHourCycleOnTheMacIsTheFileNamesHourCycle() {
        let utc = TimeZone(identifier: "UTC")!
        let cases: [(Locale, String)] = [
            (Locale(identifier: "en_US@hours=h23"), "22.25.33"),
            (Locale(identifier: "en_GB@hours=h12"), "10.25.33"),
        ]
        var checked = 0
        for (system, clock) in cases {
            AppLanguage.each { language in
                let name = ShotNames.base(date: moment, naming: ScStr.naming(system: system, language: language),
                                          timeZone: utc)
                XCTAssertTrue(name.contains(clock), "\(language) on \(system.identifier): \(name)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 2 * AppLanguage.allCases.count)
    }
}
