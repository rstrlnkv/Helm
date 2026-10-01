import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// The Log page's search, fed what the round-three repair did not feed it: the
/// header rule in every language, a query typed the way a keyboard types it,
/// a query in another case or with blanks around it, a query that names one
/// card's header and another card's line; and the split, fed three
/// «terminating» lines in a row and a run an older build opened with a bare
/// «logging enabled».
///
/// The rule under test (`LogSearch.matches(header:_:drawnTime:)`): a header
/// finds its card only by what it says whole — the version, «Helm <version>»,
/// or the day and minute as drawn.
///
/// Each case holds a rule, and its assertion message says what a person would
/// see if the rule broke.
final class TheLogHeaderSearchUnderEveryLanguageTests: XCTestCase {

    /// 14:13:20 UTC on 21 September 2026.
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func line(_ seconds: Double, _ level: LogLevel = .info, _ category: String = "vpn",
                      _ message: String = "network state changed; re-reading") -> LogEntry {
        LogEntry(date: base.addingTimeInterval(seconds), level: level, category: category,
                 message: message)
    }

    private func start(_ seconds: Double, _ version: String) -> LogEntry {
        line(seconds, .info, "app", "Helm \(version) started")
    }

    private func build(_ lines: [LogEntry], query: String, language: AppLanguage) -> LogPresentation {
        LogPresentation.build(lines, minimumLevel: .info, categories: [], query: query,
                              language: language.rawValue, calendar: utc)
    }

    /// What a keyboard produces for a drawn string: every blank a plain space.
    /// Foundation's short time style puts a narrow no-break space (U+202F)
    /// before «PM» in English, and no key on a Mac keyboard types one.
    private func typed(_ drawn: String) -> String {
        String(String.UnicodeScalarView(drawn.unicodeScalars.map {
            $0.properties.isWhitespace ? " " : $0
        }))
    }

    // MARK: - The header rule in every language

