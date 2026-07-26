# Layout Switcher — Design

**Status:** approved-pending-review
**Date:** 2026-07-26
**Module id:** `layout`

## Goal

A Helm module that notices text typed in the wrong keyboard layout and fixes it:
`ghbdtn` becomes `привет`, and the system input source follows. It works
automatically while you type, and it can be undone.

This is the first module that reads every keystroke and types into other
applications. Most of the decisions below are about the second half of that
sentence.

## What the field already knows

Studied from open-source implementations — methods only, no code taken:
[RuSwitcher](https://github.com/rashn/RuSwitcher) (much the most explicit about
its own limits), [keyswitcher](https://github.com/graninilya/keyswitcher),
[langSwitcher](https://github.com/reg2005/langSwitcher),
[punto-switcher](https://github.com/rshagiev/punto-switcher),
[LayoutSwitcher](https://github.com/3t0n/LayoutSwitcher).

1. **Observe with `CGEventTap` in listen-only mode.** Passive: the tap reports
   keys, it does not swallow them. Needs Accessibility.
2. **Replace with `CGEvent.keyboardSetUnicodeString`, not the clipboard.**
   Clipboard replacement fails in Electron and VS Code, and it destroys whatever
   the user had copied. Synthesised Unicode does neither.
3. **Translate with `UCKeyTranslate`**, against the layouts actually installed.
   A hard-coded ЙЦУКЕН↔QWERTY table supports exactly two layouts and silently
   mangles a third.
4. **Mark your own events** with `CGEventSource.userData` and filter them on the
   way in, or the tap sees its own typing and feeds on itself.
5. **Their documented holes, which are ours too:** apps that draw their own text
   (the VS Code editor) do not expose a cursor through Accessibility; automatic
   conversion leans on the system dictionaries, so rare words and slang fall
   through; and languages with no system dictionary (Belarusian, Armenian,
   Georgian) cannot be judged at all.

## Decisions

1. **Automatic from the first version**, as Punto and Caramba are. Two hotkeys
   sit beside it, both explicit requests rather than guesses: **convert the last
   word** (for when the automatic rules declined, which they will — rare words,
   slang, a language with no dictionary) and **undo the last conversion**. The
   module's value is that you do not have to think; the hotkeys are for when it
   was wrong either way.
2. **Convert only on both answers agreeing:** the word is *not* a word in the
   layout it was typed in, *and it is* a word once translated. A word that is
   valid as typed is never touched, whatever else is true about it.
3. **Every conversion is undoable** by a dedicated hotkey. Without that, an
   automatic switcher is a program that occasionally rewrites your text while
   you watch.
4. **Refuse rather than guess** in secure contexts: password fields, secure
   input, and an app blocklist that ships with password managers and terminals
   in it. In a terminal, `ghbdtn` may be a filename.
5. **Nothing typed is ever written down.** No key content in the log, no buffer
   on disk, buffer cleared when secure input turns on.

## Architecture

Descriptor plus engine, as every other module (ARCHITECTURE.md § Modules):
`Module_Layout_Engine`, `Module_Layout_UI`, registered in `ModuleRegistry.all`.

### Pure logic — `Engine/Logic/`

Everything that decides is pure, because the alternative is testing by typing.

| Unit | Answers |
|---|---|
| `TypingBuffer` | What is the current word? A state machine over key events: accumulates characters; resets on space, return, punctuation, arrows, a mouse click, or a focus change. |
| `LayoutVerdict` | Should this word be converted? Takes the word, the spell-checker's verdict for it in both layouts, and the guard rules below. Returns `leave` or `convert(to:)`. |
| `SwitchPlan` | How is the conversion performed? Number of backspaces, the string to insert, whether the input source changes too. |
| `Exceptions` | Has the user marked this word "never touch"? |
| `AppScope` | Does this app take conversions at all? Per-app rules, same shape as Keep Awake and VPN already use. |
| `UndoRecord` | What did the last conversion change, and is it still undoable? Holds the word before and after and where it happened; invalidated by a focus change or by any typing that is not the undo hotkey, because by then the text underneath has moved. |

`LayoutVerdict`'s guard rules, all of them reasons to *decline*:

- the word is valid as typed;
- shorter than three characters;
- contains a digit;
- looks like a path, a URL or an email;
- is entirely upper case (acronyms);
- is in the user's exception list;
- no dictionary is available for either language.

### Ports — thin, one syscall family each

| Port | Backed by |
|---|---|
| `KeyTapPort` | `CGEventTap`, listen-only |
| `TypingPort` | `CGEvent.keyboardSetUnicodeString` + backspaces, stamped via `CGEventSource.userData` |
| `LayoutPort` | Text Input Sources: enumerate, read current, select |
| `TranslationPort` | `UCKeyTranslate` between two sources |
| `SpellPort` | `NSSpellChecker`, per language |
| `SecureInputPort` | `IsSecureEventInputEnabled()` |
| `FocusPort` | `AXUIElement`: the focused element's role, and the frontmost app's bundle id |

### Data flow

```
key event → (is it ours? drop) → TypingBuffer
                                      │  word boundary reached
                                      ▼
                    AppScope ─ no ─→ leave
                        │ yes
                        ▼
      SecureInputPort / FocusPort ─ secure ─→ leave, clear buffer
                        │ safe
                        ▼
            TranslationPort → candidate word
                        │
                        ▼
              SpellPort × 2 → LayoutVerdict
                        │ convert
                        ▼
                   SwitchPlan → TypingPort + LayoutPort
                        │
                        ▼
                 remember for undo
```

The hotkeys enter the same pipeline further down: **convert last word** skips
`LayoutVerdict` (the user has already decided) but not the secure-context
checks, and **undo** replays `UndoRecord` through `TypingPort` in reverse.

## Permissions

Accessibility, and nothing else. Without it the tap yields nothing: the module
must say so where it is switched on — `HelmPermissionNote` and `PermissionNeed`
already do this for the other modules — and must not present itself as working.

## Error handling

- **No Accessibility:** module reports "needs Accessibility", offers the settings
  pane, does nothing else.
- **Secure input on:** conversions suspended, buffer cleared, state visible in
  the panel so the silence is explained.
- **No dictionary for a language:** that language pair is not eligible for
  automatic conversion; the hotkey still works, since the user asked explicitly.
- **Translation unavailable** (a layout with no `UCKeyTranslate` data): the pair
  is skipped rather than approximated.
- **Typing failed** (target app rejected synthetic events): the conversion is
  abandoned, not retried — a partial retype is worse than no conversion.

## Testing

- `TypingBuffer`: a table of event sequences → expected word and reset points,
  including every boundary character and a focus change mid-word.
- `LayoutVerdict`: a table of (word, verdict in each layout, flags) → decision,
  with one case per guard rule, plus the case that matters most — a word that is
  valid as typed is never converted, even when it is also valid translated
  (`ras` / `кфы`).
- `SwitchPlan`: backspace count for multi-byte and composed characters.
- `Exceptions`, `AppScope`: membership and precedence.
- `UndoRecord`: what invalidates it — a focus change, a click, further typing —
  because an undo applied to text that has moved on corrupts a second place.
- Live, behind `HELM_BENCH=1`: `UCKeyTranslate` against the layouts actually
  installed on the machine, so a wrong mapping shows up as a failure rather than
  as mangled text.

## Not in this version

- Screen Sharing (RuSwitcher runs a mode on both machines for it).
- Languages without a system dictionary.
- Converting a selection rather than the last word.
- Anything that needs a cursor position from an app that draws its own text.
