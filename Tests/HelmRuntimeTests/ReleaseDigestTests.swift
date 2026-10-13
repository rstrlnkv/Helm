import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The updater strips quarantine and the app is ad-hoc signed, so this parser
/// is the whole of "is this the file the release published". Everything here is
/// about refusing, because a false positive runs code.
final class ReleaseDigestTests: XCTestCase {
    private let asset = "Helm-0.7.1-dev.10.zip"
    private let good = String(repeating: "a1b2c3d4", count: 8)   // 64 hex chars


    func testFindsTheDigestForTheAssetItWasAskedAbout() {
        let text = """
        Some prose about the release.

        sha256 Helm-0.7.1-dev.10.zip \(good)
        sha256 Helm-0.7.1-dev.10.dmg \(String(repeating: "f", count: 64))
        """
        XCTAssertEqual(ReleaseDigest.parse(notes: text, asset: asset), good)
    }

    /// A digest published for another file is not a digest for this one — the
    /// dmg and the zip sit in the same release.
    func testADigestForAnotherAssetIsNotUsed() {
        let text = "sha256 Helm-0.7.1-dev.9.zip \(good)"
        XCTAssertNil(ReleaseDigest.parse(notes: text, asset: asset))
    }

    func testNotesWithoutADigestYieldNothing() {
        for text in ["", "### Fixed\n- things", "sha256", "sha256 \(asset)"] {
            XCTAssertNil(ReleaseDigest.parse(notes: text, asset: asset), text)
        }
    }

    /// Truncated, over-long and decorated digests must not be accepted: a
    /// prefix that compares equal to a prefix is not a match.
    func testMalformedDigestsAreRejected() {
        for hex in [String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                    "0x" + String(repeating: "a", count: 62),
                    String(repeating: "g", count: 64)] {
            XCTAssertNil(ReleaseDigest.parse(notes: "sha256 \(asset) \(hex)", asset: asset), hex)
            XCTAssertFalse(ReleaseDigest.isHexDigest(hex), hex)
        }
        // Upper case is a formatting choice, not a malformed digest: it parses,
        // and the comparison normalizes it.
        XCTAssertEqual(ReleaseDigest.parse(notes: "sha256 \(asset) \(good.uppercased())",
                                           asset: asset), good)
    }

    /// The digest is of the bytes on disk, and a single changed byte must fail.
    func testTheFileDigestIsTheFileAndNothingElse() throws {
        let dir = scratchDirectory("digest")

        let file = dir.appendingPathComponent("payload.zip")
        try Data("the real release".utf8).write(to: file)
        let digest = try ReleaseDigest.sha256(ofFileAt: file)
        XCTAssertTrue(ReleaseDigest.isHexDigest(digest))
        XCTAssertTrue(ReleaseDigest.matches(fileAt: file, expected: digest))
        XCTAssertTrue(ReleaseDigest.matches(fileAt: file, expected: digest.uppercased()),
                      "the published digest's case is not the user's problem")

        try Data("the real releasf".utf8).write(to: file)
        XCTAssertFalse(ReleaseDigest.matches(fileAt: file, expected: digest),
                       "a swapped asset of the same length was accepted")
    }

    func testAMissingFileNeverMatches() {
        let gone = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        XCTAssertFalse(ReleaseDigest.matches(fileAt: gone, expected: good))
    }

    // MARK: notes written with CR LF line endings

    /// Release notes can arrive with CR LF line endings, and Swift reads
    /// `"\r\n"` as ONE Character that is not `"\n"`, so a split on `"\n"` finds
    /// no line break in such notes at all.
    private func crlf(_ lines: [String], trailing: Bool) -> String {
        lines.joined(separator: "\r\n") + (trailing ? "\r\n" : "")
    }

    func testADigestLineOpeningCRLFNotesIsFound() {
        let notes = crlf(["sha256 \(asset) \(good)", "", "### Fixed", "- things"], trailing: true)
        XCTAssertEqual(ReleaseDigest.parse(notes: notes, asset: asset), good)
    }

    func testADigestLineInTheMiddleOfCRLFNotesIsFound() {
        let notes = crlf(["Some prose about the release.", "", "sha256 \(asset) \(good)",
                          "sha256 Helm-0.7.1-dev.10.dmg \(String(repeating: "f", count: 64))", "", "More."],
                         trailing: true)
        XCTAssertEqual(ReleaseDigest.parse(notes: notes, asset: asset), good)
    }

    func testADigestLineLastWithATrailingCRLFIsFound() {
        let notes = crlf(["Some prose about the release.", "", "sha256 \(asset) \(good)"], trailing: true)
        XCTAssertEqual(ReleaseDigest.parse(notes: notes, asset: asset), good)
    }

    /// Notes that end on the digest line: CR LF between the lines and nothing
    /// after the last one.
    func testADigestLineLastWithNoTerminatorAfterCRLFLinesIsFound() {
        let notes = crlf(["Some prose about the release.", "", "sha256 \(asset) \(good)"], trailing: false)
        XCTAssertEqual(ReleaseDigest.parse(notes: notes, asset: asset), good)
    }

    /// A lone CR ends a line for a reader that obeys it, and `HelmFailure`
    /// flattens it with the other line breaks for that reason; the digest line
    /// after one is still a line of its own.
    func testADigestLineAfterALoneCRIsFound() {
        let notes = "Some prose about the release.\rsha256 \(asset) \(good)\rMore."
        XCTAssertEqual(ReleaseDigest.parse(notes: notes, asset: asset), good)
    }

    /// The refusals hold in CR LF notes as they do in LF ones. A split that
    /// finds the line breaks must not join what they separate: the digest on the
    /// line after the asset's name is not the asset's digest.
    func testALineBreakInsideTheDigestLineIsNotPartOfIt() {
        for ending in ["\n", "\r\n"] {
            let notes = "sha256 \(asset)\(ending)\(good)\(ending)"
            XCTAssertNil(ReleaseDigest.parse(notes: notes, asset: asset),
                         "line ending \(ending.debugDescription)")
        }
    }

    func testADigestForAnotherAssetInCRLFNotesIsNotUsed() {
        let notes = crlf(["Prose", "sha256 Helm-0.7.1-dev.9.zip \(good)", "More"], trailing: true)
        XCTAssertNil(ReleaseDigest.parse(notes: notes, asset: asset))
    }

    /// The line the release script writes is the line the parser reads.
    func testTheEmittedLineRoundTrips() {
        let line = ReleaseDigest.line(asset: asset, sha256: good)
        XCTAssertEqual(ReleaseDigest.parse(notes: line, asset: asset), good)
    }
}
