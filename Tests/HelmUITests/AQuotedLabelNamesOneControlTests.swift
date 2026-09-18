import XCTest
import HelmTestSupport
@testable import HelmUI

/// A changelog entry that quotes a control's label must quote the *same*
/// control in all eight languages.
///
/// CLAUDE.md orders the label taken from the string the control itself calls,
/// «or a rename leaves the sentence behind and all seven translations
/// faithfully translate the wrong word», and records that the fix is one key
/// deleted and rewritten in eight files. Nothing held anyone to it: the entry
/// for 0.10.0 said the colour menu ends with «Other…» while the menu draws
/// «Other colour…», and it shipped. The English was the only wrong one — the
/// seven had been read out of Calendar — so no reader of one language could
/// have seen it either.
///
/// **What this compares.** Where an English entry quotes a fragment that is
/// itself a key in `en.lproj` — that is, a string the app really draws — every
/// other language's entry must contain that key's own translation. It does not
/// look at quotation marks outside English: which marks a language uses, and
/// which words it chooses to wrap in them, are `Quoted`'s business and
/// `PunctuationIsTerminologyTests`'. Counting quoted fragments per language was
/// tried first and is not a check: 32 of the 64 quoting entries legitimately
/// quote a different number of things, because Chinese wraps «日历» where
/// English wraps nothing.
///
/// Non-breaking spaces are normalised on both sides. The subject here is which
/// control an entry names, not how the name is spaced; French's spacing is
/// `PunctuationIsTerminologyTests`' subject and has its own counts behind it.
///
/// **What this cannot see.** An entry whose English names a control wrongly and
/// whose seven translations faithfully follow it resolves consistently and
/// passes — that half is closed only by reading an entry against the running
/// app, which is what CLAUDE.md asks for and what no test can do. The defect
/// this catches is the other shape: the one that actually shipped.
final class AQuotedLabelNamesOneControlTests: XCTestCase {

    /// English's own pair, asked of `Quoted` rather than written down here, for
    /// the reason `PunctuationIsTerminologyTests` gives: a second copy of that
    /// ruling in a test is a second thing to keep in step.
    private static let englishMarks: (open: String, close: String) = {
        let sentinel = "\u{1}"
        let parts = Quoted(sentinel, language: .en).components(separatedBy: sentinel)
        return (parts[0], parts[1])
    }()

    /// One entry naming one control, as English writes it.
    private struct Citation: Hashable {
        /// The English entry — which, English being the key, is also the key.
        let entry: String
        /// The label it quotes, which is itself a key in `en.lproj`.
        let cite: String
    }

    /// A citation this check knows about and does not fail on, with the reason.
    ///
    /// Every one of these was found by this check on the day it was written.
    /// None is fixed here: the entries are what a person reads after an update,
    /// and CLAUDE.md holds that composing that text is not the same act as
    /// making a code change. They are listed so the check can be green today and
    /// catch the next one, and so each is a line somebody can work off.
    private struct Excused {
        /// Enough of the entry to name it; the entries themselves run to
        /// paragraphs, and two of these excuse two different labels in one.
        let entryStartsWith: String
        let cite: String
        let reason: String
    }

    private static let excused: [Excused] = [
        // Read against the translations by eye; the finding is specific.
        Excused(entryStartsWith: "A way out of a scan in Disk.",
                cite: "Scan again",
                reason: "German and French quote a different control entirely — "
                      + "„Anderes wählen…“ and « Choisir autre chose… » — so the "
                      + "English and the seven name two different buttons; "
                      + "also missing in es, ja, pt, zh"),
        Excused(entryStartsWith: "Keep Awake says which app is holding the Mac",
                cite: "App",
                reason: "Chinese keeps the English word «App» where the control "
                      + "draws 应用, so a reader looking for it in their own "
                      + "interface finds nothing"),
        Excused(entryStartsWith: "\u{201C}Show in Finder\u{201D} opens the folder",
                cite: "Show in Finder",
                reason: "Japanese spells the label «Finder に表示» where the "
                      + "control draws «Finderに表示» — the label was re-spelled "
                      + "rather than called"),

        // Flagged by this check and not yet read against the running app. The
        // languages are named so nobody re-derives them.
        Excused(entryStartsWith: "A paused rule now says only that it is paused.",
                cite: "Not applying right now",
                reason: "not read against the app yet; missing in es, fr, ja, zh"),
        Excused(entryStartsWith: "An app list the Uninstaller never received",
                cite: "Open Extensions\u{2026}",
                reason: "not read against the app yet; missing in ru"),
        Excused(entryStartsWith: "Duplicates can basket every extra at once",
                cite: "Clear",
                reason: "not read against the app yet; missing in de, es, fr, ja, zh"),
        Excused(entryStartsWith: "Duplicates can basket every extra at once",
                cite: "Select all",
                reason: "not read against the app yet; missing in ja, ru"),
        Excused(entryStartsWith: "Helm no longer asks for your administrator password",
                cite: "Stay awake with the lid closed",
                reason: "not read against the app yet; missing in fr, zh"),
        Excused(entryStartsWith: "Keep Awake takes any duration you like",
                cite: "Indefinite",
                reason: "not read against the app yet; missing in fr"),
        Excused(entryStartsWith: "The sidebar is yours to arrange.",
                cite: "Restore defaults",
                reason: "not read against the app yet; missing in de, es, fr, pt, zh"),
        Excused(entryStartsWith: "\u{201C}Search again\u{201D} no longer starts",
                cite: "Search again",
                reason: "not read against the app yet; missing in ru"),
        Excused(entryStartsWith: "\u{201C}Upgrade all\u{201D} sits in the page",
                cite: "Upgrade all",
                reason: "not read against the app yet; missing in ja, ru, zh"),
    ]

