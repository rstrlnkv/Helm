import XCTest
@testable import Module_Layout_Engine

final class ModelTests: XCTestCase {
    /// The wire types cross a JSON boundary; a field that does not survive the
    /// round trip is a command the UI sends and the engine never sees.
    func testConversionEventRoundTrips() throws {
        let event = ConversionEvent(before: "ghbdtn", after: "привет", app: "com.apple.Notes")
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(ConversionEvent.self, from: data), event)
    }

    func testStateRoundTrips() throws {
        let state = LayoutState(enabled: true, automatic: true, suspended: false,
                                lastConversion: nil, lastConversionUndone: false,
                                totals: ConversionTotals(today: LedgerFigures(words: 3, characters: 18),
                                                         week: LedgerFigures(words: 3, characters: 18),
                                                         month: LedgerFigures(words: 3, characters: 18),
                                                         year: LedgerFigures(words: 3, characters: 18),
                                                         allTime: LedgerFigures(words: 3, characters: 18),
                                                         since: nil))
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LayoutState.self, from: data), state)
    }
}
