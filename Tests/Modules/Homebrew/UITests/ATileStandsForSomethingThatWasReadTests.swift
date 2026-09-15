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

    private func info(isCask: Bool = false, homepage: String? = "https://openssl-library.org",
                      tap: String? = "homebrew/core", licence: String? = "Apache-2.0",
                      latest: String? = "3.6.4", installed: String? = "3.6.4",
                      at: Date? = Date(timeIntervalSince1970: 1_757_700_000),
                      onRequest: Bool? = true, deprecated: String? = nil,
                      replacement: String? = nil, siblings: [String] = [],
                      dependencies: [String] = [], caveats: String? = nil) -> PackageInfo {
        PackageInfo(name: "openssl@3", isCask: isCask, desc: "Cryptography and SSL/TLS Toolkit",
                    homepage: homepage, license: licence,
                    tap: tap, latestVersion: latest, installedVersion: installed,
                    installedAt: at, installedOnRequest: onRequest,
                    deprecationReason: deprecated, replacement: replacement,
                    siblings: siblings, dependencies: dependencies, caveats: caveats)
    }

    /// The shapes the initialiser above cannot express: a value the *document*
    /// carried as an empty string.
    ///
    /// **An empty string is not an absent fact, and the tile grid is where that
    /// shows.** `"license": ""` drew a licence tile with nothing under it, which
    /// is exactly what this test exists to forbid — and none of the six shapes
    /// below could see it, because they are built by hand and the emptiness
    /// enters through `brew info`. It is collapsed in `BrewInfoParser` (its
    /// `text` helper), the one place the document is read, so these two shapes
    /// come through the parser: that is what makes the case a statement about
    /// the module rather than about an initialiser call.
    private func blankValueShapes() -> [PackageInfo] {
        // Hand-made, unlike every fixture in `BrewInfoParserTests`: nobody has
        // seen Homebrew print an empty licence, and it does not have to — these
        // are strings out of a document fetched over the network.
        let uninstalled = """
        {"formulae":[{"name":"wget","desc":"","homepage":"","license":"","tap":"  ",
        "deprecated":false,"versions":{"stable":"1.25.0"},"caveats":"","installed":[]}],"casks":[]}
        """
        let installedBlankVersion = """
        {"formulae":[{"name":"wget","license":"Apache-2.0","tap":"homebrew/core",
        "deprecated":false,"versions":{"stable":"1.25.0"},
        "installed":[{"version":"   ","time":1757800000,
        "installed_on_request":true}]}],"casks":[]}
        """
        let shapes = [uninstalled, installedBlankVersion].compactMap {
            BrewInfoParser.parse(Data($0.utf8), isCask: false)
        }
        // Asserted rather than assumed: a fixture the parser refuses drops out
        // of the list, and a loop over nothing passes every assertion in it.
        XCTAssertEqual(shapes.count, 2, "a fixture was refused, so it asserts nothing")
        return shapes
    }

    // MARK: - What an answer earns

    /// An installed formula: what is on disk, when it arrived, and why.
    func testAnInstalledFormulaEarnsItsThreeTiles() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(), sizeBytes: nil)
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
            let facts = PackageFacts.of(info(isCask: true, licence: nil, onRequest: nil), sizeBytes: nil)
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
            let facts = PackageFacts.of(info(at: nil), sizeBytes: nil)
            XCTAssertFalse(facts.contains { $0.label == HbStr.tileInstalledOn },
                           "\(language.rawValue): a package with no recorded install time was "
                           + "given a date tile to fill")
        }
    }

    /// A package that is not installed: the catalogue's version and its licence,
    /// and nothing that claims it is on this Mac.
    func testAPackageThatIsNotInstalledEarnsTheOtherSet() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(installed: nil, at: nil, onRequest: nil), sizeBytes: nil)
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
                                             at: nil, onRequest: nil), sizeBytes: nil)
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
            + blankValueShapes()
        AppLanguage.each { language in
            for shape in shapes {
                for fact in PackageFacts.of(shape, sizeBytes: nil) {
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

    // MARK: - The size is the one tile nobody was told

    /// A figure that was walked earns the last tile, written in the reader's
    /// own units.
    ///
    /// Last on purpose: it is the one fact that arrives after the tier has
    /// already been drawn, and a grid that inserted it anywhere else would move
    /// the tiles around it as it landed.
    func testAWalkedFigureEarnsTheLastTile() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(), sizeBytes: 41_353_216)
            XCTAssertEqual(facts.map(\.label),
                           [HbStr.tileInstalledVersion, HbStr.tileInstalledOn,
                            HbStr.tileHowItGotHere, HbStr.tileOnDisk],
                           "\(language.rawValue): the size did not arrive as the last tile")
            XCTAssertEqual(facts.last?.value, Bytes(41_353_216),
                           "\(language.rawValue): the figure is not the one `Bytes` writes")
        }
    }

    /// And it is written in the app's language rather than the system's — the
    /// same rule the install date carries, read the same way: a formatter with
    /// no locale answers identically in all eight, which is what this has to be
    /// able to fail on.
    func testTheFigureFollowsTheAppsLanguage() {
        var spellings: [AppLanguage: String] = [:]
        AppLanguage.each { language in
            spellings[language] = PackageFacts.of(info(), sizeBytes: 41_353_216)
                .first { $0.label == HbStr.tileOnDisk }?.value
        }
        XCTAssertEqual(spellings.count, AppLanguage.allCases.count)
        XCTAssertGreaterThan(Set(spellings.values).count, 1, """
            all eight languages write the size «\(spellings[.en] ?? "")» — the unit and the             decimal mark are coming from a formatter that answers in the system's language
            """)
    }

    /// **Nothing measured is no tile — never «0 bytes».**
    ///
    /// The walk answers nil for a keg that is missing, one that would not open
    /// and a cask (`HomebrewEngine.size`), and nil is the whole of what the page
    /// is told. A zero drawn here would not read as a gap: it reads as a
    /// measurement, and it says the package occupies nothing at all.
    ///
    /// Asserted against `Bytes(0)` rather than against the digit, because the
    /// spelling is «0 bytes» in one language and «0 байт» in another, and the
    /// question is whether that sentence can appear at all.
    func testAnUnmeasuredSizeEarnsNoTileAtAll() {
        AppLanguage.each { language in
            for shape in [info(), info(isCask: true, licence: nil, onRequest: nil),
                          info(installed: nil, at: nil, onRequest: nil)] {
                let facts = PackageFacts.of(shape, sizeBytes: nil)
                XCTAssertFalse(facts.contains { $0.label == HbStr.tileOnDisk }, """
                    \(language.rawValue): a package nothing was walked for was given a size tile
                    """)
                XCTAssertFalse(facts.contains { $0.value == Bytes(0) }, """
                    \(language.rawValue): the tier draws «\(Bytes(0))» where nothing was                     measured — a figure of nought is a measurement, not a gap
                    """)
            }
        }
    }

    /// A package that is not installed still earns its own two tiles and no
    /// third: there is no keg to walk, and the design says so in words the
    /// tiles do not carry — nothing here stands in for the figure.
    func testAPackageThatIsNotInstalledIsNotGivenAPlaceholder() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(installed: nil, at: nil, onRequest: nil),
                                        sizeBytes: nil)
            XCTAssertEqual(facts.map(\.label), [HbStr.tileVersion, HbStr.tileLicence],
                           "\(language.rawValue): a hit was given a tile for a keg it does not have")
        }
    }

    // MARK: - A block with nothing in it is not a block

    /// **The commonest package there is draws neither of the other two blocks.**
    /// An installed formula somebody asked for, not deprecated, with no other
    /// version lines: `origin` and `notes` were always-present stacks that
    /// resolved to zero height rather than to nothing, so the tier paid its 24 pt
    /// step around each of them where the rhythm is 12.
    ///
    /// Asked of the predicate rather than of the rendered page: `PackageBlocks`
    /// is where the decision lives for the reason `PackageFacts` is, a `body`
    /// being nowhere a test can reach. What this cannot see is the view
    /// forgetting to ask — that is one line in `PackageSecondTier`, and the
    /// price of reaching it is a measured height.
    func testAPackageWithNothingToSayDrawsNeitherBlock() {
        let bare = info(homepage: nil, tap: nil)
        XCTAssertFalse(PackageBlocks.hasOrigin(bare), "an origin line with no origin in it")
        XCTAssertFalse(PackageBlocks.hasNotes(bare),
                       "«somebody asked for it» is not a note — only «it came as a dependency» is")
    }

    /// Either half of the origin line is enough to draw it: a package with a
    /// homepage and no tap is an ordinary answer, and so is the reverse.
    func testEitherHalfOfTheOriginLineKeepsIt() {
        XCTAssertTrue(PackageBlocks.hasOrigin(info(tap: nil)))
        XCTAssertTrue(PackageBlocks.hasOrigin(info(homepage: nil)))
    }

    /// And each note on its own keeps the notes block — including the one that
    /// is read as a *value*: nil is a cask, which records nobody, and only
    /// `false` is something to say.
    func testEachNoteOnItsOwnKeepsTheBlock() {
        XCTAssertTrue(PackageBlocks.hasNotes(info(homepage: nil, tap: nil,
                                                  deprecated: "repo_archived")))
        XCTAssertTrue(PackageBlocks.hasNotes(info(homepage: nil, tap: nil, onRequest: false)))
        XCTAssertTrue(PackageBlocks.hasNotes(info(homepage: nil, tap: nil,
                                                  siblings: ["openssl@4"])))
        XCTAssertFalse(PackageBlocks.hasNotes(info(isCask: true, homepage: nil, tap: nil,
                                                   onRequest: nil)),
                       "a cask records nobody, and that absence is not a note")
    }

    /// A package brew answered nothing measurable about earns no grid at all —
    /// the block is absent rather than an empty row of wells.
    func testAnAnswerWithNothingInItEarnsNoTiles() {
        AppLanguage.each { language in
            let facts = PackageFacts.of(info(licence: nil, latest: nil, installed: nil,
                                             at: nil, onRequest: nil), sizeBytes: nil)
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
            let dated = PackageFacts.of(info(), sizeBytes: nil).first { $0.label == HbStr.tileInstalledOn }
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
