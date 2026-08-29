import Foundation
import HelmRuntime
import XCTest
@testable import Module_Layout_Engine

/// What reaches the personal vocabulary is a fingerprint, never a word.
///
/// The file it lands in says «this exact word was put back», and nothing more:
/// no list to read, no order to reconstruct, no way to go from the file to the
/// text. That costs the ability to show somebody what Helm has learned, and it
/// is worth it for a module that sees every keystroke on the Mac.
final class AFingerprintIsNotAWordTests: XCTestCase {

    private let salt = SealKey(material: Data(repeating: 7, count: 32), firstUse: false)
    private let otherSalt = SealKey(material: Data(repeating: 9, count: 32), firstUse: false)

    func testTheSameWordAlwaysGivesTheSameFingerprint() {
        XCTAssertEqual(WordFingerprint.of("cnjk", salt: salt),
                       WordFingerprint.of("cnjk", salt: salt))
    }

    func testDifferentWordsGiveDifferentFingerprints() {
        XCTAssertNotEqual(WordFingerprint.of("cnjk", salt: salt),
                          WordFingerprint.of("ldthm", salt: salt))
    }

    /// **The word is not in the fingerprint.** The obvious failure would be a
    /// «fingerprint» that is the word with something appended.
    func testTheWordDoesNotSurviveInIt() throws {
        let print = try XCTUnwrap(WordFingerprint.of("пароль", salt: salt))
        XCTAssertFalse(print.contains("пароль"))
        XCTAssertFalse(print.lowercased().contains("парол"))
        XCTAssertEqual(print.count, 64, "not a SHA-256 in hex")
    }

    /// **Another Mac's file says nothing about this one.** Without the salt the
    /// fingerprint would be a plain hash, and a plain hash of a short word is a
    /// dictionary lookup away from the word.
    func testAnotherSaltGivesAnotherFingerprint() {
        XCTAssertNotEqual(WordFingerprint.of("cnjk", salt: salt),
                          WordFingerprint.of("cnjk", salt: otherSalt))
    }

    /// Putting `Cnjk` back has to protect `cnjk`: it is the same word to the
    /// person, and the module compares what was typed.
    func testCaseDoesNotMakeItANewWord() {
        XCTAssertEqual(WordFingerprint.of("Cnjk", salt: salt),
                       WordFingerprint.of("cnjk", salt: salt))
        XCTAssertEqual(WordFingerprint.of("CNJK", salt: salt),
                       WordFingerprint.of("cnjk", salt: salt))
    }

    /// Whitespace around a word is not part of it.
    func testItIsTrimmed() {
        XCTAssertEqual(WordFingerprint.of("  cnjk\n", salt: salt),
                       WordFingerprint.of("cnjk", salt: salt))
    }

    /// Nothing to fingerprint is nil, not the fingerprint of an empty string —
    /// which would otherwise become an entry every empty word could match.
    func testNothingIsNotAWord() {
        XCTAssertNil(WordFingerprint.of("", salt: salt))
        XCTAssertNil(WordFingerprint.of("   ", salt: salt))
    }
}
