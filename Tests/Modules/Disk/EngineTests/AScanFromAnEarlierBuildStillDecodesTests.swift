import XCTest
@testable import Module_Disk_Engine

/// A `last-scan.json` written by a build that did not have today's fields still
/// opens the module on a ring.
///
/// **A `defaulted` property on a `Codable` payload does not, by itself, make an
/// older payload decode** (CLAUDE.md). `ScanResult.advice` carries
/// `= []` in the memberwise initializer and nothing else, so the synthesised
/// `Decodable` went on requiring the key — and `JSONDecoder` gives up on the
/// *whole* document rather than filling in the one field, so `ScanStore.Cached`
/// threw with it and the entire tree was dropped. What that costs is a silent
/// extra minute of walking at the first launch after an update, once per field
/// anybody adds here.
///
/// Its two neighbours already carry the repair with the reason written above
/// them — `DiskEntry.init(from:)` for `isFolded`, `DiskAdvice.init(from:)` for
/// `targets` and `modified` — which is what makes this type the odd one out
/// rather than the first case. The tests below are written against **JSON that
/// omits a key**, never against a re-encoded value of today's type: encoding
/// what we have and decoding it back cannot express a document from before the
/// field existed, and would pass with the repair deleted.
final class AScanFromAnEarlierBuildStillDecodesTests: XCTestCase {

    /// A tree as an earlier build wrote it: no `advice` on the result, no
    /// `isFolded` on the entries.
    private let withoutAdvice = """
        {"root":{"name":"Macintosh HD","path":"/","bytes":4096,"isDirectory":true,
         "noAccess":false,"children":[]},
         "freeBytes":120000,"filesScanned":7,"seconds":1.5}
        """

    func testAResultWithNoAdviceKeyStillDecodes() throws {
        let data = Data(withoutAdvice.utf8)
        let result = try JSONDecoder().decode(ScanResult.self, from: data)
        XCTAssertEqual(result.root.path, "/")
        XCTAssertEqual(result.filesScanned, 7)
        XCTAssertEqual(result.advice, [],
                       "a missing advice list is no advice, not invented advice")
    }

    /// The one that matters: the tree is inside `ScanStore.Cached`, and a throw
    /// anywhere in the document takes the whole thing — the ring, the sizes and
    /// the age label — not merely the field that moved.
    func testTheWholeCachedTreeSurvivesAMissingKey() throws {
        let document = Data("""
            {"result":\(withoutAdvice),"savedAt":760000000}
            """.utf8)
        let cached = try JSONDecoder().decode(ScanStore.Cached.self, from: document)
        XCTAssertEqual(cached.result.root.name, "Macintosh HD")
        XCTAssertEqual(cached.result.freeBytes, 120_000)
    }

    /// And the repair is not "accept anything": a document with no tree in it is
    /// not a scan, and decoding one into an empty ring would put a measurement
    /// on screen that was never made.
    func testAResultWithNoTreeIsStillRefused() {
        let data = Data("""
            {"freeBytes":120000,"filesScanned":7,"seconds":1.5,"advice":[]}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScanResult.self, from: data),
                             "a payload with no root decoded into something drawable")
    }

    /// The fields that were there before `advice` are read outright, so a
    /// truncated write is refused rather than drawn as a disk holding nothing.
    func testAResultMissingItsFiguresIsRefused() {
        let data = Data("""
            {"root":{"name":"/","path":"/","bytes":1,"isDirectory":true,
             "noAccess":false,"children":[]},"filesScanned":7,"seconds":1.5}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScanResult.self, from: data),
                             "a scan with no free-space figure decoded as one with none")
    }
}
