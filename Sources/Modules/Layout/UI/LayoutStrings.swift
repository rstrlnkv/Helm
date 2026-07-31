import HelmUI
import Module_Layout_Engine

enum LyStr {
    /// Broader than "layout" on purpose: the module id stays `layout`, but the
    /// name has room for whatever else belongs to the keyboard later.
    static var moduleName: String { L("Keyboard") }
    static var summary: String { L("Fixes words typed in the wrong keyboard layout") }
    static var automatic: String { L("Fix as I type") }
    static var automaticNote: String { L("A word is only changed when it is not a word as typed and is one once swapped. Anything valid is left alone.") }
    static var needsAccessibility: String { L("Without Accessibility Helm cannot see what you type, and this does nothing.") }
    static var suspended: String { L("Paused — a password field is in front, and Helm never reads one.") }
    static var exceptions: String { L("Never change these words") }
    static var exceptionsHint: String { L("One per line.") }
    static var triggers: String { L("When to fix") }
    static var triggersHint: String { L("A word is checked when you finish it this way. Moving the caret or clicking elsewhere never converts — by then you have moved on.") }
    static var onSpace: String { L("When Space is pressed") }
    static var onReturn: String { L("When Return is pressed") }
    static var onPunctuation: String { L("When a punctuation mark is typed") }
    static var noAppsYet: String { L("Nothing listed. A few terminals and password managers are left alone already — add any others here.") }
    static var addApp: String { L("Add app…") }
    static var ruleOn: String { L("Fix") }
    static var ruleOff: String { L("Don’t fix") }
    /// «Сочетания клавиш» is what macOS calls these — 12 tables to 0 for
    /// `Keyboard shortcut`, and 2 to 0 for the plural. «Горячие клавиши» is a
    /// colloquialism the system never uses, and this file already said the
    /// right thing thirty lines down (`orShortcut`). One name per thing.
    static var shortcuts: String { L("Shortcuts") }
    static var apps: String { L("Rules for specific apps") }
    static var appsHint: String { L("Terminals and password managers are left alone: there, a wrong-looking word is often exactly right.") }
    static var metricToday: String { L("TODAY") }
    static var metricState: String { L("STATE") }
    static var on: String { L("Active") }
    static var notWatching: String { L("Not running") }
    static var paused: String { L("Paused") }
    static var lastChange: String { L("Last change") }
    static var introTitle: String { L("Keyboard") }
    static var introSubtitle: String { L("Before it starts changing what you type.") }
    static var introWhat: String { L("Type ghbdtn in the wrong layout and it becomes привет, with the input source switching to match.") }
    static var introWhen: String { L("Only when what you typed is not a word and becomes one once the layout is switched. Anything that is already a word is left alone.") }
    static var introWhere: String { L("Never in a password field. And not in the terminals and password managers Helm knows — add any others in Settings.") }
    static var introUndo: String { L("Every change can be undone — tap the same key again, in the app it happened in. And there is a field on this page to try it in, before it touches anything real.") }
    static var introStart: String { L("Got it") }
    static var autoReplaceSection: String { L("Abbreviations") }
    static var autoReplaceNote: String { L("A short token you type often, and what it stands for. It expands when you finish the word.") }
    static var abbreviation: String { L("Abbreviation") }
    static var expansion: String { L("Stands for") }
    static var addAbbreviation: String { L("Add") }
    static var noAbbreviations: String { L("No abbreviations yet") }
    static var fixCapitals: String { L("Fix a capital held too long") }
    static var fixCapitalsNote: String { L("ПРивет → Привет. Never ПРИВЕТ — that is shouting on purpose — and never a word with a digit in it.") }
    static var tryIt: String { L("Try it") }
    static var tryItPlaceholder: String { L("Type ghbdtn and press space") }
    static var tryItHint: String { L("This is the real thing, not a demonstration: it works here exactly as it does anywhere else.") }
    static var indicator: String { L("Language indicator") }
    static var indicatorShow: String { L("Show it in the menu bar") }
    static var indicatorHint: String { L("Helm’s own copy of the menu-bar indicator, with the choices the system’s one does not offer. macOS shows its own — turn that one off in Keyboard settings, or you get two.") }
    static var tapKey: String { L("Fix with") }
    static var tapKeyHint: String { L("Tap it on its own. With text selected it fixes the selection; otherwise it fixes the last word, and tapping again puts it back. Held down or pressed with anything else it is still an ordinary modifier.") }

    /// Shown only when 🌐︎ is chosen. macOS may already have that key doing
    /// something, and Helm cannot make it stop — the setting is the person's.
    static var globeNote: String { L("macOS may already use 🌐︎ to switch input source, open emoji or start dictation. Set “Press 🌐︎ to: Do Nothing” in Keyboard settings, or it will do both. Keyboards without a 🌐︎ key never send it.") }

    /// Shown when a left-hand key is chosen. Not a warning against it — it is
    /// their keyboard — but the trade should be visible at the moment it is
    /// made, not discovered later.
    static var leftKeyNote: String { L("This is a key you type with. It still works normally when held or combined, but a stray tap on its own will fix the last word.") }

    /// The one chord, for keyboards with no right-hand modifier to tap.
    static var orShortcut: String { L("Or a key combination") }
    static func tapKeyName(_ key: TapKey) -> String {
        switch key {
        case .off: return L("Off")
        case .rightCommand: return L("Right ⌘")
        case .rightOption: return L("Right ⌥")
        case .rightControl: return L("Right ⌃")
        case .rightShift: return L("Right ⇧")
        case .leftCommand: return L("Left ⌘")
        case .leftOption: return L("Left ⌥")
        case .leftControl: return L("Left ⌃")
        case .leftShift: return L("Left ⇧")
        case .globe: return L("🌐︎")
        }
    }
    static var badgeStyle: String { L("Style") }
    static var badgeSize: String { L("Size") }
    static func badgeStyleName(_ style: BadgeStyle) -> String {
        switch style {
        case .plain: return L("Letters")
        case .filled: return L("Letters on a filled badge")
        case .outlined: return L("Letters in a frame")
        case .flagEmoji: return L("Flag, system")
        case .flagDrawn: return L("Flag")
        }
    }
    static var badgePreview: String { L("Your layouts, as they will look:") }
    static var flagNote: String { L("A layout that names no country keeps its letters, in a frame the same size as a flag.") }
    static var openKeyboardSettings: String { L("Open Keyboard settings…") }
    static var neverThisWord: String { L("Never this word") }
    static var audible: String { L("Play a sound when a word is fixed") }
    static var undoHint: String { L("Undo it by tapping the same key again, in the app it happened in.") }
}
