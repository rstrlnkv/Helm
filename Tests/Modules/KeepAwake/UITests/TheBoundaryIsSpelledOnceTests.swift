import XCTest
import HelmUI
@testable import Module_KeepAwake_UI

/// One phrase, three sentences, eight languages — and it used to be twenty-four
/// spellings.
///
/// The battery floor is named by the row under the slider, by the panel's notice
/// and by the hero's. Each wrote it out again, and that is how «below» survived in
/// one of them for ten days after it had been corrected in another: the boundary
/// is **inclusive** (`BatteryGuard.shouldDeactivate` is `percent <= threshold`),
/// which is 以下 and 及以下 in the two languages that have a strict operator to get
/// wrong. The three are composed from `KAStr.atPercentOrLess` now, and this is
/// what says they still are.
///
/// Per language, with the override, for the reason the file next door gives: the
/// suite runs in whichever language this machine is set to, so a check that reads
/// `AppLanguage.current` inspects one of the eight and reports on all of them.
final class TheBoundaryIsSpelledOnceTests: XCTestCase {

    private static let floor = 20

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    private func inEveryLanguage(_ body: (AppLanguage) -> Void) {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            body(language)
        }
    }

    /// Every sentence that names the floor contains the phrase that names it.
    func testAllThreeSentencesContainTheBoundaryPhrase() {
        inEveryLanguage { language in
            let at = KAStr.atPercentOrLess(Self.floor)
            for (name, sentence) in [("the row's note", KAStr.belowPercent(Self.floor)),
                                     ("the panel's notice",
                                      KAStr.stoppedByBatteryShort(Self.floor)),
                                     ("the hero's notice", KAStr.stoppedByBattery(Self.floor))] {
                XCTAssertTrue(sentence.lowercased().contains(at.lowercased()),
                              "\(language.rawValue): \(name) spells the boundary its own way — "
                              + "«\(sentence)» does not contain «\(at)». Three spellings is how "
                              + "one of them came to name an operator the code does not use")
            }
        }
    }

    /// The spelling each language uses for **«and everything under it»** — the
    /// inclusive marker, in the positive.
    ///
    /// Six of these eight are checked nowhere else, and that is the hole this
    /// table fills. Every other check on this phrase is either a *negative* —
    /// `TheNoticeNamesTheGuardsOperatorTests` asserts the strict operator is
    /// absent — or a *containment*: the three sentences carry whatever the one
    /// declaration says. A phrase that names no boundary at all satisfies both.
    /// «при 20 % и ниже» → «до 20 %», or «не выше 20 %», or the bare «20 %»,
    /// composed into all three sentences, passes every other assertion in these
    /// two files: it carries the figure, it keeps its per-language space before
    /// the sign, it is still one declaration, the hero still says more than the
    /// panel — and it no longer says the session ends *at* the figure.
    ///
    /// ja and zh keep their own test below rather than only appearing here,
    /// because those are the two where the marker has a wrong twin (未満 / 低于)
    /// and the pair is the point: 及以下 present is a different fact from 低于
    /// absent, and a string can fail one without failing the other.
    private static func inclusiveMarker(in language: AppLanguage) -> String {
        switch language {
        case .en: return "or less"
        case .ru: return "и ниже"
        case .es: return "o menos"
        case .fr: return "ou moins"
        case .de: return "oder weniger"
        case .ja: return "以下"
        case .zh: return "及以下"
        case .pt: return "ou menos"
        }
    }

    /// The marker is in the phrase, and in every sentence composed from it.
    ///
    /// Asserted against each sentence directly rather than against the phrase
    /// alone: the two sides of a check must not both read one thing, and «the
    /// phrase says *or less*» plus «the sentences contain the phrase» is one
    /// reading with a second test's conclusion standing in for the other half.
    /// A sentence that stopped composing would then be reported by that test and
    /// not by this one, which is how a person reads a failure as a naming
    /// quibble rather than as a sentence that lost its boundary.
    func testEveryLanguageSaysOrLessInThePhraseAndInEverySentenceDrawnFromIt() {
        inEveryLanguage { language in
            let marker = Self.inclusiveMarker(in: language)
            for (name, sentence) in [("the phrase itself", KAStr.atPercentOrLess(Self.floor)),
                                     ("the row's note", KAStr.belowPercent(Self.floor)),
                                     ("the panel's notice",
                                      KAStr.stoppedByBatteryShort(Self.floor)),
                                     ("the hero's notice", KAStr.stoppedByBattery(Self.floor))] {
                XCTAssertTrue(sentence.lowercased().contains(marker.lowercased()),
                              "\(language.rawValue): \(name) does not say «\(marker)» — "
                              + "«\(sentence)». `BatteryGuard.shouldDeactivate` is "
                              + "`percent <= threshold`, so the session ends **at** "
                              + "\(Self.floor) %, and a sentence that names the figure without "
                              + "the inclusive marker promises a Mac that is still awake there")
            }
        }
    }

    /// And the table above is eight spellings rather than one repeated.
    ///
    /// An inline table wins outright over the `.lproj` files, so a language that
    /// never reaches `L` gives English eight times — and were every row of this
    /// table «or less», the check above would pass on eight English readings of a
    /// phrase no translator had ever seen. Distinct, non-empty: a hole in the
    /// table is a `contains("")`, which is true of every string there is.
    func testTheMarkerTableIsEightDistinctSpellings() {
        let markers = AppLanguage.allCases.map { Self.inclusiveMarker(in: $0) }
        XCTAssertFalse(markers.contains(where: \.isEmpty),
                       "an empty marker matches every sentence: \(markers)")
        XCTAssertEqual(Set(markers).count, AppLanguage.allCases.count,
                       "two languages are looked up by the same marker, so one of them is "
                       + "checked against another language's word: \(markers)")
    }

    /// And it is the *inclusive* operator in the two languages where that is a
    /// word rather than a sign. This is the correction that had to be made twice.
    func testJapaneseAndChineseUseTheInclusiveOperator() {
        AppLanguage.override = .ja
        XCTAssertTrue(KAStr.atPercentOrLess(Self.floor).contains("以下"))
        XCTAssertFalse(KAStr.atPercentOrLess(Self.floor).contains("未満"))
        AppLanguage.override = .zh
        XCTAssertTrue(KAStr.atPercentOrLess(Self.floor).contains("及以下"))
        XCTAssertFalse(KAStr.atPercentOrLess(Self.floor).contains("低于"))
    }

    /// The space before the sign is **per language**, which is what the note on
    /// these functions used to get wrong by calling it macOS's own everywhere.
    /// Counted over the loctables macOS ships: ru, de, fr and es put a no-break
    /// space there; pt-BR joins, 143 to 0; ja and zh join as a matter of course;
    /// English joins.
    func testTheSpaceBeforeTheSignIsPerLanguage() {
        for language in [AppLanguage.ru, .de, .fr, .es] {
            AppLanguage.override = language
            XCTAssertTrue(KAStr.atPercentOrLess(Self.floor).contains("\u{00A0}%"),
                          "\(language.rawValue) wraps a figure away from its per-cent sign")
        }
        for language in [AppLanguage.en, .pt, .ja, .zh] {
            AppLanguage.override = language
            let phrase = KAStr.atPercentOrLess(Self.floor)
            XCTAssertFalse(phrase.contains("\u{00A0}%"),
                           "\(language.rawValue) spaces its per-cent sign where its own system "
                           + "tables join it: «\(phrase)»")
            XCTAssertTrue(phrase.contains("\(Self.floor)%"), "\(language.rawValue): «\(phrase)»")
        }
    }

    /// The figure reaches every one of them — the phrase is a function of the
    /// floor, and a table that dropped the interpolation would read as a sentence
    /// about no number at all.
    func testEveryLanguageNamesTheFigure() {
        inEveryLanguage { language in
            XCTAssertTrue(KAStr.stoppedByBattery(37).contains("37"),
                          "\(language.rawValue) drew the notice without the floor in it")
        }
    }

    /// The long form is the one that says what to do, in all eight. Without this
    /// the hero could be handed the panel's sentence in seven languages and
    /// nothing would say so — English is the key, so English cannot show it.
    func testTheHerosNoticeIsLongerThanThePanelsInEveryLanguage() {
        inEveryLanguage { language in
            XCTAssertGreaterThan(KAStr.stoppedByBattery(Self.floor).count,
                                 KAStr.stoppedByBatteryShort(Self.floor).count + 4,
                                 "\(language.rawValue): the hero says no more than the panel, so "
                                 + "the way out of the veto is written down nowhere")
        }
    }

    // MARK: - The lid's two lengths

    /// The settings row says what the panel's subtitle says, and then how to undo
    /// it. Two lengths of one wording: the subtitle is a fragment in a « · » list
    /// inside a 320 pt card and cannot take a second sentence, and the row is the
    /// only place the way back out of a machine-wide setting can be written down.
    func testTheLidNoteOpensOnTheSentenceThePanelDraws() {
        inEveryLanguage { language in
            let short = KAStr.sleepIsOffNow
            let long = KAStr.sleepIsOffNote
            XCTAssertTrue(long.hasPrefix(short),
                          "\(language.rawValue): the row and the panel say sleep is off in two "
                          + "different ways — «\(long)» does not open on «\(short)»")
            XCTAssertGreaterThan(long.count, short.count + 8,
                                 "\(language.rawValue): the row adds no way back out of a "
                                 + "setting that outlives the process")
        }
    }

    /// And both name the *scope*, which is why the English key changed: «Sleep is
    /// off right now» reads as Keep Awake holding an assertion, which is what every
    /// other row on that page does and is nothing like this.
    func testBothLengthsSayWhoseSleepIsOff() {
        for language in [AppLanguage.en, .ru, .de, .fr, .es, .pt] {
            AppLanguage.override = language
            XCTAssertTrue(KAStr.sleepIsOffNow.contains("Mac"),
                          "\(language.rawValue) does not say the whole Mac: "
                          + "«\(KAStr.sleepIsOffNow)»")
        }
    }
}
