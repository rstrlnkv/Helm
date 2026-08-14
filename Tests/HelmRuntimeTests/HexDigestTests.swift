import XCTest
import CryptoKit
@testable import HelmRuntime

/// The one spelling of a digest, and the reason it may not drift.
///
/// `SettingSeal.mac` compares what this returns against a string an *earlier
/// build* wrote into somebody's settings, and `ReleaseDigest.matches` against a
/// string a release note published. So the guard is not "it looks like hex": it
/// is that the answer equals the `String(format: "%02x", …)` line these four
/// call sites used to spell by hand, for every byte there is.
final class HexDigestTests: XCTestCase {

    /// The line this replaced, kept here on purpose: a test whose two sides read
    /// one shared constant proves nothing, so the old implementation is written
    /// out rather than called.
    private func theWayItUsedToBeSpelled(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    func testEveryByteReadsExactlyTheWayItUsedTo() {
        let all = (UInt8.min...UInt8.max).map { $0 }
        XCTAssertEqual(HexDigest.string(of: all), theWayItUsedToBeSpelled(all))
    }

    /// Byte by byte as well as in a run: a two-digit byte and a one-digit byte
    /// next to each other is how a missing pad hides — `0a0b` against `ab`.
    func testEachByteOnItsOwnIsTwoLowercaseDigits() {
        for byte in UInt8.min...UInt8.max {
            let hex = HexDigest.string(of: [byte])
            XCTAssertEqual(hex, theWayItUsedToBeSpelled([byte]))
            XCTAssertEqual(hex.count, 2, "\(byte) was not padded to two digits")
            XCTAssertFalse(hex.contains(where: \.isUppercase))
        }
    }

    /// A `SHA256Digest` is not an array, and the point of taking a `Sequence` is
    /// that no caller has to make it one.
    func testADigestIsAcceptedWhereItIsProduced() {
        let digest = SHA256.hash(data: Data("helm".utf8))
        XCTAssertEqual(HexDigest.string(of: digest), theWayItUsedToBeSpelled(Array(digest)))
        XCTAssertTrue(ReleaseDigest.isHexDigest(HexDigest.string(of: digest)),
                      "the updater would refuse a digest spelled this way")
    }

    func testNoBytesIsTheEmptyString() {
        XCTAssertEqual(HexDigest.string(of: [UInt8]()), "")
    }
}
