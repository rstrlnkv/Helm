import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **The number that says which rule set this is comes out of the plist, and it
/// goes back into the plist.**
///
/// `SealedRules.seal` computes it with `RuleSeal.next(after:mark:)` and stores it
/// with `store.set(Int(next), for: RuleSeal.sequenceKey)`. The round trip is
/// `UInt64 → Int`, and `Int.init(_: UInt64)` is the *trapping* conversion: for
/// anything above `Int.max` it is `Fatal error: Not enough bits to represent the
/// passed value`, measured on this toolchain (Swift 6.4) rather than reasoned
/// about.
///
/// Which makes the reachable half the question, and it is reachable with no
/// permission at all. `storedSequence` is `store.int("foldersSeq", default: 0)`
/// over `com.helm.app.plist` — the same file the module's own documentation
/// calls "writable by any process running as this user" — and an `NSNumber`
/// casts to `Int` by value, so `<integer>9223372036854775807</integer>` arrives
/// as `Int.max`. `next` then answers `Int.max + 1`.
///
/// The seal does not stand in the way of it. A planted number breaks the MAC
/// over a *stored* rule set, so that save is refused — but with the `folders`
/// key removed there is nothing to judge, `RuleSeal.mayOverwrite(nil)` is `true`
/// by design, and the write runs straight through to the conversion:
///
/// ```
/// defaults delete com.helm.app module.autopilot.folders
/// defaults write  com.helm.app module.autopilot.foldersSeq -int 9223372036854775807
/// ```
///
/// The next rule anybody saves takes Helm down, and the value is still in the
/// file afterwards, so it takes Helm down again. That is the whole of the
/// finding: a crash loop on the one gesture that configures the module,
/// available to anything that can write a preference.
///
/// **These assert the arithmetic and never call the trap**, which is the only
/// shape available: a test that reached `store.set(Int(next))` would abort the
/// bundle and take the other 370 cases with it, and XCTest cannot catch a Swift
/// trap. `Int(exactly:)` asks the same question the conversion asks and answers
/// `nil` instead of dying.
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

    /// And the same question asked of the other half of the answer.
    ///
    /// `next` is one above **both** what the plist says and what the mark says,
    /// so the mark is a second way in. It comes from the keychain, whose item is
    /// meant to name only Helm — this is the belt behind that, and it costs one
    /// line.
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
