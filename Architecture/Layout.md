# Layout

`Sources/Modules/Layout/` reads every keystroke and types into other applications,
which is a larger claim on the machine than anything else Helm does. Four things
bound it:

- The tap is listen-only (`CGKeyTap.start`'s doc comment in `SystemPorts.swift`), and Helm's own events carry `helmEventMarker` and are dropped on the way in. Replacement is synthesised Unicode, never the clipboard, and translation goes through `UCKeyTranslate` against the layouts actually installed.
- The decision to convert is `LayoutVerdict.swift`, a list of reasons to decline with one way through; secure input, password fields, terminals and password managers are refused before the dictionary is consulted, and the gesture and the hotkey are judged by `decideForced` against the same exceptions.
- What the module keeps from typing is a count (`ConversionLedger.swift`), and `command grep -rni 'vocabulary\|learned:\|salted' Sources/Modules/Layout/` prints nothing. The one path from typed text to a file is the page's button for excluding a word, which writes into `Exceptions.swift`'s plist in cleartext, and it is closed for a forced conversion.
- The selection actions are the one exception to the no-clipboard rule: they have two routes, the accessibility API where the app answers and ⌘C/⌘V where it does not, and `PasteboardSafety.swift` gates both. The engine holds no strings: it emits `LayoutAnnouncement`s over a port and the UI side speaks them, gated on VoiceOver being on. The emoji item in the menu-bar indicator is drawn only when Accessibility is granted (`EmojiPalette.swift`).

Which layout a word is converted *into* is `OtherSource.swift`, not "the first that is not the current one".
