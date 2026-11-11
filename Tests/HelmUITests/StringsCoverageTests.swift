import XCTest
import HelmTestSupport
@testable import HelmUI

/// The string catalogs, read as data — the files are what ships, and a word that never made it into
/// one is the failure worth catching. Every catalog is read through `ModuleCatalogs.all()`: the kit's,
/// each module's, the host's and the changelog's. A catalog's symbols are internal to its target and
/// `Bundle.module` inside a test target is the test's own bundle, so the file is the only honest witness.
///
/// No keyed table stands outside the catalogs: `testNoStringKeepsAnInlineTable` says so about the source
/// (the words `Architecture/Localization.md` names as kept in Swift are switches it does not read), and
/// the build refuses a key a call names that the catalog does not carry — a missing *language* it does
/// not, and an identifier shows on screen where English would have, which is why the eight-languages
/// method below cannot go.
final class StringsCoverageTests: XCTestCase {

    /// The kit's catalog is read, and is the kit's: `ModuleCatalogs.all()` throws when the file is
    /// missing, and this says what a pass means. 105 plain keys were measured in the kit when it
    /// moved; a floor of 90 is a guard against a read that has stopped finding the symbols.
    func testTheKitsCatalogIsRead() throws {
        let kit = try XCTUnwrap(try ModuleCatalogs.all().first { $0.module == "HelmUI" },
                                "no catalog named HelmUI was read")
        XCTAssertEqual(kit.path, ModuleCatalogs.kitPath)
        XCTAssertGreaterThanOrEqual(kit.strings.count, 90,
                                    "the kit's catalog carries \(kit.strings.count) symbols — the read lost them")
        XCTAssertTrue(try ModuleCatalogs.all().contains { $0.module == "HelmApp" },
                      "the host's catalog was not read")
        XCTAssertTrue(try ModuleCatalogs.all().contains { $0.module == "Changelog" },
                      "the changelog's catalog was not read")
    }

