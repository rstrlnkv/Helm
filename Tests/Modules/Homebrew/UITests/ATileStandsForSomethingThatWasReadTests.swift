import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Every tile in the package view's second tier stands for a fact brew
/// actually answered.**
///
/// `PackageInfo`'s fields are optional for reasons that happen constantly, not
/// rarely: a cask's document carries no licence and no record of who asked for
/// it, a package that is not installed has no install date, and `brew info` can
/// answer a document with any of them missing. A grid built to a fixed shape
/// fills those holes with something — a dash, an empty line, a zero — and each
/// of those reads on the page as a fact: "Homebrew was asked and had nothing to
/// say", or worse, a figure.
///
/// So the tiles are a list rather than a layout, and this is the test that can
/// see it. Parameterised by language throughout, because this Mac runs in
/// Russian and a bare assertion about a visible string exercises one of eight
/// (CLAUDE.md, `Tests/Support/EachLanguage.swift`).
final class ATileStandsForSomethingThatWasReadTests: XCTestCase {

    private func info(isCask: Bool = false, licence: String? = "Apache-2.0",
                      latest: String? = "3.6.4", installed: String? = "3.6.4",
                      at: Date? = Date(timeIntervalSince1970: 1_757_700_000),
                      onRequest: Bool? = true, deprecated: String? = nil,
                      replacement: String? = nil, siblings: [String] = [],
                      dependencies: [String] = [], caveats: String? = nil) -> PackageInfo {
        PackageInfo(name: "openssl@3", isCask: isCask, desc: "Cryptography and SSL/TLS Toolkit",
                    homepage: "https://openssl-library.org", license: licence,
                    tap: "homebrew/core", latestVersion: latest, installedVersion: installed,
                    installedAt: at, installedOnRequest: onRequest,
                    deprecationReason: deprecated, replacement: replacement,
                    siblings: siblings, dependencies: dependencies, caveats: caveats)
    }

    // MARK: - What an answer earns