    // MARK: - Reading

    private func table(for language: AppLanguage) throws -> [String: String] {
        let path = try XCTUnwrap(Localized.stringsFile(for: language)?.path,
                                 "no Localizable.strings for \(language.rawValue)")
        let dict = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String],
                                 "\(language.rawValue).lproj did not parse")
        XCTAssertGreaterThan(dict.count, 100, "\(language.rawValue).lproj carries almost nothing")
        return dict
    }

    /// The fragments an English string wraps in English's own marks.
    private func quotedFragments(in text: String) -> [String] {
        let (open, close) = Self.englishMarks
        var found: [String] = []
        var rest = Substring(text)
        while let opened = rest.range(of: open) {
            let after = rest[opened.upperBound...]
            guard let closed = after.range(of: close) else { break }
            found.append(String(after[..<closed.lowerBound]))
            rest = after[closed.upperBound...]
        }
        return found
    }

    /// Every place an English string quotes a label the app actually draws.
    private func citations(in english: [String: String]) -> [Citation] {
        english.keys
            .flatMap { key in
                quotedFragments(in: key)
                    .filter { english[$0] != nil }
                    .map { Citation(entry: key, cite: $0) }
            }
            .sorted { ($0.entry, $0.cite) < ($1.entry, $1.cite) }
    }

    /// A non-breaking space is a space for this comparison.
    private func flattened(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: - The subject happened

    /// **The check has something to check.** A test that looks for a missing
    /// word passes when nothing was read at all, and this one walks a list it
    /// builds itself: an extraction that quietly found nothing would be green
    /// for ever, over a changelog full of quoted labels.
    func testThereAreCitationsToCheckAtAll() throws {
        let english = try table(for: .en)
        let quoting = english.keys.filter { !quotedFragments(in: $0).isEmpty }
        XCTAssertGreaterThan(quoting.count, 20,
                             "almost nothing in en.lproj quotes anything — the marks are "
                             + "probably not the ones `Quoted` answers with")
        XCTAssertGreaterThan(citations(in: english).count, 20,
                             "almost nothing quoted is a string the app draws — the lookup "
                             + "back into the table is not finding keys")
    }

    /// **No excuse outlives what it excuses.** An entry reworded, or a citation
    /// put right, leaves a line here that excuses nothing, and a list that rots
    /// silently is how a check stops being one. A prefix matching two citations
    /// is the same defect read from the other end — it would excuse a second
    /// one nobody decided about.
    func testEveryExcuseStillNamesExactlyOneCitation() throws {
        let all = citations(in: try table(for: .en))
        for excuse in Self.excused {
            let matched = all.filter {
                $0.cite == excuse.cite && $0.entry.hasPrefix(excuse.entryStartsWith)
            }
            XCTAssertEqual(matched.count, 1, """
                the excuse for \(excuse.cite) on "\(excuse.entryStartsWith)…" matches \
                \(matched.count) citations, not one. Its reason was: \(excuse.reason)
                """)
        }
    }

    // MARK: - The check

    func testAQuotedLabelNamesTheSameControlInEveryLanguage() throws {
        var tables: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases { tables[language] = try table(for: language) }
        let english = try XCTUnwrap(tables[.en])

        var offenders: [String] = []

        for citation in citations(in: english) {
            let isExcused = Self.excused.contains {
                $0.cite == citation.cite && citation.entry.hasPrefix($0.entryStartsWith)
            }
            if isExcused { continue }

            for language in AppLanguage.allCases where language != .en {
                guard let table = tables[language] else { continue }
                let label = flattened(table[citation.cite] ?? citation.cite)
                let entry = flattened(table[citation.entry] ?? citation.entry)
                guard !entry.contains(label) else { continue }
                offenders.append("""
                      \(language.rawValue): the entry "\(citation.entry.prefix(48))…" quotes \
                    "\(citation.cite)" in English, but its \(language.rawValue) text does not \
                    carry "\(label)", which is what that control draws in \(language.rawValue)
                    """)
            }
        }

        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) changelog citation(s) name one control in English and another, \
            or none, in a translation. CLAUDE.md: call the same string the control calls, or a \
            rename leaves the sentence behind and all seven translations faithfully translate \
            the wrong word.
            \(offenders.sorted().joined(separator: "\n"))
            """)
    }
}
