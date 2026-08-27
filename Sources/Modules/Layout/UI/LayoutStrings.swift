import HelmRuntime
import HelmUI
import Module_Layout_Engine

enum LyStr {
    /// Broader than "layout" on purpose: the module id stays `layout`, but the
    /// name has room for whatever else belongs to the keyboard later.
    static var moduleName: String { L("Keyboard") }
    static var summary: String { L("Fixes words typed in the wrong keyboard layout") }
    static var automatic: String { L("Fix as I type") }
    static var automaticNote: String { L("A word is only changed when it is not a word as typed and is one once swapped. Anything valid is left alone.") }
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
    static var on: String { L("Active") }
    static var notWatching: String { L("Not running") }
    static var paused: String { L("Paused") }
    static var lastChange: String { L("Last change") }

    /// Without the grant the *typing* half can do nothing at all, so the page
    /// says that instead of drawing every setting under a banner. Not «every
    /// setting»: the language indicator reads the input source through TIS and
    /// works without the grant — the page draws it below this message, and a
    /// message claiming otherwise called its own neighbour a lie.
    static var deniedTitle: String { L("Helm is not watching the keyboard") }
    static var deniedMessage: String {
        L("Fixing what you type needs Accessibility: without it Helm sees no keystrokes and changes nothing. The language indicator below works without it.")
    }