    /// **All eight languages in every catalog, none empty, none marked anything but `translated`.**
    /// A catalog editor writes «needs_review» for a value somebody has not looked at, and the build
    /// ships it all the same. Replaces the `.lproj` pair (every English text in every other language,
    /// no empty value): the catalog's symbol is the key, and each is asked for all eight.
    func testEveryCatalogSymbolCarriesTheEightLanguages() throws {
        let catalogs = try ModuleCatalogs.all()
        XCTAssertGreaterThanOrEqual(catalogs.count, 12, "only \(catalogs.count) catalog(s) were read")
        var offenders: [String] = []
        var symbols = 0
        for catalog in catalogs {
            XCTAssertFalse(catalog.strings.isEmpty, "\(catalog.path) carries no symbols")
            for (symbol, values) in catalog.strings {
                symbols += 1
                for language in AppLanguage.allCases {
                    guard let value = values[language.rawValue] else {
                        offenders.append("\(catalog.module).\(symbol): no \(language.rawValue)")
                        continue
                    }
                    if value.isEmpty { offenders.append("\(catalog.module).\(symbol): empty \(language.rawValue)") }
                    let state = catalog.states[symbol]?[language.rawValue] ?? ""
                    if state != "translated" {
                        offenders.append("\(catalog.module).\(symbol): \(language.rawValue) is «\(state)»")
                    }
                }
            }
        }
        XCTAssertGreaterThan(symbols, 1000, "only \(symbols) symbols were read, so a pass means nothing")
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) catalog value(s) are missing or unfinished:\n"
                      + offenders.sorted().prefix(40).joined(separator: "\n"))
    }

    /// The places of the placeholders in a value, in order: `%@` takes the next place, `%2$@` its own.
    /// `["1", "2"]` for `%@ of %@` and for `%1$@ of %2$@`, `["2", "1"]` for a value that says them
    /// the other way round — a translation may reorder, and must not lose or invent one.
    static func placeholderPlaces(_ text: String) -> [Int] {
        var places: [Int] = []
        var next = 1
        for match in text.matches(of: /%(?:(\d+)\$)?@/) {
            if let position = match.1.flatMap({ Int($0) }) {
                places.append(position)
            } else {
                places.append(next)
                next += 1
            }
        }
        return places
    }

    /// **A catalog value holds the placeholders of its English, by place.** A translation that lost its
    /// `%@` is non-empty, `translated` and reads fine, and drops the timer's value or, for Screenshots'
    /// `nameTemplate`, the time from a saved file's name. A reordered value (`%2$@ … %1$@`) is not a
    /// defect, and a count of `%@` alone would call it one. The walk must have met a reordered value
    /// and the two Screenshots keys, or it saw nothing.
    func testEveryCatalogLanguageKeepsTheEnglishPlaceholders() throws {
        var offenders: [String] = []
        var met: Set<String> = []
        for catalog in try ModuleCatalogs.all() {
            for (symbol, values) in catalog.strings {
                guard let english = values["en"] else { continue }
                let expected = Self.placeholderPlaces(english).sorted()
                if !expected.isEmpty { met.insert("\(catalog.module).\(symbol)") }
                for language in AppLanguage.allCases {
                    let got = values[language.rawValue].map(Self.placeholderPlaces)?.sorted() ?? []
                    if got != expected {
                        offenders.append("\(catalog.module).\(symbol): \(language.rawValue) has places \(got), en has \(expected)")
                    }
                }
            }
        }
        XCTAssertTrue(met.isSuperset(of: ["Screenshots.timerOn", "Screenshots.nameTemplate"]),
                      "the walk did not meet Screenshots' %@ keys; met: \(met.sorted())")
        XCTAssertGreaterThan(met.count, 60, "only \(met.count) key(s) with a placeholder were met — "
                             + "the template keys of the modules and the host are not being read")
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) catalog value(s) differ from English in their placeholders:\n"
                      + offenders.sorted().prefix(40).joined(separator: "\n"))
    }

    func testThePlaceholderReaderCountsPlacesNotMarks() {
        XCTAssertEqual(Self.placeholderPlaces("%@ of %@"), [1, 2])
        XCTAssertEqual(Self.placeholderPlaces("%1$@ of %2$@"), [1, 2])
        XCTAssertEqual(Self.placeholderPlaces("%2$@ 個中 %1$@"), [2, 1])
        XCTAssertEqual(Self.placeholderPlaces("no argument, 100%"), [])
        XCTAssertEqual(Self.placeholderPlaces("%1$@"), [1])
    }

    /// What a value holds that is neither a placeholder nor a literal percent sign, by the one rule
    /// the format string follows: **a value with arguments writes a literal `%` as `%%`; a value
    /// without writes it single** (`100% готово` prints as it is, `100%%` prints two marks). Measured on
    /// the copy the day it was decided; a bare `%` beside an argument is read as the start of a
    /// conversion, and `%%` in a value with none prints twice.
    static func percentOffences(_ value: String) -> [String] {
        let hasArguments = !placeholderPlaces(value).isEmpty
        if hasArguments {
            let rest = value.replacing(/%(?:\d+\$)?@/, with: "").replacing("%%", with: "")
            return rest.contains("%") ? ["a bare % beside a placeholder"] : []
        }
        return value.contains("%%") ? ["%% in a value with no placeholder"] : []
    }

    func testNoBarePercentBesideAnArgumentAndNoDoubleOneWithout() throws {
        var offenders: [String] = []
        var met = 0
        for catalog in try ModuleCatalogs.all() {
            for (symbol, values) in catalog.strings {
                for (language, value) in values {
                    if value.contains("%") { met += 1 }
                    for offence in Self.percentOffences(value) {
                        offenders.append("\(catalog.module).\(symbol) \(language): \(offence)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(met, 100, "only \(met) value(s) with a % were met — the walk is not reading the catalogs")
        XCTAssertTrue(offenders.isEmpty, offenders.sorted().prefix(40).joined(separator: "\n"))
    }

    func testThePercentRuleCatchesBothWaysToBreakIt() {
        XCTAssertEqual(Self.percentOffences("at %@%% or less"), [])
        XCTAssertEqual(Self.percentOffences("at %@% or less").count, 1)
        XCTAssertEqual(Self.percentOffences("100% done"), [])
        XCTAssertEqual(Self.percentOffences("100%% done").count, 1)
    }

    /// One English text is one word, in the whole of Helm. A word in the kit and in a module catalog is
    /// two translations of one text, free to drift apart — and a catalog's symbols are internal, so the
    /// other module cannot reach the copy: a shared word lives in the kit, `HelmWord`. A second meaning
    /// takes a different English. A value that holds a placeholder is exempt (its argument makes it a
    /// different sentence), and so are the per-form keys of one word (`wordsPutRightFew` and `…Many`
    /// are English's one `words put right`, and differ in Russian): one stem, one catalog.
    func testOneEnglishTextIsOneWordAcrossEveryCatalog() throws {
        var homes: [String: [String]] = [:]
        for entry in try ModuleCatalogs.entries(for: .en) where Self.placeholderPlaces(entry.english).isEmpty {
            homes[entry.english, default: []].append(entry.name)
        }
        XCTAssertGreaterThan(homes.count, 300, "only \(homes.count) English texts were read")
        let repeated = homes.filter { $0.value.count > 1 && !Self.areFormsOfOneWord($0.value) }
            .sorted { $0.key < $1.key }
        XCTAssertTrue(repeated.isEmpty,
                      "\(repeated.count) English text(s) are written under two symbols:\n"
                      + repeated.prefix(20).map { "  «\($0.key)»: \($0.value.sorted().joined(separator: ", "))" }
                        .joined(separator: "\n"))
            }

    /// `Module.wordFew`, `Module.wordMany`: the same module and the same stem before the plural suffix.
    static func areFormsOfOneWord(_ names: [String]) -> Bool {
        let stems = Set(names.map { $0.replacing(/(One|Few|Many|Other)$/, with: "") })
        return stems.count == 1 && Set(names).count == names.count
    }

    func testTheFormsOfOneWordAreNotTwoMeanings() {
        XCTAssertTrue(Self.areFormsOfOneWord(["Layout.wordsPutRightFew", "Layout.wordsPutRightMany"]))
        XCTAssertFalse(Self.areFormsOfOneWord(["Layout.wordsPutRightFew", "Disk.wordsPutRightMany"]))
        XCTAssertFalse(Self.areFormsOfOneWord(["Layout.tabs", "Layout.windows"]))
    }

    /// **No source holds an inline table.** The catalogs are where a module's words live, and a table at a
    /// call site is outside everything this file guards — a language could be missing from one and
    /// nothing would say so; one changelog entry shipped English to six languages for exactly that.
    /// Read from the source with comments and literals blanked, so neither a doc comment that names the
    /// old spelling nor a string that holds it counts. `testTheReadingFindsAnInlineTableInEitherSpelling` tests the reading.
    static func inlineTableSpellings(in code: String) -> [Int] {
        var lines: [Int] = []
        let patterns = [#"\[\s*\.(?:ru|es|fr|de|ja|zh|pt|en)\s*:"#, #"\[\s*AppLanguage\s*:\s*String\s*\]"#]
        for pattern in patterns {
            for match in code.ranges(of: try! Regex(pattern)) {
                lines.append(code[..<match.lowerBound].filter { $0 == "\n" }.count + 1)
            }
        }
        return lines.sorted()
    }

    func testTheReadingFindsAnInlineTableInEitherSpelling() {
        XCTAssertEqual(Self.inlineTableSpellings(in: "let a = 1\nlet t = [.ru: x]\n"), [2])
        XCTAssertEqual(Self.inlineTableSpellings(in: "let t: [AppLanguage: String] = [:]"), [1])
        XCTAssertEqual(Self.inlineTableSpellings(in: "let t = [\n  .ru :\n x]"), [1])
        XCTAssertEqual(Self.inlineTableSpellings(in: "let a = [1, 2]; let b = foo.ru"), [])
        let blanked = SwiftSource.code("// a table [.ru: x] in prose\nlet a = \"[.ru: y]\"\n")
        XCTAssertEqual(Self.inlineTableSpellings(in: blanked), [], "prose and literals are not tables")
    }

    func testNoStringKeepsAnInlineTable() throws {
        let sources = try SwiftSource.code(under: "Sources")
        XCTAssertGreaterThan(sources.count, 100, "only \(sources.count) source files were read, so a pass means nothing")
        let found = sources.flatMap { read in Self.inlineTableSpellings(in: read.text).map { "  \(read.path):\($0)" } }
        XCTAssertTrue(found.isEmpty,
                      "\(found.count) inline table(s) remain in Sources. A word belongs in its catalog, "
                      + "an interpolated one as a `%@` key:\n" + found.sorted().prefix(60).joined(separator: "\n"))
    }

    /// Where a language ships a key back as its own value, on purpose.
    ///
    /// Every entry here is a decision somebody made and can be argued with;
    /// that is the point of writing them down. It replaced a length threshold —
    /// "fail if the key is 20 characters or more" — which did no work at all:
    /// most legitimate identities are a word or two, so a length rule fired on
    /// almost none of the entries below, while `Show all`,
    /// `Widget size` and `Close tab` could have shipped untranslated in all
    /// seven and passed. A threshold hides the decision; a list makes it.
    ///
    /// Per language, not per key, because `Notification` is French and German's
    /// own word for it is `Mitteilung`: an identity is legitimate in the
    /// languages that were checked, not everywhere the spelling could occur.
    private static let deliberateIdentities: [String: Set<AppLanguage>] = [
        "1 module": [.fr],
        // The host's counted words, now in its catalog and so read by this loop. French says «module»
        // and Spanish «error» the way English does (the six others differ), and a count in front of
        // them does not change the word.
        "%@ error": [.es],
        "%@ modules": [.fr],
        " · %@ module": [.fr],
        " · %@ modules": [.fr],
        "App": [.es, .fr, .de, .pt],
        "Apps": [.es, .fr, .de, .pt],
        "Archive": [.fr],
        "Audio": [.es, .fr, .de],
        "Auto": [.fr],
        "Autopilot": [.de],
        // The Keyboard module's app-row picker. Portuguese borrowed the word
        // whole, the way German borrowed «Filter»: macOS pt-BR says «Layout de
        // Teclado» throughout `KeyboardSettings.appex` — «Alterar Layout de
        // Teclado», «Layout de Teclado Instalado» — so the system's own
        // spelling is the English one. The other six all differ (Раскладка,
        // Belegung, Disposition, Distribución, 配列, 布局), which is what makes
        // this an identity rather than a row nobody filled in.
        "Layout": [.pt],
        // The severity badge over a `brew doctor` finding that is an `Error:`
        // rather than a `Warning:`. German spells it exactly as English does —
        // Duden lists «Problem» and the alternatives («Schwierigkeit»,
        // «Missstand») are longer words for something else — and the other six
        // all differ (Проблема, Problema, Problème, 問題, 问题), which is what
        // makes this an identity rather than a row nobody filled in.
        "Problem": [.de],
        "BETA": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Beta": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "BUILD": [.fr, .de, .pt],
        "Caches": [.fr, .de, .pt],
        // German borrowed the word whole; Duden lists «Filter» and nothing else
        // for the sense a list menu means.
        "Filter": [.de],
        "Capsule": [.fr],
        "cask": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Cookies": [.ru, .es, .fr, .de, .pt],
        // The two picture formats in the Screenshots format picker. macOS never
        // transliterates a format name: CoreTypes.bundle says «PNG-Bild»,
        // «Image PNG», «PNG画像» — the abbreviation stays in the script of
        // English in every language here.
        "PNG": [.de, .es, .fr, .ja, .pt, .ru, .zh],
        "JPEG": [.de, .es, .fr, .ja, .pt, .ru, .zh],
        // A markup shape's name, as Preview spells it: Localizable.loctable
        // `Oval` / `PVOvalAnnotationType` is «Oval» in de and pt_BR, and
        // `Rectangle` / `PVRectangleAnnotationType` is «Rectangle» in fr.
        "Oval": [.de, .pt],
        "Rectangle": [.fr],
        // The folder as French Finder and screencaptureui show it:
        // SystemFolderLocalizations fr says «Documents».
        "Documents": [.fr],
        // macOS's own screenshot panel button: screencaptureui.app `Options`
        // is «Options» in French.
        "Options": [.fr],
        // The four modifier-key names are macOS's own words, read from
        // AppKit's FunctionKeyNames.loctable rather than translated: ru and zh
        // keep all four in English there; ja keeps three («shift» differs by
        // its case); es keeps «Control», fr keeps «Option», pt keeps «Shift».
        "Command": [.ru, .ja, .zh],
        "Control": [.ru, .es, .ja, .zh],
        "Option": [.ru, .fr, .ja, .zh],
        "Shift": [.ru, .pt, .zh],
        // The two `brew config` group headings French spells exactly as
        // English does. Larousse gives «configuration» and «machine» for both
        // senses — the settings of an installation, and the computer itself —
        // and neither has a shorter French word to prefer. The other six all
        // differ (Конфигурация/Машина, Configuración/Equipo,
        // Konfiguration/Rechner, 構成/マシン, 配置/本机, Configuração/Máquina),
        // which is what makes these identities rather than rows nobody filled
        // in.
        "Configuration": [.fr],
        "Machine": [.fr],
        "Cyan": [.fr, .de],
        "DEV": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Dev": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Document": [.fr],
        // The log row's spoken level. Spanish spells it the way English does —
        // «Error» is the RAE's word and the one this file's own «Errors» =
        // «Errores» is the plural of.
        "Error": [.es],
        // The Screenshots editor's name. German, Spanish and Portuguese each
        // have the word as their own — «Der Editor», «El editor», «O editor»
        // in the changelogs — so the tab says it the way English does.
        "Editor": [.de, .es, .pt],
        // The emoji button, as macOS displays it: AppKit InputManager.loctable
        // says «Emoji & Symbole» in de, «Emojis y símbolos» in es, «Emoji et
        // symboles» in fr, «Emoji e Símbolos» in pt_BR. German, French and
        // Portuguese keep that word; Spanish does not — macOS says «Emojis», and
        // Helm's «Emoji» is its own (`ScStr.tool` in ScreenshotsStrings says so).
        "Emoji": [.de, .es, .fr, .pt],
        "Extension": [.fr],
        "General": [.es],
        "h": [.es, .fr, .pt],
        "Hardware": [.es, .de, .pt],
        "Homebrew": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        "Image": [.fr],
        // The package view's licence tile. The English text is the British
        // spelling, which is the French word — «licence», capitalised as a
        // label. The other six each have their own: «Лицензия», «Licencia»,
        // «Lizenz», «ライセンス», «许可证», «Licença».
        "Licence": [.fr],
        "m": [.es, .fr, .pt],
        "Manual": [.es, .pt],
        "MB": [.es, .de, .ja, .zh, .pt],
        // The tunnel strip's unit, and the identity is inherited rather than
        // new: all eight already shipped it inside «Speed, Mbit/s», which
        // splitting that key into a plain label and a unit turned from a
        // sentence into six identities and put in front of this list. macOS
        // spells the same quantity differently and is not the answer —
        // `MeasurementFormatter` over `UnitInformationStorage.megabits` gives
        // «Mb» in seven of the eight and «Мбит» in Russian, with no per-second
        // in any of them.
        "Mbit/s": [.es, .fr, .de, .ja, .zh, .pt],
        "min": [.es, .fr, .pt],
        "Mint": [.de],
        "MODULES": [.fr],
        "Modules": [.fr],
        "Name": [.de],
        "Nature": [.fr],
        "Notification": [.fr],
        "OK": [.fr, .pt],
        "Orange": [.fr, .de],
        "Panel": [.es, .de],
        // es reads «Módulos» now, System Information's own name for the section.
        "Plug-ins": [.de, .pt],
        "Ring": [.de],
        "Rostislav Strelnikov": [.es, .fr, .de, .ja, .zh, .pt],
        // German uses the loanword for the system search and the de changelog
        // quotes «Spotlight» as the control's name.
        "Spotlight": [.de],
        "Start": [.de],
        "Style": [.fr],
        "Tab": [.de],
        "Tag": [.fr, .de],
        // «Text» is the German word, spelled as English spells it.
        "Text": [.de],
        "Timer": [.de, .pt],
        // The same word as the plain «Timer» above, with its countdown: macOS
        // de and pt_BR both display «Timer» for it.
        "Timer: %@": [.de, .pt],
        "Updates": [.de],
        "VERSION": [.fr, .de],
        // The same two languages as the dial above it, for the same reason
        // and now at the package view's version tile: French and German
        // both write the word the way English does. The four non-Latin
        // scripts and the two Iberian languages do not — «Версия»,
        // «Versión», «バージョン», «版本», «Versão».
        "Version": [.fr, .de],
        "Video": [.de],
        "🌐︎": [.ru, .es, .fr, .de, .ja, .zh, .pt],
        // Apple's own name for its material. macOS keeps it Latin in all eight
        // languages (`Appearance.appex`, key `Liquid Glass`); German alone
        // spells it with a no-break space between the words, so German is a
        // different string and not an identity.
        "Liquid Glass": [.ru, .es, .fr, .ja, .zh, .pt],
        // The highlighter tool's English is «Marker»; German says «Marker» too, as PencilKit's
        // `Localizable.loctable` does (key `Marker`).
        "Marker": [.de],
    ]

    /// Whether a value says anything in a language: a letter or a digit once its placeholders go. `%@ · %@`
    /// is two arguments and a dot, the same string in every language, and no translation exists to be missing.
    static func holdsAWord(_ value: String) -> Bool {
        value.replacing(/%(?:\d+\$)?@/, with: "").contains { $0.isLetter || $0.isNumber }
    }

    func testAValueWithNoWordInItIsNotAnUntranslatedOne() {
        XCTAssertFalse(Self.holdsAWord("%@ · %@"))
        XCTAssertFalse(Self.holdsAWord("%1$@ — %2$@"))
        XCTAssertTrue(Self.holdsAWord("%@ error"))
        XCTAssertTrue(Self.holdsAWord("Show all"))
        XCTAssertTrue(Self.holdsAWord("%1$@ of %2$@"))
    }

    /// Every catalog's value in `language` that is its own English, and is not a decision: read from
    /// the symbol's own entry, so two symbols with one English are both judged.
    func testNoTranslationIsJustTheEnglishAgainUnlessItIsMeantTo() throws {
        var untranslated: [String] = []
        var judged = 0
        for language in AppLanguage.allCases where language != .en {
            for entry in try ModuleCatalogs.entries(for: language) {
                judged += 1
                guard entry.value == entry.english, Self.holdsAWord(entry.english) else { continue }
                guard Self.deliberateIdentities[entry.english]?.contains(language) != true else { continue }
                untranslated.append("  \(language.rawValue): \(entry.name) \"\(entry.english.prefix(60))\"")
            }
        }
        XCTAssertGreaterThan(judged, 7000, "only \(judged) value(s) were judged")
        XCTAssertTrue(untranslated.isEmpty,
                      "\(untranslated.count) value(s) are shipped as their own English. If a "
                      + "language really does spell one of these the way English does, say so in "
                      + "deliberateIdentities — a decision belongs in writing:\n"
                      + untranslated.sorted().joined(separator: "\n"))
    }

    /// An allowlist rots the moment the string it excuses is translated, and a stale entry excuses
    /// whatever is written there next. Every entry has to still be doing work: some symbol holds the
    /// English and answers it back in that language.
    func testEveryAllowedIdentityIsStillOne() throws {
        var stale: [String] = []
        for language in AppLanguage.allCases where language != .en {
            let entries = try ModuleCatalogs.entries(for: language)
            for (english, languages) in Self.deliberateIdentities where languages.contains(language) {
                let holders = entries.filter { $0.english == english }
                if holders.isEmpty {
                    stale.append("\(language.rawValue): \"\(english)\" is in no catalog")
                } else if !holders.contains(where: { $0.value == english }) {
                    stale.append("\(language.rawValue): \"\(english)\" is translated as \"\(holders[0].value)\"")
                }
            }
        }
        XCTAssertTrue(stale.isEmpty,
                      "\(stale.count) allowlist entr(ies) no longer describe the catalogs:\n"
                      + stale.sorted().joined(separator: "\n"))
    }
}
