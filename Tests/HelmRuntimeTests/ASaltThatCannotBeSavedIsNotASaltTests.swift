import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The salt file's own paragraph made a promise the code did not keep.
///
/// > If the file cannot be written the tags stay stable and unsalted rather
/// > than changing every launch, because a tag that means nothing across
/// > restarts is useless for the triage it exists for.
///
/// What it did instead: draw sixteen fresh random bytes, hand them to
/// `PrivateFile.write`, **drop the answer**, and salt with them regardless. So a
/// salt file that could not be written gave every launch a different salt — the
/// exact behaviour the paragraph says was ruled out, and the one that destroys
/// the property the tag exists for. `app#1a2f` on Monday and `app#c40b` on
/// Tuesday are the same application, and nobody reading the log can know it.
///
/// It is the shape ARCHITECTURE.md keeps finding: a promise written in prose
/// with no test under it. This is the test.
final class ASaltThatCannotBeSavedIsNotASaltTests: XCTestCase {

    private var file: URL!

    override func setUp() {
        super.setUp()
        file = scratchDirectory("salt-promise").appendingPathComponent("salt")
    }

    /// A write that refuses leaves no salt at all — never a fresh one per launch.
    func testARefusedWriteLeavesTheTagsUnsalted() {
        let salt = Redact.loadOrCreateSalt(at: file, writing: { _, _ in false })
        XCTAssertTrue(salt.isEmpty,
                      "a salt that was never written down is a different salt every launch, "
                      + "which makes every tag in the log incomparable with yesterday's")
    }

    /// The promise itself: two launches that both fail to save agree.
    ///
    /// Asserted over the *tag* and not only over the bytes, because the bytes
    /// are the mechanism and the comparable tag is the thing being promised.
    func testTwoLaunchesThatCannotSaveStillAgree() {
        let first = Redact.loadOrCreateSalt(at: file, writing: { _, _ in false })
        let second = Redact.loadOrCreateSalt(at: file, writing: { _, _ in false })
        XCTAssertEqual(first, second,
                       "the salt moved between two launches that both failed to save it")
        XCTAssertEqual(Redact.tag("com.acme.tool", prefix: "app", salt: first),
                       Redact.tag("com.acme.tool", prefix: "app", salt: second),
                       "one application tagged two ways across two launches")
    }

    /// A write that lands is salted, and salted with what it was handed.
    func testAWriteThatLandsIsTheSaltThatIsUsed() {
        var handed: Data?
        let salt = Redact.loadOrCreateSalt(at: file, writing: { data, _ in
            handed = data
            return true
        })
        XCTAssertEqual(salt.count, 16, "a saved salt is the sixteen bytes that were drawn")
        XCTAssertEqual(handed.map { [UInt8]($0) }, salt,
                       "the bytes used to tag are not the bytes that were written down, so the "
                       + "next launch reads a salt this one never used")
    }

    /// An existing file is read, and nothing is written over it.
    func testAnExistingSaltIsKeptAndNotRewritten() throws {
        let existing = Data((0..<16).map { UInt8($0) })
        try existing.write(to: file)
        var wrote = false
        let salt = Redact.loadOrCreateSalt(at: file, writing: { _, _ in wrote = true; return true })
        XCTAssertEqual(salt, [UInt8](existing))
        XCTAssertFalse(wrote, "the salt was rewritten, so every launch replaces the one before it")
    }

    /// A short file is not a salt — it is rewritten, and the answer still decides.
    ///
    /// The length check exists because a truncated write leaves a file that
    /// reads back as *something*. Paired with a refusing write here, because
    /// that is the run in which a truncated file is likeliest.
    func testATruncatedSaltFileIsNotTakenAsOne() throws {
        try Data([1, 2, 3]).write(to: file)
        let salt = Redact.loadOrCreateSalt(at: file, writing: { _, _ in false })
        XCTAssertTrue(salt.isEmpty, "three bytes were taken for a sixteen-byte salt")
    }
}
