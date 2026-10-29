# Layout

`Sources/Modules/Layout/` reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
bound it:

- The tap is listen-only (`CGKeyTap.start`'s doc comment in `SystemPorts.swift`), and Helm's own events carry `helmEventMarker` and are dropped on the way in — the one guard against reading its own output back, since every conversion runs on main and the tap hears the echo after it (`HelmsOwnKeystrokesAreNotReadAsTypingTests`). Replacement is synthesised Unicode, never the clipboard, and translation goes through `UCKeyTranslate` against the layouts actually installed.
- The decision to convert is `LayoutVerdict.swift`, a list of reasons to decline with one way through; secure input, password fields, terminals and password managers are refused before the dictionary is consulted, and the gesture and the hotkey are judged by `decideForced` against the same exceptions.
- What the module keeps from typing is a count (`ConversionLedger.swift`), and `command grep -rni 'vocabulary\|learned:\|salted' Sources/Modules/Layout/` prints nothing. The one path from typed text to a file is the page's button for excluding a word, which writes into `Exceptions.swift`'s plist in cleartext, and it is closed for a forced conversion.
- The selection actions are the one exception to the no-clipboard rule: they have two routes, the accessibility API where the app answers and ⌘C/⌘V where it does not, and `PasteboardSafety.swift` gates both (`TheClipboardIsLeftAloneWhenItCannotBeGivenBackTests`, through `AXSelection`'s pasteboard, focus and key ports). The engine holds no strings: it emits `LayoutAnnouncement`s over a port and the UI side speaks them, gated on VoiceOver being on. The emoji item in the menu-bar indicator is drawn only when Accessibility is granted (`EmojiPalette.swift`).

Which layout a word is converted *into* is `OtherSource.swift`, not "the first that is not the current one".

## How Layout's model reaches its engine

`LayoutViewModel` is built with the engine by the descriptor's `makeModule` and held by
the host. It calls the engine through `LayoutWork` (`LayoutViewModel.swift`), an internal
port of three members: `fix()` for the gesture and the hotkey, `settingsChanged()` after
the page, the lists window or a panel verb wrote the store, and `stream()`. There is no
command enum or handler, so a name that does not exist is a build error. After the
descriptor's `stop(_:)` the model reaches none of the three
(`AStoppedLayoutModelReachesNoWorkTests`).

The one thing the engine says to its model is `LayoutState`, level-triggered, through
`LayoutEngine.stream()` in the shape of Keep Awake's (Architecture/KeepAwake.md § How
the model reaches the engine): the latest state first, the subscriber registered in the
one hold of the transport's lock that replays it, one task in the model that `stop(_:)`
cancels before the engine's `deactivate()` (`TheLayoutStreamReplaysTheLatestStateTests`,
`ASwitchedOffModuleLetsItsSubscriberGoTests`). The model lives as long as the module is
switched on, so the panel tile keeps counting with Settings closed.

Words: `Sources/Modules/Layout/UI/Localizable.xcstrings`; interpolated ones in inline tables in `LayoutStrings.swift`; shared words through `L()` from the kit.

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
