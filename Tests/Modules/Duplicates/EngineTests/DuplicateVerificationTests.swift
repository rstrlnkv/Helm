import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// The last thing standing between a stale offer and a deleted file.
final class DuplicateVerificationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = scratchDirectory("verify")
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    func testTwoIdenticalFilesVerify() throws {
        let a = try write("a.bin", "the same bytes")
        let b = try write("b.bin", "the same bytes")
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: b), .identical)
    }

    /// The case the whole thing exists for: the scan said identical, the file
    /// was edited since, and the removal must not go ahead.
    func testAnEditedFileIsChanged() throws {
        let a = try write("a.bin", "the same bytes")
        let b = try write("b.bin", "the same bytes!")
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: b), .changed)
    }

    /// Same length, different content — the case a size comparison alone would
    /// wave through, and the reason both files are read in full.
    func testSameSizeDifferentContentIsChanged() throws {
        let a = try write("a.bin", "aaaaaaaa")
        let b = try write("b.bin", "bbbbbbbb")
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: b), .changed)
    }

    /// A hard link is one file wearing two names. Trashing "one of them"
    /// removes the only copy there is, and frees nothing.
    func testAHardLinkIsRefused() throws {
        let a = try write("a.bin", "shared content")
        let b = directory.appendingPathComponent("b.bin").path
        try FileManager.default.linkItem(atPath: a, toPath: b)
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: b), .changed)
    }

    /// A file that vanished between the scan and the press is not a licence to
    /// delete its partner's twin: an answer that could not be obtained is not
    /// an answer in favour.
    func testAMissingFileIsUnreadable() throws {
        let a = try write("a.bin", "content")
        let gone = directory.appendingPathComponent("not-here.bin").path
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: gone), .unreadable)
        XCTAssertEqual(DuplicateVerification.verify(remove: gone, keep: a), .unreadable)
    }

    /// Two empty files are identical, and nothing about reading zero bytes
    /// should turn that into a refusal.
    func testTwoEmptyFilesVerify() throws {
        let a = try write("a.bin", "")
        let b = try write("b.bin", "")
        XCTAssertEqual(DuplicateVerification.verify(remove: a, keep: b), .identical)
    }
}
