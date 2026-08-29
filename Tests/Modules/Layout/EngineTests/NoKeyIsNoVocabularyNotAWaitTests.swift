import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// A port that answers, and one that never does.
private final class GivenSalt: SealKeyPort, @unchecked Sendable {
    private let material: Data
    private(set) var asked = 0
    init(_ byte: UInt8 = 7) { material = Data(repeating: byte, count: 32) }
    func key() -> SealKey? {
        asked += 1
        return SealKey(material: material, firstUse: false)
    }
}

/// The keychain that is there and will not answer — a locked one at login, or
/// an ad-hoc build whose ACL does not match the item it wrote last time.
private final class NoSalt: SealKeyPort, @unchecked Sendable {
    private(set) var asked = 0
    func key() -> SealKey? { asked += 1; return nil }
}

/// Helm is ad-hoc signed, so its identity changes with every build and a
/// keychain ACL written by one never matches the next. That is not a one-off
/// prompt — it is every install. The closed-lid setting was sealed for exactly
/// one commit before the installed build sat behind a system dialog having
/// drawn nothing, and the rule from that day is: seal what is read
/// occasionally, never what `init` reads.
///
/// So the vocabulary's absence has to be ordinary. No key is «no personal
/// vocabulary» — the module as it was before this existed — and never a wait.
final class NoKeyIsNoVocabularyNotAWaitTests: XCTestCase {

    func testConstructingItAsksTheKeychainNothing() {
        let keys = GivenSalt()
        _ = VocabularyStore(directory: scratchDirectory("vocab-init"), keys: keys)
        XCTAssertEqual(keys.asked, 0,
                       "the keychain was read while the store was being built — on an "
                       + "ad-hoc build that is a modal dialog on the launch path")
    }

    func testWithNoKeyNothingIsLearnedAndNothingIsProtected() throws {
        let directory = scratchDirectory("vocab-nokey")
        let keys = NoSalt()
        let store = VocabularyStore(directory: directory, keys: keys)
        store.warm()

        store.putBack("cnjk")
        store.putBack("cnjk")
        XCTAssertFalse(store.leavesAlone("cnjk"),
                       "a word was protected without a key to fingerprint it with")

        // And nothing was written: a file of unsalted words is exactly what
        // this design exists to avoid.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("vocabulary.json").path),
            "a vocabulary file was written with no salt to protect it")
    }

    func testWithAKeyTheSecondPutBackIsARule() {
        let store = VocabularyStore(directory: scratchDirectory("vocab-key"), keys: GivenSalt())
        store.warm()

        store.putBack("cnjk")
        XCTAssertFalse(store.leavesAlone("cnjk"), "once is not a rule")
        store.putBack("cnjk")
        XCTAssertTrue(store.leavesAlone("cnjk"))
        XCTAssertFalse(store.leavesAlone("ldthm"))
    }

    /// It outlives a launch, and the file it leaves says nothing readable.
    func testItSurvivesARelaunchAndTheFileHoldsNoWords() throws {
        let directory = scratchDirectory("vocab-relaunch")
        let first = VocabularyStore(directory: directory, keys: GivenSalt())
        first.warm()
        first.putBack("cnjk")
        first.putBack("cnjk")
        XCTAssertTrue(first.leavesAlone("cnjk"))

        let second = VocabularyStore(directory: directory, keys: GivenSalt())
        second.warm()
        XCTAssertTrue(second.leavesAlone("cnjk"), "what was learned did not survive")

        let text = try String(contentsOf: directory.appendingPathComponent("vocabulary.json"),
                              encoding: .utf8)
        XCTAssertFalse(text.contains("cnjk"), "the word is in the file")
        XCTAssertFalse(text.contains("стол"))
    }

    /// A different Mac's salt is a different file: what one learned tells the
    /// other nothing, which is the whole point of salting rather than hashing.
    func testAnotherSaltDoesNotReadTheFirstOnesLessons() {
        let directory = scratchDirectory("vocab-othersalt")
        let mine = VocabularyStore(directory: directory, keys: GivenSalt(7))
        mine.warm()
        mine.putBack("cnjk")
        mine.putBack("cnjk")

        let theirs = VocabularyStore(directory: directory, keys: GivenSalt(9))
        theirs.warm()
        XCTAssertFalse(theirs.leavesAlone("cnjk"))
    }
}