    /// **The day and minute as a person types them find the card, in every
    /// language.** The rule is «the day and minute as drawn, whole»; the tests
    /// that hold it build the query from `HelmDates.dayAndMinute` itself, so
    /// both sides read one declaration. A person reads the header and types it:
    /// in English the drawn string is «9/21/26, 2:13 PM» with a narrow no-break
    /// space before «PM», and the keyboard types an ordinary one — so the
    /// comparison reads every blank as a plain space (`LogSearch.plainBlanks`).
    /// The header is not selectable, so it cannot be copied instead.
    ///
    /// A card with no version is the case the time search exists for (it has
    /// no version to search by), so the fixture's card is the run after
    /// «terminating». The control: the drawn string itself finds the card.
    func testTheDayAndMinuteAsAKeyboardTypesThemFindTheirCardInEveryLanguage() {
        let lines = [start(0, "0.11.1-dev.13"), line(10),
                     line(20, .info, "app", "terminating"),
                     line(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
        let split = LogSessions.split(lines)
        guard split.count == 2, let headless = split.last else {
            return XCTFail("the fixture split into \(split.count) card(s), not 2")
        }
        XCTAssertNil(headless.version, "the fixture's second card has a version")
        var unreachable: [String] = []
        AppLanguage.each { language in
            let drawn = HelmDates.dayAndMinute(headless.lines[0].date)
            XCTAssertEqual(build(lines, query: drawn, language: language).cards.map(\.id), [headless.id],
                           "\(language.rawValue): the control — the drawn «\(drawn)» did not find its card")
            let keyboard = typed(drawn)
            let found = build(lines, query: keyboard, language: language).cards.map(\.id)
            if found != [headless.id] {
                let odd = drawn.unicodeScalars.filter { $0.properties.isWhitespace && $0 != " " }
                    .map { String(format: "U+%04X", $0.value) }
                unreachable.append("\(language.rawValue): «\(keyboard)» found \(found.count) card(s); "
                                   + "the header draws \(odd) where the keyboard types a space")
            }
        }
        XCTAssertTrue(unreachable.isEmpty, """
            the day and minute typed as a person reads them off the header find no card — \
            \(unreachable.joined(separator: "; "))
            """)
    }

    /// **Case and blanks around a whole header do not change what it finds, in
    /// every language.** The version in capitals, «helm» in lower case, a query
    /// with a space or a tab around it — each is the whole header and finds the
    /// one card; a doubled space inside is not the drawn words and finds none.
    func testAWholeHeaderInAnotherCaseOrWithBlanksAroundItFindsItsCardInEveryLanguage() {
        let lines = [start(0, "0.11.1-dev.13"), line(10),
                     start(100, "0.11.1-dev.14"), line(110)]
        AppLanguage.each { language in
            let lang = language.rawValue
            for query in ["0.11.1-DEV.14", "helm 0.11.1-dev.14", "HELM 0.11.1-Dev.14",
                          "  Helm 0.11.1-dev.14 ", "\tHelm 0.11.1-dev.14\n"] {
                XCTAssertEqual(build(lines, query: query, language: language).cards.map(\.session.version),
                               ["0.11.1-dev.14"], "\(lang): «\(query)» did not find the one card it names")
            }
            let drawn = HelmDates.dayAndMinute(lines[0].date)
            for query in [drawn.uppercased(), drawn.lowercased(), " \(drawn)  "] {
                XCTAssertEqual(build(lines, query: query, language: language).cards.map(\.session.version),
                               ["0.11.1-dev.13"], "\(lang): «\(query)» did not find the card drawn «\(drawn)»")
            }
            // Not the drawn words: nothing is found, and nothing header-only is drawn.
            let page = build(lines, query: "Helm  0.11.1-dev.14", language: language)
            XCTAssertTrue(page.cards.isEmpty, "\(lang): a doubled space inside matched \(page.cards.count) card(s)")
        }
    }

    /// **A query that is one card's header and another card's line draws
    /// both, each for what it matched.** «0.11.0» is the version of the first
    /// card and a word in a line of the second: the first is drawn with no row
    /// (its header matched), the second with that line and no other; the copy
    /// carries both start lines and the one line; the footer counts the first
    /// card's start line (it says «0.11.0» itself) and the line — two.
    func testAQueryThatIsOneCardsHeaderAndAnotherCardsLineDrawsBoth() {
        let lines = [start(0, "0.11.0"), line(10),
                     start(100, "0.12.0"), line(110),
                     line(120, .warn, "updates", "skipped 0.11.0: already installed"),
                     line(130)]
        AppLanguage.each { language in
            let lang = language.rawValue
            let page = build(lines, query: "0.11.0", language: language)
            XCTAssertEqual(page.cards.map(\.session.version), ["0.11.0", "0.12.0"],
                           "\(lang): the header match and the line match did not both draw")
            guard page.cards.count == 2 else { return }
            XCTAssertTrue(page.cards[0].rows.isEmpty && page.cards[0].startup.isEmpty,
                          "\(lang): the card found by its header drew a line that does not say «0.11.0»")
            XCTAssertEqual(page.cards[1].rows.flatMap(\.lines).map(\.message) + page.cards[1].startup.flatMap(\.lines).map(\.message),
                           ["skipped 0.11.0: already installed"], "\(lang)")
            XCTAssertEqual(page.lines.map(\.message),
                           ["Helm 0.11.0 started", "Helm 0.12.0 started", "skipped 0.11.0: already installed"],
                           "\(lang): the copy")
            XCTAssertEqual(page.shown, 2, "\(lang): the footer")
        }
    }

    // MARK: - The split

    /// **Three «terminating» in a row stay with the launch they end**, and the
    /// first other line after them opens a run of its own; a «terminating»
    /// that follows some other line is not a pair and stays where it is.
    func testThreeTerminatingLinesInARowStayWithTheLaunchTheyEnd() {
        let quit = { (at: Double) in self.line(at, .info, "app", "terminating") }
        let three = [start(0, "0.11.1-dev.14"), line(0.1), quit(600), quit(600.049), quit(600.1),
                     start(900, "0.11.1-dev.15"), line(900.1)]
        XCTAssertEqual(LogSessions.split(three).map(\.lines.count), [5, 2],
                       "three «terminating» lines drew a card of their own")
        let orphan = [start(0, "0.11.1-dev.14"), quit(600), quit(600.049), quit(600.1),
                      line(601, .info, "memory", "sample")]
        XCTAssertEqual(LogSessions.split(orphan).map(\.lines.count), [4, 1])
        let apart = [start(0, "0.11.1-dev.14"), quit(600), line(601, .info, "memory", "sample"), quit(700)]
        XCTAssertEqual(LogSessions.split(apart).map(\.lines.count), [2, 2],
                       "a «terminating» after another run's line left that run")
        // A tail that begins on the pair: its head card holds all three.
        let head = [quit(600), quit(600.049), quit(600.1), start(900, "0.11.1-dev.15")]
        XCTAssertEqual(LogSessions.split(head).map(\.lines.count), [3, 1])
    }

    /// **A run an older build opened with a bare «logging enabled» is not
    /// joined by a newer build's «logging enabled (version)».** Builds before
    /// the version was written spelled the on edge bare; a build that writes
    /// «logging enabled (0.12.0)» is newer than any build that wrote a bare
    /// one, and a version change is a relaunch. So a versioned on edge
    /// answering a «logging disabled» in a run a bare line opened is another
    /// launch's — decidable from the file, unlike a bare on edge after a
    /// versioned run, which is left whole (`LogSessions.opensNewRun`). This is
    /// the shape of one file that straddles the update on a stable Mac that had
    /// logging switched on by hand: the old build's run, then today's.
    func testARunABareLoggingEnabledOpenedIsNotJoinedByAVersionedOne() {
        let lines = [start(0, "0.10.0"), line(10), line(20, .info, "app", "terminating"),
                     line(3_600, .info, "app", "logging enabled"),
                     line(3_610, .warn, "vpn", "yesterday's warning"),
                     line(3_620, .info, "app", "logging disabled"),
                     line(90_000, .info, "app", "logging enabled (0.12.0)"),
                     line(90_010, .warn, "vpn", "today's warning")]
        let split = LogSessions.split(lines)
        let holding = split.first { $0.lines.contains { $0.message == "today's warning" } }
        XCTAssertFalse(holding?.lines.contains { $0.message == "yesterday's warning" } ?? true, """
            today's warning, written by 0.12.0, shares a card with the run an older build opened \
            with a bare «logging enabled» a day earlier: the card holds \
            \(holding?.lines.map(\.message) ?? []) and its badge counts \
            \(holding?.count(of: .warn) ?? 0) warnings for one launch
            """)
    }

    // MARK: - Another language's clock, an exact build, an older warning

    /// **The day and minute as another language draws them find no card.** The
    /// header draws its time in the app's language, and the rule is «as
    /// drawn»: under German «21.09.26, 19:13» is on the card and «9/21/26, 7:13 PM»
    /// is not, so a query copied from a report written in another language
    /// must draw no header-only card, while the page's own spelling finds it.
    /// Both sides are spelled with the language named outright, and the page is
    /// built the way `LogView` builds it — the language and calendar defaulted.
    /// The subject is asserted first: at least one pair of languages spells the
    /// same moment differently, or the negative half proves nothing.
    func testTheDayAndMinuteAsAnotherLanguageDrawsThemFindNoCard() {
        let lines = [start(0, "0.11.1-dev.13"), line(10),
                     line(20, .info, "app", "terminating"),
                     line(7_200, .info, "memory", "sample: 88 MB (+65 MB) — no phases running")]
        let split = LogSessions.split(lines)
        guard split.count == 2, let headless = split.last, let launch = split.first else {
            return XCTFail("the fixture split into \(split.count) card(s), not 2")
        }
        var differing = 0
        var wrong: [String] = []
        AppLanguage.each { language in
            for session in [launch, headless] {
                let moment = session.lines[0].date
                let own = HelmDates.dayAndMinute(moment, language: language.rawValue)
                let page = LogPresentation.build(lines, minimumLevel: .info, categories: [], query: own)
                if page.cards.map(\.id) != [session.id] {
                    wrong.append("\(language.rawValue): its own «\(own)» found \(page.cards.count) card(s)")
                }
                for other in AppLanguage.allCases where other != language {
                    let foreign = HelmDates.dayAndMinute(moment, language: other.rawValue)
                    guard foreign.compare(own, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
                    else { continue }
                    differing += 1
                    let found = LogPresentation.build(lines, minimumLevel: .info, categories: [],
                                                      query: foreign).cards.count
                    if found != 0 {
                        wrong.append("\(language.rawValue): «\(foreign)» (as \(other.rawValue) draws it) "
                                     + "found \(found) card(s) over a header that draws «\(own)»")
                    }
                }
            }
        }
        XCTAssertGreaterThan(differing, 0, "no two languages spell the moment differently — nothing was tried")
        XCTAssertTrue(wrong.isEmpty, wrong.joined(separator: "; "))
    }

    /// **An exact build with a `-dev` suffix is found whole, and its
    /// neighbours by prefix are not.** «0.11.1-dev.1» is a prefix of
    /// «0.11.1-dev.14» and «0.11.1» of both; each names exactly one card. A
    /// part that is no card's whole version finds none, and the version still
    /// draws its header-only card under a level filter, which the start line
    /// alone never earns.
    func testAnExactDevVersionFindsItsCardAndNotTheCardsItPrefixes() {
        let versions = ["0.11.1", "0.11.1-dev.1", "0.11.1-dev.14", "0.11.1-dev.140"]
        var lines: [LogEntry] = []
        for (index, version) in versions.enumerated() {
            lines += [start(Double(index) * 100, version), line(Double(index) * 100 + 10)]
        }
        XCTAssertEqual(LogSessions.split(lines).map(\.version), versions, "the fixture's split changed")
        AppLanguage.each { language in
            let lang = language.rawValue
            for version in versions {
                for query in [version, "Helm \(version)", version.uppercased()] {
                    XCTAssertEqual(build(lines, query: query, language: language).cards.map(\.session.version),
                                   [version], "\(lang): «\(query)»")
                }
            }
            for query in ["0.11.1-dev", "-dev.14", "dev.14", "0.11.1-dev.14.", "Helm0.11.1-dev.14",
                          "v0.11.1-dev.14"] {
                let page = build(lines, query: query, language: language)
                XCTAssertTrue(page.cards.isEmpty, """
                    \(lang): «\(query)» drew \(page.cards.map { $0.session.version ?? "nil" }) — no card's \
                    header says it whole and no line holds it as a row
                    """)
            }
            let filtered = LogPresentation.build(lines, minimumLevel: .warn, categories: [],
                                                  query: "0.11.1-dev.14", language: lang, calendar: utc)
            XCTAssertEqual(filtered.cards.map(\.session.version), ["0.11.1-dev.14"],
                           "\(lang): under «Warnings» the named build drew no card")
            XCTAssertEqual(filtered.shown, 0, "\(lang): under «Warnings» the footer counts a line nobody sees")
        }
    }

    /// **A warning with no site that quotes a start line is drawn, not hidden in
    /// a header.** Builds before `v0.7.2-dev.1` wrote a warning with no source
    /// site (`git tag --contains f008e352`, the commit that added it), and a
    /// crash that tears a warning cuts its site off: either way the entry has
    /// no site, so the reading that tells a glued start from a quote cannot tell
    /// them apart (it can for `warn` and `error` lines that carry one). Such an
    /// entry is read as a launch, and its header draws a day, a minute and a
    /// version, never the warning's words — so a start line that carries a
    /// warning is the card's first row as well (`LogSession.startIsARow`). Held:
    /// the card's badge counts no warning that no row on it shows, and under
    /// «Warnings» every warning of the tail is on a row.
    ///
    /// Two shapes, both site-less: an older build's warning quoting a copied
    /// start line, and a warning a crash tore, glued to the next launch's
    /// start (read through `LogSeed`, as the page reads it).
    func testAWarningWithNoSiteGluedToOrQuotingAStartLineIsStillDrawn() {
        let zone = TimeZone(identifier: "UTC")!
        let quoted = "2026-09-21 14:25:00.000 [info] [app] Helm 9.9.9 started"
        let older = [start(0, "0.9.0"), line(10),
                     line(60, .warn, "autopilot", "refused a file named \(quoted)"),
                     line(120)]
        let torn = "2026-09-21 14:13:20.000 [info] [app] Helm 0.11.1-dev.13 started\n"
            + "2026-09-21 14:20:00.000 [warn] [vpn] never connected after 30 s  (VPNEngi"   // the crash
            + "2026-09-21 14:25:00.000 [info] [app] Helm 0.11.1-dev.14 started\n"
            + "2026-09-21 14:25:00.100 [info] [host] enable vpn\n"
            + "2026-09-21 14:30:00.000 [info] [vpn] network state changed; re-reading\n"
        let seeded = LogSeed.entries(from: torn, startedMidFile: false, dated: base,
                                     using: LogSeed.Stamps(timeZone: zone))
        XCTAssertEqual(seeded.count, 4, "the parse itself changed: \(seeded.map(\.message))")
        var hidden: [String] = []
        for (shape, lines) in [("an older build's quoting warning", older), ("a torn warning", seeded)] {
            let warnings = lines.filter { $0.level == .warn }
            XCTAssertEqual(warnings.count, 1, "\(shape): the fixture holds \(warnings.count) warnings")
            XCTAssertTrue(warnings.allSatisfy { $0.site == nil }, "\(shape): the warning has a site")
            let page = build(lines, query: "", language: .en)
            for card in page.cards {
                let drawn = (card.startup + card.rows).flatMap(\.lines).filter { $0.level == .warn }.count
                if card.warnings != drawn {
                    hidden.append("\(shape): the card «Helm \(card.session.version ?? "nil")» says "
                                  + "\(card.warnings) warning(s) and draws \(drawn)")
                }
            }
            let underWarnings = LogPresentation.build(lines, minimumLevel: .warn, categories: [], query: "",
                                                      language: "en", calendar: utc)
            let rows = Set(underWarnings.cards.flatMap { ($0.startup + $0.rows).flatMap(\.lines) }.map(\.id))
            for warning in warnings where !rows.contains(warning.id) {
                hidden.append("\(shape): under «Warnings» «\(warning.message.prefix(40))…» is on no row "
                              + "(\(underWarnings.cards.count) card(s) drawn)")
            }
        }
        XCTAssertTrue(hidden.isEmpty, """
            a warning read as a launch's header is counted and not shown — \(hidden.joined(separator: "; "))
            """)
    }
}