    /// An installed formula: what is on disk, when it arrived, and why.
    func testAnInstalledFormulaEarnsItsThreeTiles() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info())
            XCTAssertEqual(facts.map(\.label),
                           [HbStr.tileInstalledVersion, HbStr.tileInstalledOn,
                            HbStr.tileHowItGotHere],
                           "\(language.rawValue): the tiles an installed formula earns have moved")
            XCTAssertEqual(facts.first?.value, "3.6.4")
            XCTAssertEqual(facts.last?.value, HbStr.installedOnRequest)
        }
    }

    /// A cask records no licence and no record of who asked for it, so it earns
    /// two tiles rather than three with one of them blank.
    func testACaskIsNotGivenATileForWhatItDoesNotRecord() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(isCask: true, licence: nil, onRequest: nil))
            XCTAssertEqual(facts.map(\.label),
                           [HbStr.tileInstalledVersion, HbStr.tileInstalledOn],
                           "\(language.rawValue): a cask was given a tile for a fact its own "
                           + "document does not carry")
        }
    }

    /// The install time is missing from a document often enough to matter — a
    /// Cellar restored from a backup, a formula linked by hand.
    func testAnUndatedInstallEarnsNoDateTile() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(at: nil))
            XCTAssertFalse(facts.contains { $0.label == HbStr.tileInstalledOn },
                           "\(language.rawValue): a package with no recorded install time was "
                           + "given a date tile to fill")
        }
    }

    /// A package that is not installed: the catalogue's version and its licence,
    /// and nothing that claims it is on this Mac.
    func testAPackageThatIsNotInstalledEarnsTheOtherSet() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(installed: nil, at: nil, onRequest: nil))
            XCTAssertEqual(facts.map(\.label), [HbStr.tileVersion, HbStr.tileLicence],
                           "\(language.rawValue): the tiles a search hit earns have moved")
            XCTAssertEqual(facts.first?.value, "3.6.4",
                           "the version a hit shows is the catalogue's — it has no other")
            XCTAssertFalse(facts.contains { $0.label == HbStr.tileInstalledVersion }, """
                \(language.rawValue): a package that is not installed was given an \
                «installed version» tile
                """)
        }
    }

    /// And a hit with neither — a cask brew knows no licence for — earns one
    /// tile, not two with a gap.
    func testAHitWithNoLicenceEarnsOneTile() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(isCask: true, licence: nil, installed: nil,
                                             at: nil, onRequest: nil))
            XCTAssertEqual(facts.map(\.label), [HbStr.tileVersion],
                           "\(language.rawValue): a licence nobody answered became a tile")
        }
    }

    /// The rule the four cases above are each an instance of, said once over
    /// every shape of answer this module can hold.
    func testNoTileEverCarriesAnEmptyValue() {
        let shapes = [info(), info(isCask: true, licence: nil, onRequest: nil), info(at: nil),
                      info(installed: nil, at: nil, onRequest: nil),
                      info(isCask: true, licence: nil, latest: nil, installed: nil, at: nil,
                           onRequest: nil),
                      info(licence: nil, latest: nil, installed: nil, at: nil, onRequest: nil)]
        AppLanguage.each { language in
            for shape in shapes {
                for fact in PackageFacts.of(shape) {
                    XCTAssertFalse(fact.label.trimmingCharacters(in: .whitespaces).isEmpty,
                                   "\(language.rawValue): a tile with no label")
                    XCTAssertFalse(fact.value.trimmingCharacters(in: .whitespaces).isEmpty, """
                        \(language.rawValue): the tile «\(fact.label)» carries nothing, which \
                        reads as Homebrew having been asked and having had no answer
                        """)
                }
            }
        }
    }

    /// A package brew answered nothing measurable about earns no grid at all —
    /// the block is absent rather than an empty row of wells.
    func testAnAnswerWithNothingInItEarnsNoTiles() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(licence: nil, latest: nil, installed: nil,
                                             at: nil, onRequest: nil))
            XCTAssertTrue(facts.isEmpty,
                          "\(language.rawValue): \(facts.count) tile(s) were drawn for an answer "
                          + "with no fact in it")
        }
    }

    // MARK: - The date is in the reader's language

    /// The install date goes through `HelmDates.day`, which is keyed by the
    /// app's language — a `DateFormatter` built with no locale answers in the
    /// *system's*, so on a Mac outside Helm's eight the page would be English
    /// with somebody else's dates spliced into it.
    ///
    /// Read as a difference between two languages rather than against a literal:
    /// a locale-less formatter gives the same string in all eight, which is
    /// exactly what this has to be able to fail on.
    func testTheInstallDateFollowsTheAppsLanguage() {
        var spellings: [AppLanguage: String] = [:]
        AppLanguage.each { language in
            let dated = PackageFacts.of(info()).first { $0.label == HbStr.tileInstalledOn }
            spellings[language] = dated?.value
            XCTAssertNotNil(dated, "\(language.rawValue): no install date tile to read")
        }
        XCTAssertEqual(spellings.count, AppLanguage.allCases.count)
        XCTAssertGreaterThan(Set(spellings.values).count, 1, """
            all eight languages spell the install date «\(spellings[.en] ?? "")» — the value is \
            coming from a formatter that answers in the system's language rather than the app's
            """)
        XCTAssertNotEqual(spellings[.ru], spellings[.ja],
                          "Russian and Japanese write the same date the same way")
    }

    // MARK: - A deprecation reason is not a machine token

    /// The one token this Mac produces today, mapped in every language.
    ///
    /// `repo_archived` is what `brew info --json=v2 --formula -- periphery`
    /// answers with here (Homebrew 7.0.1, 2026-09-15). Asserted as "not the
    /// token" rather than against a literal sentence, so the check is about the
    /// mapping existing in all eight rather than about one wording.
    func testTheReasonThisMacProducesIsASentenceInEveryLanguage() {
        AppLanguage.each { language in
            let said = HbStr.deprecationReason("repo_archived")
            XCTAssertFalse(said.contains("repo_archived"), """
                \(language.rawValue): the page shows «\(said)» — a machine token out of a JSON \
                document, put in front of somebody as an explanation
                """)
            XCTAssertFalse(said.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue): the reason came back empty")
        }
    }

    /// Every token Homebrew's own enumeration carries, in every language.
    ///
    /// The list is read out of `/opt/homebrew/Library/Homebrew/deprecate_disable.rb`
    /// (Homebrew 7.0.1, 2026-09-15) — the formula set and the cask set, which
    /// share `unmaintained` and `unreachable`. Written out here rather than read
    /// off that file at test time: the file belongs to Homebrew and may not
    /// exist on a machine running this suite, and a test that skips when it is
    /// absent is a guard that cannot fail on the Mac that has no brew.
    func testEveryTokenHomebrewEnumeratesHasASentence() {
        let tokens = ["does_not_build", "no_license", "repo_archived", "repo_removed",
                      "unmaintained", "unreachable", "unsupported", "deprecated_upstream",
                      "versioned_formula", "checksum_mismatch", "discontinued", "moved_to_mas",
                      "no_longer_available", "no_longer_meets_criteria", "fails_gatekeeper_check"]
        AppLanguage.each { language in
            for token in tokens {
                let said = HbStr.deprecationReason(token)
                // Not `said.contains(token)`: four of these tokens are ordinary
                // words — `discontinued`, `unmaintained`, `unreachable`,
                // `unsupported` — and a real English sentence about any of them
                // contains the word, so that predicate reports a correct mapping
                // as a fault in the one language where `L()` answers with the
                // key. What is actually being asked is whether the mapping is
                // there at all: the fallback is the only way a token reaches the
                // page, so a sentence that is not the fallback is a sentence.
                XCTAssertNotEqual(said, HbStr.brewsOwnReason(token),
                                  "\(language.rawValue): \(token) falls through to Homebrew's "
                                  + "own word, so the page shows the token")
                XCTAssertFalse(said.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(language.rawValue): \(token) came back empty")
            }
            // Distinct sentences, not one sentence fifteen times: a `default`
            // that swallowed the whole switch would pass every assertion above
            // in English, where `L()` answers with the key itself.
            XCTAssertEqual(Set(tokens.map { HbStr.deprecationReason($0) }).count, tokens.count,
                           "\(language.rawValue): two of Homebrew's reasons read identically")
        }
    }

    /// And a reason this build has never seen keeps Homebrew's own word rather
    /// than a translation somebody guessed.
    ///
    /// Two shapes reach here: a token upstream added after this release, and a
    /// formula that deprecated itself with a sentence of its own instead of a
    /// token — `deprecate!` takes free text.
    func testAnUnknownReasonIsCarriedThroughVerbatim() {
        AppLanguage.each { language in
            for raw in ["unreliable_upstream_signature", "the tap that served it is gone"] {
                let said = HbStr.deprecationReason(raw)
                XCTAssertTrue(said.contains(raw), """
                    \(language.rawValue): «\(raw)» was dropped on the way to the page — the note \
                    then says a package is deprecated and nothing about why
                    """)
                XCTAssertNotEqual(said, raw,
                                  "\(language.rawValue): the raw token is shown as though Helm "
                                  + "were the one saying it")
                XCTAssertEqual(said, HbStr.brewsOwnReason(raw),
                               "\(language.rawValue): an unmapped reason is said some other way "
                               + "than as Homebrew's own word")
            }
        }
    }
}