    /// The caption under the hero figure, which has to agree with it: «1 слово»,
    /// «17 слов». Interpolated, so it keeps its own table — the lookup would
    /// happen after the number was already in the string (CLAUDE.md §
    /// Localization).
    static func fixedToday(_ count: Int, language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: Plural.russian(count, "слово", "слова", "слов") + " исправлено сегодня",
            .es: count == 1 ? "palabra corregida hoy" : "palabras corregidas hoy",
            .fr: count <= 1 ? "mot corrigé aujourd’hui" : "mots corrigés aujourd’hui",
            .de: count == 1 ? "Wort heute korrigiert" : "Wörter heute korrigiert",
            .pt: count == 1 ? "palavra corrigida hoje" : "palavras corrigidas hoje",
            .ja: "語を今日修正",
            .zh: "个词今天已修正",
        ]
        let english = count == 1 ? "word fixed today" : "words fixed today"
        return language == .en ? english : table[language] ?? english
    }
    static var introSubtitle: String { L("Before it starts changing what you type.") }
    static var introWhat: String { L("Type ghbdtn in the wrong layout and it becomes привет, with the input source switching to match.") }
    static var introWhen: String { L("Only when what you typed is not a word and becomes one once the layout is switched. Anything that is already a word is left alone.") }
    static var introWhere: String { L("Never in a password field. And not in the terminals and password managers Helm knows — add any others in Settings.") }
    /// Names the gesture rather than promising «the same key»: an automatic
    /// conversion is a change the person pressed no key for, so «the same key
    /// again» named nothing. `gesture` is the bound tap key or the recorded
    /// chord; nil means neither exists, and the sentence must not promise an
    /// undo that does not. Interpolated, so it keeps its own table.
    static func introUndo(gesture: String?, language: AppLanguage = AppLanguage.current) -> String {
        let tryIt: [AppLanguage: String] = [
            .en: "And there is a field on this page to try it in, before it touches anything real.",
            .ru: "А на этой странице есть поле, где можно всё попробовать, прежде чем это коснётся настоящего текста.",
            .es: "Y en esta página hay un campo para probarlo antes de que toque nada real.",
            .fr: "Et cette page contient un champ pour l’essayer, avant qu’il ne touche à rien de réel.",
            .de: "Und auf dieser Seite gibt es ein Feld zum Ausprobieren, bevor etwas Echtes berührt wird.",
            .pt: "E nesta página há um campo para experimentar, antes que toque em algo real.",
            .ja: "実際の文章に触れる前に、このページの入力欄で試せます。",
            .zh: "本页还有一个输入框，可以在触及真实文字之前先试一试。",
        ]
        let undo: [AppLanguage: String]
        if let gesture {
            undo = [
                .en: "Every change can be undone — press \(gesture) again, before you type anything else, in the app it happened in.",
                .ru: "Любую замену можно отменить — нажмите «\(gesture)» ещё раз, до того, как наберёте что-то ещё, в том приложении, где она произошла.",
                .es: "Cada cambio se puede deshacer: pulsa \(gesture) otra vez antes de escribir nada más, en la app donde ocurrió.",
                .fr: "Chaque changement peut être annulé — appuyez de nouveau sur \(gesture) avant de taper autre chose, dans l’app où c’est arrivé.",
                .de: "Jede Änderung lässt sich widerrufen — \(gesture) erneut drücken, bevor du etwas anderes tippst, in der App, in der sie passiert ist.",
                .pt: "Cada alteração pode ser desfeita — pressione \(gesture) novamente antes de digitar mais nada, no app em que aconteceu.",
                .ja: "変更は元に戻せます。何か入力する前に、同じアプリで \(gesture) をもう一度押してください。",
                .zh: "每次更改都可以撤销——请在继续输入之前，在发生更改的应用中再按一次 \(gesture)。",
            ]
        } else {
            undo = [
                .en: "A change can be undone once a fix key is set — pick one under Shortcuts.",
                .ru: "Отменять замены можно, когда назначена клавиша — выберите её в разделе «Сочетания клавиш».",
                .es: "Un cambio se puede deshacer cuando hay una tecla asignada: elígela en «Atajos».",
                .fr: "Un changement peut être annulé dès qu’une touche est choisie — dans la section des raccourcis.",
                .de: "Eine Änderung lässt sich widerrufen, sobald eine Taste gewählt ist — unter „Kurzbefehle“.",
                .pt: "Uma alteração pode ser desfeita quando há uma tecla definida — escolha uma em Atalhos.",
                .ja: "修正キーを設定すると変更を元に戻せます。「ショートカット」で選んでください。",
                .zh: "设置修复键后即可撤销更改——请在“快捷键”中选择。",
            ]
        }
        guard let head = undo[language] ?? undo[.en],
              let tail = tryIt[language] ?? tryIt[.en] else { return "" }
        return sentences(head, tail, language: language)
    }
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
    /// «Select it again to change it back», not «tapping again puts it back»:
    /// a fixed selection leaves no undo record — the caret's landing place
    /// after a selection replace is the app's business, so a blind reverse
    /// edit could eat text — and the old sentence promised one.
    static var tapKeyHint: String { L("Tap it on its own. With text selected it fixes the selection — select it again to change it back; otherwise it fixes the last word, and tapping again puts it back. Held down or pressed with anything else it is still an ordinary modifier.") }
    /// Shown for either Control. A solo Control tap is VoiceOver's own
    /// «pause speech» gesture, so for a VoiceOver user this binding fires
    /// both at once.
    static var controlKeyNote: String { L("Tapping Control on its own also pauses VoiceOver speech. If you use VoiceOver, pick another key.") }

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
    /// The system's own spelling of its input menu's last item, read from
    /// `TextInputMenuCore.bundle` (key `Open Keyboard Settings`) rather than
    /// translated again — German keeps the table's no-break space before the
    /// ellipsis. This key used to be «Open Keyboard settings…», a near-copy
    /// with four of eight rows retranslated by hand.
    static var openKeyboardSettings: String { L("Open Keyboard Settings…") }
    /// macOS's own name for its palette, read from AppKit's
    /// `InputManager.loctable` (key `Emoji & Symbols`) rather than translated
    /// again — the Edit menu of every app spells it this way. Helm's zh takes
    /// the `zh_CN` row and its pt the `pt_BR` row, the variants the rest of
    /// the app follows.
    static var emojiAndSymbols: String { L("Emoji & Symbols") }
    /// The emoji door's full title, built the way the system input menu builds
    /// it: the `Show palette class IM` template (`TextInputMenuCore.bundle`)
    /// around the palette's own name — so the sentence cannot drift from the
    /// palette it opens, the same construction as `VPNStr.secretNeedsAPress`.
    /// Interpolated, so the template keeps its own table.
    static func showEmojiPanel(language: AppLanguage = AppLanguage.current) -> String {
        let name = L("Emoji & Symbols", language: language)
        let table: [AppLanguage: String] = [
            .ru: "Показать панель «\(name)»",
            .es: "Mostrar \(name)",
            .fr: "Afficher \(name)",
            .de: "\(name) einblenden",
            .ja: "\(name)を表示",
            .zh: "显示\(name)",
            .pt: "Mostrar \(name)",
        ]
        return language == .en ? "Show \(name)" : table[language] ?? "Show \(name)"
    }
    /// The system input menu's switch, spelled its way: `TextInputMenuCore.bundle`,
    /// key `Show Name of Source in Menu Bar`.
    static var showInputSourceName: String { L("Show Input Source Name") }
    static var neverThisWord: String { L("Never this word") }
    static var audible: String { L("Play a sound when a word is fixed") }
    /// Built from the current binding, never spelled by hand — the same
    /// construction as `VPNStr.secretNeedsAPress`, so the sentence cannot
    /// drift from the control it names. `gesture` is the tap key's name or
    /// the recorded chord's label; «press» covers both where «tap» does not.
    /// Interpolated, so it keeps its own table.
    static func undoHint(gesture: String, language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "Чтобы отменить, нажмите «\(gesture)» ещё раз — до того, как наберёте что-то ещё, в том приложении, где это произошло.",
            .es: "Para deshacerlo, pulsa \(gesture) otra vez antes de escribir nada más, en la app donde ocurrió.",
            .fr: "Pour annuler, appuyez de nouveau sur \(gesture) avant de taper autre chose, dans l’app où c’est arrivé.",
            .de: "Zum Widerrufen \(gesture) erneut drücken, bevor du etwas anderes tippst, in der App, in der es passiert ist.",
            .pt: "Para desfazer, pressione \(gesture) novamente antes de digitar mais nada, no app em que aconteceu.",
            .ja: "元に戻すには、何か入力する前に、同じアプリで \(gesture) をもう一度押してください。",
            .zh: "要撤销，请在继续输入之前，在发生更改的应用中再按一次 \(gesture)。",
        ]
        let english = "Undo it by pressing \(gesture) again — before you type anything else, in the app it happened in."
        return language == .en ? english : table[language] ?? english
    }
    /// The honest line for the state the old hint lied about: no tap key and
    /// no chord means no undo exists, and a sentence promising one described
    /// a gesture that could never fire.
    static var undoImpossible: String { L("No key is assigned — this change can only be put back by hand.") }
    /// The row's own label when the change it names was taken back: the record
    /// outlives the rejection (that is when «Never this word» earns its keep),
    /// and it must say which state it is in.
    static var lastChangeUndone: String { L("Last change (undone)") }
    /// Under the triggers when all three are off: no ending ever confirms a
    /// word, so «Fix as I type» is dead however green the badge above is.
    static var noTriggers: String { L("Nothing is switched on — words will not be fixed as you type.") }

    /// What a VoiceOver reader hears when a word is rewritten in the app they
    /// are typing in. The words themselves are in it — an announcement is
    /// spoken and gone, the one channel with the same lifetime as the memory
    /// the module keeps them in. The undo tail rides only when an undo gesture
    /// actually exists. Interpolated, so it keeps its own table.
    static func fixedAnnouncement(before: String, after: String, undoable: Bool,
                                  language: AppLanguage = AppLanguage.current) -> String {
        let fixed: [AppLanguage: String] = [
            .en: "Fixed: \(before) → \(after).",
            .ru: "Исправлено: \(before) → \(after).",
            .es: "Corregido: \(before) → \(after).",
            .fr: "Corrigé\u{00A0}: \(before) → \(after).",
            .de: "Korrigiert: \(before) → \(after).",
            .pt: "Corrigido: \(before) → \(after).",
            .ja: "修正しました：\(before) → \(after)。",
            .zh: "已修正：\(before) → \(after)。",
        ]
        let tail: [AppLanguage: String] = [
            .en: "Tap the key again to undo, before you type anything else.",
            .ru: "Нажмите клавишу ещё раз, до того, как наберёте что-то ещё, чтобы отменить.",
            .es: "Pulsa la tecla otra vez antes de escribir nada más para deshacer.",
            .fr: "Appuyez de nouveau sur la touche avant de taper autre chose pour annuler.",
            .de: "Taste erneut antippen, bevor du etwas anderes tippst, um zu widerrufen.",
            .pt: "Toque na tecla novamente antes de digitar mais nada para desfazer.",
            .ja: "何か入力する前にもう一度キーを押すと元に戻せます。",
            .zh: "在继续输入之前再按一次该键即可撤销。",
        ]
        let head = fixed[language] ?? fixed[.en] ?? ""
        guard undoable, let more = tail[language] ?? tail[.en] else { return head }
        return sentences(head, more, language: language)
    }

    /// Two sentences joined the way the language joins them: the CJK pair runs
    /// on after its full stop, the others take a space. Spelled once — two
    /// functions here each carried the same ternary.
    private static func sentences(_ head: String, _ tail: String,
                                  language: AppLanguage) -> String {
        head + (language == .ja || language == .zh ? "" : " ") + tail
    }
}
