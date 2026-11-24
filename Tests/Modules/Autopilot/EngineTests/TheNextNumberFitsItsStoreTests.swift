import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **The number that says which rule set this is comes out of the plist, and it
/// goes back into the plist.** `SealedRules.seal` stores
/// `RuleSeal.next(after:mark:)` as `Int(next)`, and `Int.init(_: UInt64)` traps
/// above `Int.max`.
///
/// The plist is writable by any process running as the user, and an `NSNumber`
/// casts to `Int` by value, so a planted `foldersSeq` of `Int.max` arrives
/// whole. The seal does not stop it: with the `folders` key removed there is
/// nothing to judge, and `RuleSeal.mayOverwrite(nil)` is `true` by design. A
/// number past `Int.max` would crash Helm on the next save, and on every save
/// after, since the value stays in the file.
///
/// **These assert the arithmetic and never call the trap**: a test that reached
/// the conversion would abort the bundle, and XCTest cannot catch a Swift trap.
/// `Int(exactly:)` asks the same question and answers `nil` instead of dying.
final class TheNextNumberFitsItsStoreTests: XCTestCase {

    /// Every number the plist can hand `storedSequence` back, at the two ends
    /// and either side of the one that matters.
    ///
    /// `Int.max` is the trap and `Int.max - 1` is its neighbour, included so the
    /// assertion is about a boundary rather than about one magic value.
    private var plantable: [UInt64] {
        [0, 1, 2, 1_000, UInt64(Int.max) - 2, UInt64(Int.max) - 1, UInt64(Int.max)]
    }

    /// The number a save gets has to be one the store it is written to can hold.
    func testTheNumberTheNextSaveGetsCanBeStored() {
        for stored in plantable {
            let next = RuleSeal.next(after: stored, mark: .absent)

            XCTAssertNotNil(Int(exactly: next), """
                a stored number of \(stored) makes the next one \(next), which is past Int.max — \
                SealedRules.seal writes it with Int(next), and that conversion traps
                """)
        }
    }

    /// The mark is the other way in: `next` is one above **both** the plist's
    /// number and the mark, and the mark comes from a keychain item meant to
    /// name only Helm. This is the belt behind that.
    func testTheNumberIsStorableWhateverTheMarkSays() {
        for mark in plantable {
            let next = RuleSeal.next(after: 0, mark: .at(mark))

            XCTAssertNotNil(Int(exactly: next), """
                a mark of \(mark) makes the next number \(next), which is past Int.max and traps \
                on the way into the store
                """)
        }
    }

    /// The premise, so neither assertion above can pass by the numbers being
    /// somewhere else entirely: the sequence really does count up from what is
    /// stored, and really is one above the mark when the mark is ahead.
    func testTheNumbersTheseAreAboutAreTheOnesTheSaveUses() {
        XCTAssertEqual(RuleSeal.next(after: 4, mark: .absent), 5)
        XCTAssertEqual(RuleSeal.next(after: 4, mark: .at(9)), 10)
        XCTAssertEqual(RuleSeal.next(after: 4, mark: .unavailable), 5,
                       "a keychain that would not answer must not decide the number")
    }

    /// And the plist really can hand `Int.max` over — the reachability half,
    /// asserted through the store the engine reads rather than assumed of
    /// `UserDefaults`.
    ///
    /// `InMemoryKeyValueStore` keeps values the way a file would, `NSNumber` and
    /// all, precisely so that a test of a wrong-typed or extreme stored value is
    /// a test of production and not of the fake.
    func testAPlistCanHandTheSequenceBackAtIntMax() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                    backing: backing)
        store.set(Int.max, for: RuleSeal.sequenceKey)

        XCTAssertEqual(store.int(RuleSeal.sequenceKey, default: 0), Int.max,
                       "the number this is about cannot be planted, so nothing above is reachable")
    }
}
