import XCTest
@testable import Module_Homebrew_Engine

/// The two decisions worth testing without a network.
///
/// The counts cover a thirty-day window and Homebrew publishes them daily, so
/// asking more than once a day is bandwidth spent on a number that has not
/// moved. And a document read off the wire is bounded before it is parsed: the
/// two files were 453,903 and 399,502 bytes on 2026-09-13, and a ceiling well
/// above that is the difference between a moved endpoint costing a refusal and
/// it costing however much whatever now lives there decides to send.
final class PopularityRefreshTests: XCTestCase {

    func testNothingStoredMeansAFetchIsDue() {
        XCTAssertTrue(PopularityRefresh.isDue(lastWritten: nil, now: Date()))
    }

    func testAReadingFromThisHourIsNotWorthReplacing() {
        let now = Date()
        XCTAssertFalse(PopularityRefresh.isDue(lastWritten: now.addingTimeInterval(-3600),
                                               now: now))
    }

    func testADayOldReadingIsDue() {
        let now = Date()
        XCTAssertTrue(PopularityRefresh.isDue(lastWritten: now.addingTimeInterval(-90_000),
                                              now: now))
    }

    /// A clock that has gone backwards — a Mac whose date was wrong and got
    /// fixed — must not park the refresh for ever.
    func testAReadingFromTheFutureIsDue() {
        let now = Date()
        XCTAssertTrue(PopularityRefresh.isDue(lastWritten: now.addingTimeInterval(90_000),
                                              now: now))
    }

    func testTheRealDocumentsFitUnderTheCeiling() {
        XCTAssertTrue(PopularityRefresh.isWithinCeiling(453_903))
        XCTAssertTrue(PopularityRefresh.isWithinCeiling(399_502))
    }

    func testSomethingTenTimesTheSizeIsRefused() {
        XCTAssertFalse(PopularityRefresh.isWithinCeiling(45_000_000))
    }

    // MARK: - What a response means

    private var oneDocument: Data {
        Data(#"{"formulae":{"helm":[{"count":"1,162"}]}}"#.utf8)
    }

    func testADocumentThisBuildCanReadIsTheOnlyAnswerThatReplacesAReading() {
        XCTAssertEqual(PopularityRefresh.answer(statusCode: 200, data: oneDocument),
                       .use(InstallCounts(counts: ["helm": 1162])))
    }

    func testA304IsNotARefusalAndNotAReading() {
        // And it is decided before the body is looked at: a 304 carries none.
        XCTAssertEqual(PopularityRefresh.answer(statusCode: 304, data: Data()), .unchanged)
    }

    /// The case that made the ceiling worth having: an endpoint that has moved
    /// and now serves somebody else's idea of a response.
    func testAnythingOverTheCeilingIsRefusedBeforeItIsParsed() {
        // Valid JSON, and far too much of it — so a refusal here can only be
        // the size, which is what makes this test about the ceiling.
        var huge = Data(#"{"formulae":{"a":[{"count":"1"}]}}"#.utf8)
        huge.append(Data(repeating: 0x20, count: PopularityRefresh.sizeCeiling))
        guard case .refused(let why) = PopularityRefresh.answer(statusCode: 200, data: huge) else {
            return XCTFail("a document over the ceiling was not refused")
        }
        XCTAssertTrue(why.contains("bytes"), "the refusal does not say what was wrong: \(why)")
    }

    func testAServerErrorIsARefusalAndNeverAnEmptyReading() {
        guard case .refused(let why) = PopularityRefresh.answer(statusCode: 503, data: Data()) else {
            return XCTFail("HTTP 503 was not refused")
        }
        XCTAssertTrue(why.contains("503"), "the refusal does not say what the server said: \(why)")
    }

    /// A redirect to a sign-in page, a proxy's notice, a truncated write: all
    /// of it parses to nothing, and nothing must not become a reading in which
    /// no package is ever installed.
    func testAShapeThisBuildCannotReadIsARefusalAndNotAnEmptyReading() {
        guard case .refused = PopularityRefresh.answer(statusCode: 200,
                                                       data: Data("<html>Sign in</html>".utf8))
        else { return XCTFail("a document that is not the counts was read as counts") }
    }

    /// **The other side of that line, which `Answer.use` argues for at length
    /// and nothing held.** `{"formulae":{}}` is the endpoint answering — with
    /// nothing in it — and it is entitled to. `InstallCountsParserTests` covers
    /// the parse; what was uncovered is this, the decision to adopt, which is
    /// the only place the difference between "nobody answered" and "the answer
    /// was empty" is acted on. Turn this into a refusal and the document that
    /// says so is never cached, so every launch re-fetches it for ever.
    func testAnEmptyDocumentIsAReadingAndIsAdopted() {
        XCTAssertEqual(PopularityRefresh.answer(statusCode: 200,
                                                data: Data(#"{"formulae":{}}"#.utf8)),
                       .use(InstallCounts(counts: [:])))
    }

    /// And the same for a document whose every entry this parser skips, which
    /// is the shape a published schema change would arrive in: the field is
    /// there, so the endpoint answered.
    func testADocumentWhoseEntriesAreAllUnreadableIsStillAReading() {
        XCTAssertEqual(PopularityRefresh.answer(statusCode: 200,
                                                data: Data(#"{"formulae":{"helm":[{"n":7}]}}"#.utf8)),
                       .use(InstallCounts(counts: [:])))
    }
}
