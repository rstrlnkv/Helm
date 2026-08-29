import XCTest
@testable import Module_Layout_Engine

/// The module learns from what it got wrong, and from nothing else.
///
/// **The signal is an undo.** Somebody pressing the key to put a word back is
/// saying «I meant what I typed» about that exact word — which is a fact, not
/// an inference from how often they type it. It is also the smallest possible
/// thing to keep: only words the module itself changed ever reach this, so a
/// login, a password fragment or a message nobody touched cannot.
///
/// **It only ever protects a word. It can never convert one.** A personal
/// vocabulary that could permit a conversion the dictionary refused would turn
/// one repeated typo into a rule — and this module rewrites text in other
/// people's apps, so a rule it invented for itself is the last thing it should
/// have. There is deliberately no method here that answers «convert this».
final class WhatThePersonPutBackIsLearnedTests: XCTestCase {

    func testAWordNobodyPutBackIsNotProtected() {
        let vocabulary = PersonalVocabulary()
        XCTAssertFalse(vocabulary.leavesAlone("cnjk"))
    }

    /// Once is an accident — a mis-press, a change of mind, a word that really
    /// was wrong. The module does not rewrite its own rules on one keystroke.
    func testOnceIsNotYetARule() {
        var vocabulary = PersonalVocabulary()
        vocabulary.putBack("cnjk")
        XCTAssertFalse(vocabulary.leavesAlone("cnjk"),
                       "one undo became a rule — a mis-press would teach the module")
    }

    func testTwiceIsARule() {
        var vocabulary = PersonalVocabulary()
        vocabulary.putBack("cnjk")
        vocabulary.putBack("cnjk")
        XCTAssertTrue(vocabulary.leavesAlone("cnjk"))
    }

    func testLearningOneWordSaysNothingAboutAnother() {
        var vocabulary = PersonalVocabulary()
        vocabulary.putBack("cnjk")
        vocabulary.putBack("cnjk")
        XCTAssertFalse(vocabulary.leavesAlone("ldthm"))
    }

    /// **It does not grow for ever.** Somebody who has used this for three
    /// years must not carry a file that grew every time they changed their
    /// mind, so the least-put-back entries go first when it is full.
    func testItForgetsTheLeastPutBackWhenFull() {
        var vocabulary = PersonalVocabulary()
        // One word put back many times, and the cap filled with singles.
        vocabulary.putBack("keepme")
        vocabulary.putBack("keepme")
        vocabulary.putBack("keepme")
        for index in 0..<PersonalVocabulary.limit {
            vocabulary.putBack("filler\(index)")
        }
        XCTAssertLessThanOrEqual(vocabulary.count, PersonalVocabulary.limit)
        XCTAssertTrue(vocabulary.leavesAlone("keepme"),
                      "the word put back three times was dropped for one put back once")
    }

    /// The entries are opaque by the time they arrive: this type never sees a
    /// word, only a fingerprint of one, and its behaviour must not depend on
    /// what the string looks like.
    func testItTreatsItsKeysAsOpaque() {
        var vocabulary = PersonalVocabulary()
        let fingerprint = "9f2c4a1b8e7d6c5a4b3e2d1c0f9a8b7c"
        vocabulary.putBack(fingerprint)
        vocabulary.putBack(fingerprint)
        XCTAssertTrue(vocabulary.leavesAlone(fingerprint))
        XCTAssertFalse(vocabulary.leavesAlone(fingerprint.uppercased()),
                       "a fingerprint was matched loosely — two different words could collide")
    }
}
