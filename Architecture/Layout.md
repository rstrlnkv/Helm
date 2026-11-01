# Layout

`Sources/Modules/Layout/` reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
bound it:

- The tap is listen-only (`CGKeyTap.start`'s doc comment in `SystemPorts.swift`), and Helm's own events carry `helmEventMarker` and are dropped on the way in — the one guard against reading its own output back, since every conversion runs on main and the tap hears the echo after it (`HelmsOwnKeystrokesAreNotReadAsTypingTests`). Replacement is synthesised Unicode, never the clipboard, and translation goes through `UCKeyTranslate` against the layouts actually installed.
- The decision to convert is `LayoutVerdict.swift`, a list of reasons to decline with one way through; secure input, password fields, terminals and password managers are refused before the dictionary is consulted, and the gesture and the hotkey are judged by `decideForced` against the same exceptions.
- What the module keeps from typing is a count (`ConversionLedger.swift`), and `command grep -rni 'vocabulary\|learned:\|salted' Sources/Modules/Layout/` prints nothing. The one path from typed text to a file is the button for excluding a word, on the page and on the panel tile (`LayoutDescriptor.never`), which writes into `Exceptions.swift`'s plist in cleartext, and it is hidden for a forced conversion.
- The selection actions are the one exception to the no-clipboard rule: `fix()` reads the selection through the accessibility API alone (`selectedTextWithoutClipboard`; an app whose tree says nothing counts as having no selection) and writes through it, pasting with ⌘V only where the app refuses the write, and `PasteboardSafety.swift` gates that paste (`TheClipboardIsLeftAloneWhenItCannotBeGivenBackTests`, through `AXSelection`'s pasteboard, focus and key ports). `AXSelection.selectedText()` has a ⌘C route behind the same gate that no shipping caller reaches: `fix()` passes `convertSelection` the text it has already read. The engine holds no strings: it emits `LayoutAnnouncement`s over a port and the UI side speaks them, gated on VoiceOver being on. The emoji item in the menu-bar indicator is drawn only when Accessibility is granted (`EmojiPalette.swift`).

Which layout a word is converted *into* is `OtherSource.swift`, not "the first that is not the current one".

## How Layout's model reaches its engine

`LayoutViewModel` is built with the engine by the descriptor's `makeModule` and held by
the host. It calls the engine through `LayoutWork` (`LayoutViewModel.swift`), an internal
port of three members: `fix()` for the gesture and the hotkey, `settingsChanged()` after
the page, the lists window or a panel verb wrote the store, and `stream()`. A name
that does not exist is a build error. After the
descriptor's `stop(_:)` the model reaches none of the three
(`AStoppedLayoutModelReachesNoWorkTests`).

The one thing the engine says to its model is `LayoutState`, level-triggered, through
`LayoutEngine.stream()` in the shape of Keep Awake's (Architecture/KeepAwake.md § How
the model reaches the engine): the latest state first, the subscriber registered in the
one hold of `EngineNews`'s lock that replays it (`EngineNews.stream`), one task in the model that `stop(_:)`
cancels before the engine's `deactivate()` (`TheLayoutStreamReplaysTheLatestStateTests`,
`ASwitchedOffModuleLetsItsSubscriberGoTests`). The model lives as long as the module is
switched on, so the panel tile keeps counting with Settings closed.

Words: `Sources/Modules/Layout/UI/Localizable.xcstrings`; shared words through `HelmWord` from the kit.

Announcements are not on the stream. `LayoutAnnouncement` is an edge said once, at the
moment it happens, over `AnnouncePort`; a replaying stream would say the last one again
to every new subscriber.

`settingsChanged()` re-reads the store on the engine's own serial queue, not on main:
`reloadSettings` ends in `emitState`, which asks the accessibility server whether the focused
field is a password field, and the tap callback runs on main. The queue is serial so that two quick
writes are read in the order they were made.

The engine registers nothing process-wide itself. Helm coming to the front (the person
may have just granted Accessibility or edited their layouts) and another application
coming to the front (the layout bound to it) both go through `AppActivationPort`;
`deactivate()` is one `stopObserving()` call, and a second `startObserving` replaces the
first (`TheEngineLetsGoOfItsObserversTests`, `TheActivationPortKeepsOneWatchTests`).

## The states of the Layout page

