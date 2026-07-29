# Translations move to `.lproj`, and the 17 collisions that blocked it — 2026-07-30

Every user-visible string lived inline in Swift: `L("Back", [.ru: "Назад", …])`,
700 call sites. They move into real macOS `.lproj/Localizable.strings` files
with **the English string as the key**, which is Apple's own
development-language-as-key convention and the thing a translator can be handed.

## The design

**Files.** `Sources/HelmUI/Resources/<lang>.lproj/Localizable.strings`, eight
languages named by `AppLanguage`'s raw values — `en ru es fr de ja zh pt`, not
the `zh-Hans`/`pt-BR` spellings in `Info.plist`, because Helm resolves the
language itself and never lets the system's bundle machinery do it. SwiftPM
builds them into `Helm_HelmUI.bundle`; `Scripts/package-app.sh` already copies
every generated bundle into the app, so no script change was needed.

**Not `NSLocalizedString`.** `AppLanguage.current` reads
`Locale.preferredLanguages` once and caches it, invalidating on locale change.
`NSLocalizedString` would hand that decision to the system's own bundle
resolution and, worse, break the `language:` overload every localization test
uses to ask about a language other than this machine's. So the per-language
sub-bundle is loaded explicitly and cached — one bundle per language, not one
per row of a hovered list, which is the same reasoning `AppLanguage.current`
already carried one level up.

**The 36 that stay inline.** A Swift-interpolated string cannot be a `.strings`
key: interpolation runs before the lookup, so `L("Step \(step) of \(total)")`
would look for the key "Step 3 of 10". `L()` keeps its `table` parameter and an
inline table still wins where it has an entry. 663 of 700 sites migrated; the
rest are interpolated or not string literals at all.

**The guard changed shape.** A test that walked tables in the source is now a
test that reads the eight files as data. That is the better question: those
files are the artifact that ships, and a key that never made it out of the
migration is exactly the failure worth catching. `WelcomeStrings`' odd
English/Table constant pairs existed only so a test could walk languages, and
went with it.

## What the migration found, and why it is worth writing down

A collision guard — refuse to proceed if one English key carries two different
translations for the same language — fired on **17 keys, 64 conflicts**. Inline
tables had hidden this completely: two modules could translate the same English
word differently for years and nothing would notice, because the tables never
met. A shared key space made them meet.

The rulings below were made by reading every call site and checking ambiguous
cases against real macOS localizations on disk (`Console.app`'s `MainMenu.loctable`,
Finder's `MenuBar.strings`, AppKit's `OK` glossary, `LoginItems.appex`) rather
than translating afresh — ARCHITECTURE.md § Localization's rule that a thing
macOS already names is called what macOS calls it.

**Most of them were not translation mistakes.** Twelve of the seventeen were two
or three genuinely different concepts wearing the same English word, and the
translators had been *right* to diverge — the tell, again and again, was that
several languages independently drew the same distinction the English had lost.
The fix is to split the English, not to force one word onto two meanings.

### Pure fixes — one concept, inconsistent translation (5 keys, 9 corrections)

| Key | Canonical | Corrected at |
|---|---|---|
| `Leftovers` | ja «残存物», zh «残留» | `UninstallerStrings:35` |
| `No leftovers found.` | fr «Aucun reste trouvé.», ja «残存物は…», zh «未找到残留项。» | `LeftoversStrings:43`, `UninstallerStrings:39` |
| `Refresh list` | es «Recargar lista», pt «Recarregar lista» | `UninstallerStrings:84` |
| `Scan again` | es «Escanear de nuevo», fr «Réanalyser», pt «Escanear de novo» | `LeftoversStrings:28` |
| `System` | es «Del sistema», pt «Do sistema» | `LeftoversStrings:24` |

`Refresh list` is the instructive one: Homebrew's file already carried a comment
recording that «Recargar»/«Recarregar» is what macOS itself uses for reloading.
That was system precedent for the concept, not a local hack, and the Uninstaller
simply had not been told.

### Splits — different concepts, same English (12 keys → 25)

| Was | Becomes | Because |
|---|---|---|
| `Clear` | `Clear` (log, shortcut, history) + `Empty` (basket) | Erasing a record is Console's "Clear"; emptying a container of pending items is Finder's "Empty Trash". |
| `Done` | `Done` + `OK` (KeepAwake's numeric field) | A confirm button glued to a one-line text field is "OK" by macOS convention — fr and pt had already independently written "OK" there while the English said "Done". |
| `Name` | `Name` (the rule's title) + `File name` (a condition's attribute) | Russian separates «название» of an entity from «имя» of a file; the other six reuse one word. |
| `Off` | `Off` (a key selector) + `Never` (a timing value) + `Disabled` (a login item's state) | es/fr/pt differed only in gender ending — the tell that the two sites describe nouns of different gender. Three concepts, not two. |
| `Other` | `Other` (a file's kind) + `Miscellaneous` (a module category) | Singular kind vs plural catch-all: es/fr/pt already had Otro/Otros, Autre/Autres. |
| `Power` | `Power` (module category) + `On power` (AC connected) | The KeepAwake site meant "connected to AC" and its own siblings already said so. |
| `Running` | `Active` (a feature's state) + `Running` (a process executing) | de/es/fr/ja all independently drew the feature-on vs process-executing line. |
| `Scanning…` | `Scanning…` + `Searching…` (merged into Homebrew's existing key) | Its sibling is literally "Scan for leftovers"; es/ja/ru had already reached for search-family words. |
| `Search` | `Search` (a tab, noun) + `Search now` (a button, imperative) | Russian distinguishes «Поиск» from «Искать»; six languages do not. |
| `Show` | `Show` (a filter setting) + `Show in Finder` (merged into the existing key) | de Anzeigen/Zeigen and ru Показывать/Показать are imperfective vs momentary. The bare "Show" was a shortening, not a choice. |
| `Stop` | `Stop scan` + `Stop` (KeepAwake's Start/Stop pair) | «Старт»/«Стоп» is the stopwatch pairing; de Stopp (noun) vs Stoppen (verb). |
| `When` | `When` (conditions) + `Timing` (at what point) | de Wenn/Wann, es Cuando/Cuándo, ja 条件/タイミング — the cleanest split found. |

### Flagged, not asserted

The Japanese and Chinese wording on the new `Disabled` key keeps what the
developer had, because no system precedent was found strong enough to override
it. A native reader should look at that badge.

## The rule this leaves behind

**One English key means one thing.** The collision guard stays in the migration
script's spirit as the `StringsCoverageTests` suite: if a future string reuses an
English word for a second meaning, the two translations will disagree and the
tests will say so. Before this, nothing could.
