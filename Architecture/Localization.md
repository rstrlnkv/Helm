# Localization

The English text is the key and stays at the call site (`L()` in
`Sources/HelmUI/L10n.swift`); the translations live in
`Sources/HelmUI/Resources/<language>.lproj/Localizable.strings`.
`ls -d Sources/HelmUI/Resources/*.lproj` lists the languages and
`command grep -c '^"' Sources/HelmUI/Resources/*.lproj/Localizable.strings` counts the
keys per file. An inline table survives only where a Swift-interpolated string is the key;
`Tests/Support/InlineTables.swift` is the reader that finds those sites. `Tests/Support/EachLanguage.swift` states the rule a new test
follows for the language it asks in.

A module that has moved its words keeps them in `Sources/Modules/<Name>/UI/Localizable.xcstrings`
(`ls Sources/Modules/*/UI/Localizable.xcstrings` lists them): all eight languages in one file, and
the key is an identifier, not the English — SwiftPM generates an internal `LocalizedStringResource`
symbol from it, so a mistyped key is a build error and the call site reads `L(.summary)`
(`Sources/Modules/KeepAwake/UI/KeepAwakeStrings.swift`; the helper is `L(_:language:)` in
`Sources/HelmUI/L10n.swift`, which asks the resource in `AppLanguage.current`, since
`String(localized:)` alone answers in the language macOS resolves for the
process, not the one the person picked in Helm, and the resource carries its own target's bundle). A key whose English holds `%@` generates a function that
takes the arguments, `L(.timerOn(length))`. Symbols are
internal to their target, so a word that two modules or the kit draw stays in the kit's `.lproj` and
is read through `L()`; the same English in a catalog and in the kit is a failure
(`StringsCoverageTests`). The catalog needs no `resources:` entry: SwiftPM processes it on its own and
`Scripts/package-app.sh` copies every `*.bundle` into `Contents/Resources`, where the target's
`Bundle.module` finds it. An interpolated string keeps its inline table at the call site unless its key holds `%@`, as above.

Each guard faces a direction the others are blind to, and each file's header says how (the catalog halves in the doc comment of their own test method):

- `Tests/HelmUITests/StringsCoverageTests.swift` — a key missing from one of the eight files, a
  catalog symbol missing a language or not marked `translated`, a word in both the kit and a catalog.
- `Tests/HelmUITests/NoOrphanTranslationsTests.swift` — an `en.lproj` key nothing asks for, a catalog
  symbol its module never names.
- `Tests/HelmUITests/StringsLiveInLprojTests.swift` — a literal that reached no table.
- `Tests/HelmUITests/OneEntryPerKeyTests.swift` — a key written twice in one file.
- `Tests/HelmUITests/PunctuationIsTerminologyTests.swift` — a mark or a space a language
  does not use, in the kit's files and in every catalog.

`Tests/Support/ModuleCatalogs.swift` reads the catalogs as data for these guards, and
`Tests/Modules/KeepAwake/UITests/TheModuleWordsReachEveryLanguageTests.swift` shows the words
come out of the built target in the language asked.

One English key means one thing. Where a second meaning needs the same word, the English
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
and a pane's search terms are the phrases that find it and are never drawn. An English key
with no quotes is cheaper still than a quoted one, since the seven translations then have
nothing to copy.

After keys are added the French folder is swept in a pass of its own with an explicit
escape for the unbreakable space, never the literal character: a literal one does not
survive a shell heredoc into Python, it arrives as an ordinary space and the substitution
silently does nothing, so the count is checked with `command grep -c` before and after.
