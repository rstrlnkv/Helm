import XCTest
@testable import Module_Disk_Engine

/// A `last-scan.json` written by a build that did not have today's fields still
/// opens the module on a ring.
///
/// A defaulted property on a `Codable` payload does not by itself make an older
/// payload decode (Architecture/StateAndLifetime.md § A value read back whole):
/// the synthesised `Decodable` still requires the key, and `JSONDecoder` then
/// drops the whole `ScanStore.Cached` document, costing a fresh walk.
///
/// The tests are written against JSON that omits a key, never a re-encoded
/// value of today's type, which cannot express a document from before the field.
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

    /// The tree is inside `ScanStore.Cached`, and a throw anywhere in the
    /// document takes the whole of it, not only the missing field.
    func testTheWholeCachedTreeSurvivesAMissingKey() throws {
        let document = Data("""
            {"result":\(withoutAdvice),"savedAt":760000000}
            """.utf8)
        let cached = try JSONDecoder().decode(ScanStore.Cached.self, from: document)
        XCTAssertEqual(cached.result.root.name, "Macintosh HD")
        XCTAssertEqual(cached.result.freeBytes, 120_000)
    }

    /// A document with no tree is not a scan; decoded, it would draw a
    /// measurement that was never made.
    func testAResultWithNoTreeIsStillRefused() {
        let data = Data("""
            {"freeBytes":120000,"filesScanned":7,"seconds":1.5,"advice":[]}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScanResult.self, from: data),
                             "a payload with no root decoded into something drawable")
    }

    /// The figures are required, so a truncated write is refused rather than
    /// drawn as a disk holding nothing.
    func testAResultMissingItsFiguresIsRefused() {
        let data = Data("""
            {"root":{"name":"/","path":"/","bytes":1,"isDirectory":true,
             "noAccess":false,"children":[]},"filesScanned":7,"seconds":1.5}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ScanResult.self, from: data),
                             "a scan with no free-space figure decoded as one with none")
    }
}
