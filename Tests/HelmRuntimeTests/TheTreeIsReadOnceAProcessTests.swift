import Foundation
import HelmTestSupport
import XCTest

/// **XCTest builds an instance per test case, so an instance method that reads
/// the tree reads it once per case and not once per class.**
///
/// Two classes were paying that in full.
/// `ATestNamesTheKeychainPortsItBuildsOverTests` walked and parsed `Sources/`
/// five times over and `Tests/` twice more, for one twelve-case class;
/// `NoOrphanTranslationsTests` walked `Sources/` twice for two cases — under a
/// comment that said «both tests below read this and nothing else», which
/// described a cache that did not exist. That sentence is why it survived: a
/// promise written in prose with no test under it reads as a fact.
///
/// So the promise is here instead, and it is about the reading rather than
/// about either caller: whatever asks, the files come off disk once a process.
///
/// **Both halves, and in this order.** «The second ask read nothing» is an
/// absence, and an absence passes when the subject never happened — a reader
/// that returned an empty array would satisfy it perfectly. The first ask is
/// asserted to have really read the directory before the second is asked to
/// have not.
final class TheTreeIsReadOnceAProcessTests: XCTestCase {

    /// Directories no other scan in this bundle asks for, so these tests warm
    /// them themselves. Every scan in the suite names its own key —
    /// `Sources`, `Tests`, `Sources/HelmUI`, four module UI directories — and
    /// the cache is keyed by that string, so a whole-`Sources` scan does not
    /// warm a directory inside it.
    ///
    /// The floors below fail loudly rather than quietly if that stops being
    /// true, which is the only reason it is safe to depend on.
    private static let coldForCounting = "Sources/Modules/Homebrew/UI"
    private static let coldForReadings = "Sources/Modules/Leftovers/UI"

    func testTheSecondAskReadsNoFileOffDisk() throws {
        let start = SwiftSource.filesRead
        let first = try SwiftSource.code(under: Self.coldForCounting)
        let byFirst = SwiftSource.filesRead - start
        let second = try SwiftSource.code(under: Self.coldForCounting)
        let bySecond = SwiftSource.filesRead - start - byFirst

        XCTAssertGreaterThan(first.count, 0,
                             "\(Self.coldForCounting) held no Swift file, so neither "
                             + "assertion below is about anything")
        XCTAssertEqual(byFirst, first.count,
                       "the first ask read \(byFirst) file(s) off disk for "
                       + "\(first.count) source file(s) — either the counter has stopped "
                       + "counting or something else in this bundle already warmed "
                       + "\(Self.coldForCounting), and this test needs a colder directory")
        XCTAssertEqual(bySecond, 0,
                       "the second ask read \(bySecond) file(s) again, so the tree is read "
                       + "once per test case and a class of a dozen pays for it a dozen times")
        XCTAssertEqual(second.map(\.path), first.map(\.path))
        XCTAssertEqual(second.map(\.text), first.map(\.text))
    }

    /// The two readings share a walk and must not share an answer.
    ///
    /// A cache keyed on the directory alone would hand whichever caller came
    /// second the first one's text, and the direction that hides is the one that
    /// matters: `uncommented` served `code`'s output blanks every literal in the
    /// tree, so `L("Off")` reads as `L("")` and the orphan scan condemns every
    /// key at once — or, the other way round, `code` served `uncommented`'s
    /// output puts every literal's punctuation back in front of the call-site
    /// scanners.
    func testTheTwoReadingsAreKeptApart() throws {
        let code = try SwiftSource.code(under: Self.coldForReadings)
        let kept = try SwiftSource.uncommented(under: Self.coldForReadings)

        XCTAssertGreaterThan(code.count, 0, "\(Self.coldForReadings) held no Swift file")
        XCTAssertEqual(kept.map(\.path), code.map(\.path),
                       "the two readings disagree about which files are there")
        // `XCTAssertFalse` rather than `XCTAssertNotEqual`, which prints both
        // sides — here two whole directories of Swift, 88 KB into the log of a
        // run that already knows what it wants to say.
        XCTAssertFalse(kept.map(\.text) == code.map(\.text),
                       "both readings of \(Self.coldForReadings) came back identical, so "
                       + "one of them was served from the other's cache — or this "
                       + "directory has stopped holding a string literal, and the test "
                       + "needs one that does")
    }

    /// And the reading each one is: the literal survives `uncommented` and does
    /// not survive `code`, asked of the tree rather than of a fixture.
    ///
    /// `ACommentIsNotAUseOfAKeyTests` pins this on hand-written source. This
    /// pins that the cached whole-directory readers are those same two readings
    /// and not, say, both wired to the same one.
    func testEachCachedReadingIsTheOneItIsNamedFor() throws {
        let kept = try SwiftSource.uncommented(under: Self.coldForReadings)
            .map(\.text).joined(separator: "\n")
        let code = try SwiftSource.code(under: Self.coldForReadings)
            .map(\.text).joined(separator: "\n")

        let literal = try XCTUnwrap(Self.aLiteral(in: kept),
                                    "no string literal survived `uncommented` over "
                                    + "\(Self.coldForReadings)")
        // The subject before the absence. The sample is picked by splitting on
        // quotes, and one picked wrongly would be missing from *both* readings
        // — passing the assertion below while saying nothing at all.
        XCTAssertTrue(kept.contains("\"\(literal)\""),
                      "«\(literal)» is not a literal of \(Self.coldForReadings); the sample "
                      + "was mis-picked, so the assertion below would be about nothing")
        XCTAssertFalse(code.contains(literal),
                       "«\(literal)» survived `code`, which blanks the insides of literals")
    }

    /// The first literal of at least four letters, so the search below is about
    /// a word rather than about a space.
    private static func aLiteral(in source: String) -> String? {
        source.components(separatedBy: "\"")
            .enumerated()
            .first { $0.offset % 2 == 1 && $0.element.count >= 4
                     && $0.element.allSatisfy { $0.isLetter || $0 == " " } }?
            .element
    }
}
