# Localization

A target that draws words keeps them in its own `Localizable.xcstrings`: all eight languages in one file,
and the key is an identifier, not the English. Three places keep words in Swift. Layout's `wordsCounted` and
Autopilot's `DayUnit.afterComparison` compose theirs in code. `HelmRuntime` does too: `Sources/HelmRuntime/Plural.swift`
holds its counted nouns in eight languages in a `switch` in code, because `L` lives in `HelmUI`, which depends on
`HelmRuntime` (`Package.swift`), so `HelmRuntime` cannot import the reader of a catalog. SwiftPM generates an internal `LocalizedStringResource`
symbol from it, so a mistyped key is a build error (measured: a key deleted from a copy of
`Sources/Modules/Disk/UI/Localizable.xcstrings` exits 1 on every run) and the call site reads
`L(.summary)` (`Sources/Modules/KeepAwake/UI/KeepAwakeStrings.swift`). `find Sources -name '*.xcstrings'` lists them: the kit's, the host's (`Sources/HelmAppStrings`,
where the changelog's `Changelog.xcstrings` sits beside its `Localizable.xcstrings`) and each module's. `Tests/Support/EachLanguage.swift` states the rule a new
test follows for the language it asks in.

The helper is `L(_ resource:language:)` in `Sources/HelmUI/L10n.swift`, which asks the resource in
`AppLanguage.current`, since `String(localized:)` alone answers in the language macOS resolves for the
process, not the one the person picked in Helm, and the resource carries its own target's bundle. It
keeps a bounded memo of its answers, because `String(localized:)` with a locale costs by the size of
the table, measured in a release build: about 57 us at 11 keys, 1 ms at the changelog's keys
(323 KB), against 0.8 us for a held dictionary. A word in a view body is drawn per frame, and a
changelog read through it was 436 ms. The changelog reads its language's sub-bundle once, in
`Sources/HelmAppStrings/ChangelogData.swift`. The memo's reason is in the doc comment of
`L(_ resource:language:)`, its limits in that of `ResourceAnswers` (`Sources/HelmUI/L10n.swift`).

A key whose English holds `%@` generates a function that takes the arguments, `L(.timerOn(length))`.
Numbers go in as strings: `%lld` groups digits by locale (`1 499 308` with a no-break space) where
`\(n)` writes `1499308`, a change of bytes, so a plural in a module is, but for those two sites, a key per form picked by `Plural.form`
(`Sources/HelmRuntime/Plural.swift`), never a catalog variation; the counted nouns `Plural.items`, `apps`,
`files` and `days` in that file keep their words in Swift (above), and `Plural.russian` takes its three from the caller. A value that holds an argument
writes a literal percent sign as `%%`, one without writes it single: measured on a copy, `%%` in a
value with no argument prints two marks.

Symbols are internal to their target, so a word that two modules or the kit draw lives in the kit's
catalog and is read through `HelmWord` (`Sources/HelmUI/HelmWord.swift`), `String` only: a
property of the kit answers with the word, not with a resource. A module does pass its own resource into
the kit's public `L`, which is how one function reads every catalog and why the resource carries its bundle. The same English
in a catalog and in the kit is a failure (`StringsCoverageTests`), except a value holding a placeholder
(the kit's `rowPosition` and Screenshots' `toolsShown` are both `%1$@ of %2$@`, the same English with different values in ja and zh). The catalog needs no
`resources:` entry: SwiftPM processes it on its own and `Scripts/package-app.sh` copies every `*.bundle`
into `Contents/Resources`, where the target's `Bundle.module` finds it. A catalog sits in a library
target, never an executable: a test target over an executable compiles its testable variant without
the catalogs, so `L(.x)` there fails `swift build --build-tests` (`Architecture/Targets.md`).

The changelog's key is the English sentence, not an identifier: its entries (count them with
`python3 -c "import json;print(len(json.load(open('Sources/HelmAppStrings/Changelog.xcstrings'))['strings']))"`) have no natural name,
the symbol stays readable, and a language the file lacks falls back to the sentence. For a word an
identifier key is the other way round: a missing *language* builds (measured, exit 0) and the screen
shows the identifier where English would have, so `StringsCoverageTests` is the only thing that
sees it.

Each guard faces a direction the others are blind to; each file's header, or the doc comment of the test method, says how:

- `Tests/HelmUITests/StringsCoverageTests.swift` — a catalog symbol missing a language or not marked
  `translated`, a placeholder a translation lost, a `%` rule judged on each value alone (a bare `%` beside a placeholder, `%%` beside none; a lost `%%` is not compared with the English), a word in both the kit and a catalog,
  an inline table at a call site.
- `Tests/HelmUITests/NoOrphanTranslationsTests.swift` — a catalog symbol nothing asks for, a word asked
  by its English spelling.
- `Tests/HelmUITests/OneEntryPerKeyTests.swift` — a key written twice in one catalog, which the build
  passes (measured, exit 0).
- `Tests/HelmUITests/PunctuationIsTerminologyTests.swift` — a mark or a space a language
  does not use, in every catalog, and an «ё» in every catalog but the changelog's.

`Tests/Support/ModuleCatalogs.swift` reads the catalogs as data for these guards, and
`Tests/Modules/KeepAwake/UITests/TheModuleWordsReachEveryLanguageTests.swift` shows the words
come out of the built target in the language asked.

One English text means one thing. Where a second meaning needs the same word, the English
is written differently, because several languages had independently drawn distinctions
the English had lost and the translators were right to diverge. A sentence that names a
control is built from the control's own word rather than spelling it a second time, so a
rename carries the sentence with it. What interpolation carries is a name rather than a
verb: a verb inflected against eight grammars would be right in roughly one of them, so
each variant is a full key with its own eight translations.

Everything the language shapes goes through a helper keyed by the app's language — never
a `Foundation` formatter built with no locale, which answers in the system's language, and
never one held in a `static let`, which keeps the language the app started in:
`HelmBytes` (in `Sources/HelmRuntime`) for sizes and counts, `Quoted` for quotation
marks, `HelmDates` for ages and spans. A pop-up's width is measured by `HelmPickerWidth`
rather than written down, because no number chosen in one language survives eight.

Terminology is looked up rather than remembered: the units, the permission panes, the
module names, the quotation marks and a screen reader's vocabulary
(`Sources/HelmUI/DesignSystem/A11yStrings.swift`) come from the tables
macOS itself ships, read from the table that is *displayed* and not the one that is
searched — three units and four pane names were invented before anyone opened those files,
and a pane's search terms are the phrases that find it and are never drawn. An English text
with no quotes is cheaper still than a quoted one, since the seven translations then have
nothing to copy.

A Russian value does not address the reader: no «вы», «ваш» or «вас», the sentence goes
impersonal, and an imperative stays. «е» is written for «ё», «все» for «всё» included (`PunctuationIsTerminologyTests`);
nothing holds the rule of address, which is no class kept by ARCHITECTURE.md § What proves what.
`Changelog.xcstrings` is shipped text and stays as it shipped.

After keys are added the French values are swept in a pass of its own with an explicit
escape for the unbreakable space, never the literal character: a literal one does not
survive a shell heredoc into Python, it arrives as an ordinary space and the substitution
silently does nothing, so the count is checked with `command grep -c` before and after.