The page id is the module id, `layout`, and a state is shot with its file `layout-<state>-<light|dark>[-<ru|de>].png` (the language is always passed: without it Helm Dev speaks the Mac's language):

    bash Scripts/shoot.sh layout \
      [--press "<name>" [--nth <n>]]... \
      [--arg module.layout.<key> <value>]... \
      --arg module.app.appearance <light|dark> \
      --arg module.app.interfaceLanguage <en|ru|de> \
      --name <state>-<light|dark>[-<ru|de>] --out <dir>

Nothing is typed and no grant is changed to reach a state; the tour is left with "Got it" unpressed, because it writes `introSeen`. The page opens only with `module.layout.enabled` on: where Helm Dev has Layout off the launch is refused (`launch page refused: layout is switched off`, no window), so each shot below also passes `--arg module.layout.enabled '<true/>'`.

| state | the page shows | reached by |
|---|---|---|
| `hero-nothing-yet` | the sentence figure, its caption, five capsule buttons, "Today" chosen | the page as it opens, with `introSeen` set and `heroPeriod` unset in the dev domain, in Helm Dev with Accessibility, on a day the ledger holds no word put right (`figures.words > 0` is false for the chosen period) |
| `hero-period-<p>` | another period chosen: `hero-counting` when the ledger has words in it, the sentence otherwise | `--arg module.layout.heroPeriod week` (`month`, `year`, `allTime`) |
| `hero-counting` | a number figure over "words put right · <period> · ≈ <time> not spent typing again" | a period the dev ledger has words in: `--arg module.layout.heroPeriod <p>`; nothing is typed |
| `hero-paused` | the caption "Paused — a password field is in front, and Helm never reads one." | needs secure input in front; not shot |
| `denied` | "Not watching", the reason and Grant…; the two notes; the indicator section only | Helm Dev without Accessibility |
| `tour-1`, `tour-2`, `tour-3` | the tour card's steps | `--press "<Show>"` (the button on the "How it works" row), then `--press "<Next>"` once and twice; or `--arg module.layout.introSeen '<false/>'` |
| `indicator-<style>` | the indicator section open, the style picker and the preview (none for `sourceName`) | `--arg module.layout.indicator '<true/>' --arg module.layout.badgeStyle <plain\|filled\|outlined\|flagDrawn\|sourceName>` |
| `last-change` | the "Last change" row, the pair, the note, Never this word | needs typing; not shot |
| `no-dictionary` | the warning line under the behaviour | only on a Mac with a layout macOS has no dictionary for; not shot |
| `lists` | the lists window: words (empty: the "no words" line), apps (the built-in refusals this Mac has, the add button), Done | `--press "<the Words row's name>"`, read from `HelmReadout ax` first; the lists window (520 × 452 on screen) may read `onscreen no`, and then `shoot.sh` shoots the settings window: take the lists window's id from `HelmReadout window <pid>` and capture it with `screencapture -x -o -l <id>` |
| `worst` | de at the narrowest pane, 772 pt: the all-time number, its caption on one line, five capsules on one row, the card column as wide as at 892 pt, the correct-while-typing row's detail on two lines, the capitals row's on one; below the fold seen at 892 pt only: the hotkey row keeps its three controls. ru and fr at 772 pt, a number the dev ledger does not hold, a long language in `lists`: not rendered, one still was kept, and the ledger's words are what they are | `--arg module.app.interfaceLanguage de --arg module.app.sidebarWidth '<real>320</real>' --arg module.layout.heroPeriod allTime`, and `--arg module.layout.enabled '<true/>'` where Helm Dev has Layout off; the minimum window is the stored frame's |

The menu-bar indicator has no page. Its states are `off` (no status item), one per badge style, its menu with and without the emoji item (Accessibility granted or not), and the badge corrected on menu open, with its once-per-run log line. Its change is an image swap in AppKit with no animation, so there is no motion to record; the menu cannot be opened by `HelmReadout`, so it is not shot.

The panel tile has three sizes (compact, wide, tall) and three more states: not watching (`HelmWidgetUnmeasured`: the module is on and its tap is not live), suspended (no status dot), and a last change (a block filled with `onPanelFill`). A module switched off is the host's `DisabledModuleWidget` in the tile's place.

No guard: the sparkline's accent opacities have no Increase Contrast variant, because a value nobody can photograph without changing a Mac setting would be a guess; the hero's swap between the period row and the grant button (`helmAccordion`) is reachable only by switching Layout or the grant, so it is not recorded.
