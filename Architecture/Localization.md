# Localization

## Catalogs and the words kept in Swift

A target that draws words keeps them in its own `Localizable.xcstrings`: all eight languages in one file,
and the key is an identifier, not the English. Four places keep words in Swift. Layout's `wordsCounted` and
Autopilot's `DayUnit.afterComparison` compose theirs in code, and so does `AppStr.tabTitle`
(`Sources/HelmAppStrings/AppStrings.swift`: the tab's label, a space and its number). `HelmRuntime` does too: `Sources/HelmRuntime/Plural.swift`
holds its counted nouns in eight languages in a `switch` in code, because `L` lives in `HelmUI`, which depends on
`HelmRuntime` (`Package.swift`), so `HelmRuntime` cannot import the reader of a catalog. SwiftPM generates an internal `LocalizedStringResource`
symbol from it, so a mistyped key is a build error and the call site reads
`L(.summary)` (`Sources/Modules/KeepAwake/UI/KeepAwakeStrings.swift`). `find Sources -name '*.xcstrings'` lists them: the kit's, the host's (`Sources/HelmAppStrings`,
where `Changelog.xcstrings` sits beside its `Localizable.xcstrings`) and each module's. `Tests/Support/EachLanguage.swift` states the rule a new
test follows for the language it asks in.

## The lookup and its memo

The helper is `L(_ resource:language:remembered:)` in `Sources/HelmUI/L10n.swift`, which asks the resource in
`AppLanguage.current`, since `String(localized:)` alone answers in the language macOS resolves for the
process, not the one the person picked in Helm, and the resource carries its own target's bundle. It
keeps a bounded memo of its answers, because `String(localized:)` with a locale costs by the size of
the table (release build: about 57 us at 11 keys, 1 ms at the changelog's keys, against 0.8 us for a held
dictionary) and a word in a view body is drawn per frame. The changelog reads its language's sub-bundle once, in
`Sources/HelmAppStrings/ChangelogData.swift`. The memo's reason is in the doc comment of
`L(_ resource:language:remembered:)`, its limits in that of `ResourceAnswers` (`Sources/HelmUI/L10n.swift`).
`remembered: false` skips the memo for a word that holds somebody's typed text (Layout's `pairRead` and
`fixedAnnouncement`), because the memo keeps the arguments and forgets only by count.

## Arguments and numbers

A key whose English holds `%@` generates a function that takes the arguments, `L(.timerOn(length))`.
Numbers go in as strings: `%lld` groups digits by locale (`1 499 308` with a no-break space) where
`\(n)` writes `1499308`, so a plural in a module is, but for the Swift sites above, a key per form picked by `Plural.form`
(`Sources/HelmRuntime/Plural.swift`), never a catalog variation; `Plural.russian` takes its three from the caller. A value that holds an argument
writes a literal percent sign as `%%`, one without writes it single: `%%` in a value with no argument prints two marks.

## Words two parts draw

Symbols are internal to their target, so a word that two modules or the kit draw lives in the kit's
catalog and is read through `HelmWord` (`Sources/HelmUI/HelmWord.swift`) or another type of the kit (`command grep -rlE '\bL\(\.' Sources/HelmUI`
lists the files), `String` only. A module does pass its own resource into the kit's public `L`, which is
why the resource carries its bundle. The same English
in a catalog and in the kit is a failure (`OneEntryPerKeyTests`), except a value holding a placeholder
(the kit's `rowPosition` and Screenshots' `toolsShown` are both `%1$@ of %2$@`, with different values in ja and zh). The catalog needs no
`resources:` entry: SwiftPM processes it and `Scripts/package-app.sh` copies every `*.bundle`
into `Contents/Resources`, where the target's `Bundle.module` finds it. A catalog sits in a library
target, never an executable: a test target over an executable compiles without
the catalogs, so `L(.x)` there fails `swift build --build-tests` (`Architecture/Targets.md`).

## The changelog's key and a missing language

The changelog's key is the English sentence, not an identifier: its entries have no natural name,
and a language the file lacks falls back to the sentence. For a word an
identifier key is the other way round: a missing *language* builds and the screen
shows the identifier, so `StringsCoverageTests` is the only thing that sees it.

## The guards

Each guard faces a direction the others are blind to; its header says which:

- `Tests/HelmUITests/StringsCoverageTests.swift` — a symbol missing a language or not `translated`, a lost placeholder, a `%` rule judged on each value alone, an inline table at a call site, an English value posing as a translation.
- `Tests/HelmUITests/NoOrphanTranslationsTests.swift` — a symbol nothing asks for, a word asked
  by its English spelling. After touching
  any `Localizable.xcstrings`, the catalog filter in `CLAUDE.local.md` runs them with the other two.
- `Tests/HelmUITests/OneEntryPerKeyTests.swift` — a key written twice in one catalog, which the build
  passes, and one English text under two symbols across the catalogs.
- `Tests/HelmUITests/PunctuationIsTerminologyTests.swift` — a mark or a space a language
  does not use, in every catalog, and an «ё» in every catalog but the changelog's.

`Tests/Support/ModuleCatalogs.swift` reads the catalogs as data for these guards (its header says what it throws on), and
`Tests/Modules/KeepAwake/UITests/TheModuleWordsReachEveryLanguageTests.swift` shows the words
come out of the built target in the language asked.

Two languages have no catalog of their own and fall back, by the owner's choice: Traditional Chinese
(`zh-Hant`) reads the Simplified one, and European Portuguese (`pt-PT`) the Brazilian. A
`zh-Hant` translation is a chain of its own.

## One English text means one thing

Where a second meaning needs the same word, the English is written differently, because several
languages draw distinctions the English loses. A sentence that names a control is built from the
control's own word, so a rename carries the sentence with it. Interpolation carries a name rather than a
verb, which eight grammars would not inflect; each variant is a full key with its own eight translations.

## Formatters and the app's language

Everything the language shapes goes through a helper keyed by the app's language — never
a `Foundation` formatter built with no locale, which answers in the system's language, and
never one held in a `static let`, which keeps the language the app started in:
`HelmBytes` (in `Sources/HelmRuntime`) for sizes and counts, `Quoted` for quotation
marks, `HelmDates` for ages and spans. A pop-up's width is measured by `HelmPickerWidth`,
because no number chosen in one language survives eight.

## Terminology from the system's own tables

Terminology is looked up rather than remembered: the units, the permission panes, the
module names, the quotation marks and a screen reader's vocabulary
(`Sources/HelmUI/DesignSystem/A11yStrings.swift`) come from the tables
macOS itself ships, read from the table that is *displayed* and not the one that is
searched, since a pane's search terms are never drawn. An English text
with no quotes is cheaper than a quoted one, since the seven translations then have nothing to copy.

## Russian values

A Russian value does not address the reader: no «вы», «ваш» or «вас», the sentence goes
impersonal, and an imperative stays. «е» is written for «ё», «все» for «всё» included (`PunctuationIsTerminologyTests`);
nothing holds the rule of address (ARCHITECTURE.md § What proves what).
`Changelog.xcstrings` is shipped text and stays as it shipped.

## The French pass

After keys are added the French values are swept in a pass of its own with an explicit
escape for the unbreakable space, never the literal character: a literal one arrives from a
shell heredoc as an ordinary space and the substitution silently does nothing, so the count is checked with `command grep -c` before and after.
