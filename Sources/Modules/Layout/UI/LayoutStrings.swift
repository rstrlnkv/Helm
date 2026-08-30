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
    /// **It said «One per line.» until the list stopped being lines.** That was
    /// a description of a `TextEditor` — true of the control, and the control is
    /// gone. A note under a list is the place to say what the list *does*, not
    /// how it is typed into: the shape is visible and the rule is not.
    static var exceptionsHint: String {
        L("These are left exactly as you typed them, whatever the dictionary thinks.")
    }
    static var addApp: String { L("Add app…") }
    static var ruleOn: String { L("Fix") }
    static var ruleOff: String { L("Don’t fix") }
    /// «Сочетания клавиш» is what macOS calls these — 12 tables to 0 for
    /// `Keyboard shortcut`, and 2 to 0 for the plural. «Горячие клавиши» is a
    /// colloquialism the system never uses, and this file already said the
    /// right thing thirty lines down (`orShortcut`). One name per thing.
    static var shortcuts: String { L("Shortcuts") }
    static var apps: String { L("Rules for specific apps") }
    /// One caption for the list, and it explains the rows above it rather than
    /// describing a rule the page keeps invisible.
    ///
    /// It replaces two: an empty state saying «a few terminals and password
    /// managers are left alone already» and a footer saying almost the same
    /// thing, neither of which named one of them. The apps are drawn now.
    static var appsWhy: String {
        L("Terminals and password managers start switched off: there, a word that looks wrong is often exactly right. Switch any of them on, or add an app of your own.")
    }
    static var lastChange: String { L("Last change") }

    /// The tile's estimate, without the period on the end: the caption above it
    /// already carries the period, and saying it twice on a 280 pt tile reads
    /// as two different spans. `timeIn(_:)` is the page's version, which has to
    /// carry it because the page has no caption above the figure.
    /// Takes a language rather than reading `AppLanguage.current`, so a guard
    /// can ask it about German. This machine runs in Russian, so a test that
    /// reads `.current` exercises exactly one of eight — CLAUDE.md § A test
    /// parameterized by an explicit language, and the reason a mutation planted
    /// in an English value once passed.
    static func notSpentTypingAgain(language: AppLanguage = AppLanguage.current) -> String {
        L("not spent typing again", language: language)
    }

    /// The bar row's name. A drawing is invisible to VoiceOver unless somebody
    /// says what it is, and `NamedControlsTests` scans the source for the shape
    /// of one that nobody did.
    static var fortnight: String { L("Last fourteen days") }

    /// Without the grant the *typing* half can do nothing at all, so the page
    /// says that instead of drawing every setting under a banner. Not «every
    /// setting»: the language indicator reads the input source through TIS and
    /// works without the grant — the page draws it below this message, and a
    /// message claiming otherwise called its own neighbour a lie.
    static var deniedTitle: String { L("Helm is not watching the keyboard") }

    /// The hero's own words without the grant. Short, because the hero is a
    /// figure and not a paragraph — the long sentence lives once, under it.
    ///
    /// **«Not watching», not «Not running».** The module is running; the tap is
    /// not. And the window header already says «Not active» in its own words,
    /// so a third spelling of the same fact on one screen is what this avoids.
    static var heroNotWatching: String { L("Not watching") }
    static var heroNotWatchingWhy: String { L("macOS is not delivering keystrokes to Helm") }

    /// What the empty state is for once the hero has said the rest: the two
    /// things somebody weighing this permission actually wants to know.
    static var deniedGuarantee: String {
        L("Helm never reads a password: a field the system marks as secure is skipped whole.")
    }
    static var indicatorWorksAnyway: String {
        L("The language indicator below works without this permission.")
    }

    static var introWhat: String { L("Type ghbdtn in the wrong layout and it becomes привет, with the input source switching to match.") }
    static var introWhen: String { L("Only when what you typed is not a word and becomes one once the layout is switched. Anything that is already a word is left alone.") }
    static var introWhere: String { L("Never in a password field. And not in the terminals and password managers Helm knows — add any others in Settings.") }
    /// The intro's undo point: the same instruction the page's note gives,
    /// plus the one thing only the intro can say.
    ///
    /// **It used to spell the instruction out again.** Two eight-language
    /// tables held the same three conditions in the same order — press it
    /// again, before you type anything else, in the app it happened in — so one
    /// sentence cost sixteen hand-maintained translations and had two places to
    /// drift from the control it names. `undoHint` is the sentence;
    /// `undoImpossible` is the honest version when no key is bound, and it must
    /// stay honest: a sentence promising an undo that cannot fire is worse than
    /// no sentence. What is left here is the tail — that this page has a field
    /// to try it in — which is true of nowhere else and so belongs to nowhere
    /// else.
    ///
    /// `gesture` is the bound tap key or the recorded chord; nil means neither
    /// exists. Interpolated, so it keeps its own table.
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
        let head = gesture.map { undoHint(gesture: $0, language: language) }
            ?? undoImpossible(language: language)
        guard let tail = tryIt[language] ?? tryIt[.en] else { return head }
        return sentences(head, tail, language: language)
    }

    /// The two faces of one control, so a reader who opened the points can put
    /// them away again — a disclosure that only opens is a disclosure that has
    /// stopped being one.
    // MARK: - The tour

    /// The button on the row headed `tourTitle`. A row names, a button acts —
    /// spelling both with `tourTitle` drew «How it works [How it works]», the
    /// only `HelmSettingRow` in `Sources/Modules` with a button in its trailing
    /// slot repeating its own label.
    static var showTour: String { L("Show") }

    /// The lists window's way out. Six modules already spell `L("Done")` for
    /// themselves — a string this many screens draw belongs in `HelmUI`, and
    /// moving it is a sweep of its own rather than a line in a module's polish.
    static var listsDone: String { L("Done") }

    static var tourTitle: String { L("How it works") }
    static var tourBack: String { L("Back") }
    static var tourNext: String { L("Next") }
    /// «2 of 4». Interpolated, so it keeps its own table.
    static func tourStep(_ index: Int, of total: Int,
                         language: AppLanguage = AppLanguage.current) -> String {
        L("\(index) of \(total)",
          [.ru: "\(index) из \(total)", .es: "\(index) de \(total)",
           .fr: "\(index) sur \(total)", .de: "\(index) von \(total)",
           .pt: "\(index) de \(total)", .ja: "\(total)分の\(index)",
           .zh: "第\(index)步，共\(total)步"],
          language: language)
    }
    static var tourWhatTitle: String { L("What it does") }
    static var tourSwitchesTitle: String { L("What you can switch on") }
    static var tourSwitchesBody: String {
        L("These are live: switch one here and it is switched.")
    }
    static var tourUndoTitle: String { L("If it gets one wrong") }
    static var tourTryBody: String {
        L("A real field, not a demonstration. Type ghbdtn, press space, and watch.")
    }
    static var introStart: String { L("Got it") }
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
    /// One line under the row. The rest is behind the ⓘ.
    ///
    /// **It was the module's whole manual in a caption** — 41 words, three
    /// sentences, one parenthetical, and seven drawn lines in Russian at the
    /// 860 pt window. `HelmExplainer` exists for exactly that: its own doc
    /// names a 606-character German caption as the case it was built for, and
    /// this page was not using it. What stays here is what the row does; what
    /// moves is «what happens if I do», which is what an ⓘ answers.
    static var tapKeyHint: String { L("Tap it on its own: it fixes the selection, or the last word.") }

    /// The one value that means the control does nothing, which the note used
    /// to describe as if it did.
    static var tapKeyOff: String {
        L("No key — nothing fixes a selection or the last word on demand. Pick one, or set a key combination below.")
    }

    /// Behind the ⓘ beside «Fix with». Assembled from the key in force, so a
    /// key with nothing special about it opens two blocks and no warnings.
    static func tapKeyExplainer(_ key: TapKey) -> HelmExplainer.Content? {
        guard key != .off else { return nil }
        var blocks: [HelmExplainer.Block] = [
            .text(L("Tap again to put the change back, or select the text again to change it back.")),
            .text(L("Held down, or pressed together with anything else, it stays an ordinary modifier — everything you already use it for keeps working.")),
        ]
        if key == .globe { blocks.append(.text(globeNote)) }
        if key.isFrequentlyUsed { blocks.append(.text(leftKeyNote)) }
        if key == .leftControl || key == .rightControl { blocks.append(.text(controlKeyNote)) }
        return HelmExplainer.Content(title: tapKey, blocks: blocks)
    }

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
    static func badgeStyleName(_ style: BadgeStyle) -> String {
        switch style {
        case .plain: return L("Letters")
        case .filled: return L("Letters on a filled badge")
        case .outlined: return L("Letters in a frame")
        case .flagDrawn: return L("Flag")
        // **Not the system's «Show Input Source Name», though it draws the same
        // thing.** That is macOS's name for a *switch*, and here it is the value
        // of a «Style» picker, so the row read «Вид: Показывать имя источника
        // ввода» — an instruction sitting where a noun belongs. The rule about
        // reading the system's spelling covers a thing macOS also names; macOS
        // names the switch, not the style, and this is the style.
        case .sourceName: return L("Layout name")
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
    /// The window's own title. Not «Settings» and not the module's name — the
    /// window holds two lists and says so, because a window titled «Keyboard»
    /// beside a settings window titled «Keyboard» is two of one thing.
    static var listsWindowTitle: String { L("Words and apps") }
    /// The rows on the page that open the window, each carrying its own count
    /// so the page still answers «how many» without it being opened — which is
    /// the one thing a list behind a button owes the person who put a word
    /// there by pressing «Never this word» somewhere else.
    ///
    /// The counted nouns come from `Plural`, which already declines them in all
    /// eight languages; the empty case is its own sentence, because «0 words»
    /// is a count where «none» is a state.
    static func exceptionsRow(_ count: Int,
                              language: AppLanguage = AppLanguage.current) -> String {
        guard count > 0 else { return L("No words set aside", language: language) }
        let table: [AppLanguage: String] = [
            .ru: Plural.russian(count, "слово", "слова", "слов"),
            .es: count == 1 ? "palabra" : "palabras",
            .fr: count <= 1 ? "mot" : "mots",
            .de: count == 1 ? "Wort" : "Wörter",
            .pt: count == 1 ? "palavra" : "palavras",
            .ja: "\(count)語",
            .zh: "\(count)个词",
        ]
        let english = count == 1 ? "word" : "words"
        guard language != .en, let counted = table[language] else { return "\(count) " + english }
        return language == .ja || language == .zh ? counted : "\(count) " + counted
    }

    static func appsRow(_ count: Int,
                        language: AppLanguage = AppLanguage.current) -> String {
        guard count > 0 else { return L("Every app but the ones Helm leaves alone",
                                        language: language) }
        return Plural.apps(count, language: language.rawValue)
    }

    static var neverThisWord: String { L("Never this word") }
    static var noExceptions: String { L("No words yet") }
    /// The field's placeholder and its VoiceOver name at once — a placeholder
    /// disappears the moment there is a value to read, so it cannot be the only
    /// thing naming the field.
    static var exceptionPrompt: String { L("A word to leave alone") }
    static var addException: String { L("Add") }
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
    static func undoImpossible(language: AppLanguage = AppLanguage.current) -> String {
        L("No key is assigned — this change can only be put back by hand.", language: language)
    }
    /// The row's own label when the change it names was taken back: the record
    /// outlives the rejection (that is when «Never this word» earns its keep),
    /// and it must say which state it is in.
    static var lastChangeUndone: String { L("Last change (undone)") }
    /// Under the triggers when all three are off: no ending ever confirms a
    /// word, so «Fix as I type» is dead however green the badge above is.
    /// The period segment, and the metric the hero is showing.
    ///
    /// The five are drawn as words rather than as glyphs: «7 дней» and
    /// «Всё время» are not a picture anybody would recognise, and a segment of
    /// five unlabelled marks is a puzzle. The metric beside it *is* two glyphs —
    /// a letter and a clock — because those two are.
    static func periodName(_ period: ConversionPeriod,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch period {
        case .today: return L("Today", language: language)
        case .week: return L("Week", language: language)
        case .month: return L("Month", language: language)
        case .year: return L("Year", language: language)
        case .allTime: return L("All time", language: language)
        }
    }

    static var period: String { L("Period") }


    /// Under the figure when it is showing words: how many, and over what.
    ///
    /// The Russian declines the participle with the noun. «слова исправлено» —
    /// a plural noun under a neuter singular short participle — was wrong for
    /// counts of 2, 3 and 4, which is the bucket a light user sees most.
    static func wordsIn(_ period: ConversionPeriod, count: Int,
                        language: AppLanguage = AppLanguage.current) -> String {
        wordsPutRight(count: count, language: language)
            + " · " + periodName(period, language: language).lowercased()
    }

    /// The noun on its own, for a surface where a control beside it already
    /// names the period.
    ///
    /// **Split out rather than written twice.** The 2×N tile carries a pop-up
    /// showing «Месяц» and said «· месяц» under the figure at the same time —
    /// one word twice on a 280 pt tile. The period belongs to whichever element
    /// can change it, and where nothing can (1×1, 2×1) it belongs to the
    /// caption. Both spellings come from here so they cannot drift apart.
    static func wordsPutRight(count: Int,
                              language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: Plural.russian(count, "слово исправлено", "слова исправлены", "слов исправлено"),
            .es: count == 1 ? "palabra corregida" : "palabras corregidas",
            .fr: count <= 1 ? "mot corrigé" : "mots corrigés",
            .de: count == 1 ? "Wort korrigiert" : "Wörter korrigiert",
            .pt: count == 1 ? "palavra corrigida" : "palavras corrigidas",
            .ja: "語を修正",
            .zh: "个词已修正",
        ]
        let english = count == 1 ? "word put right" : "words put right"
        return language == .en ? english : table[language] ?? english
    }



    /// The hero when nothing has been put right yet — the state no edition of
    /// the redesign ever drew, and the one a fresh install sees.
    static var nothingYet: String { L("Watching your words") }
    static var nothingYetNote: String { L("Nothing has needed putting right so far.") }


    /// Under the same card when macOS has no dictionary for a layout somebody
    /// has installed.
    ///
    /// **It says what still works.** The gesture asks no dictionary —
    /// `LayoutVerdict.decideForced` skips it by design — so this is «Helm
    /// cannot decide for itself here», not «this does not work here». The two
    /// read very differently to somebody who has just switched a language on.
    ///
    /// Interpolated, so it keeps its own table. The names come from
    /// `InputSourceInfo`, which is macOS's own name for the layout — the same
    /// rule as the pane names: read the system's spelling rather than invent
    /// one.
    static func noDictionary(layouts: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "macOS не даёт словаря для \(layouts), поэтому сам Helm на этой раскладке ничего не решает. Исправление клавишей работает.",
            .es: "macOS no tiene diccionario para \(layouts), así que Helm no decide por su cuenta en esa distribución. La corrección con la tecla sigue funcionando.",
            .fr: "macOS ne fournit pas de dictionnaire pour \(layouts) : Helm ne décide donc rien de lui-même sur cette disposition. La correction à la touche fonctionne toujours.",
            .de: "macOS hat kein Wörterbuch für \(layouts), deshalb entscheidet Helm auf dieser Belegung nichts von selbst. Die Korrektur per Taste funktioniert weiterhin.",
            .pt: "O macOS não tem dicionário para \(layouts), então o Helm não decide sozinho nesse leiaute. A correção pela tecla continua funcionando.",
            .ja: "macOS には \(layouts) の辞書がないため、Helm はこのレイアウトで自分から判断しません。キーによる修正は使えます。",
            .zh: "macOS 没有 \(layouts) 的词典，所以 Helm 不会在该布局上自行判断。按键修正仍然可用。",
        ]
        let english = "macOS has no dictionary for \(layouts), so Helm decides nothing by itself on that layout. Fixing with the key still works."
        return language == .en ? english : table[language] ?? english
    }

    /// What a VoiceOver reader hears when a word is rewritten in the app they
    /// are typing in. The words themselves are in it — an announcement is
    /// spoken and gone, the one channel with the same lifetime as the memory
    /// the module keeps them in. The undo tail rides only when an undo gesture
    /// actually exists. Interpolated, so it keeps its own table.
    /// The last change, read rather than seen.
    ///
    /// The row is two words and an arrow. Uncombined it gave a reader three
    /// unrelated stops with nothing saying one replaced the other; combined it
    /// needs a sentence, and the arrow is hidden so it is not read as a glyph.
    /// The wording is `fixedAnnouncement`'s minus its undo tail — that one is
    /// said when the change *happens*, this one when the row is read afterwards.
    ///
    /// Interpolated, so it keeps its own table.
    static func pairRead(before: String, after: String,
                         language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "Исправлено: \(before) → \(after)",
            .es: "Corregido: \(before) → \(after)",
            .fr: "Corrigé\u{00A0}: \(before) → \(after)",
            .de: "Korrigiert: \(before) → \(after)",
            .pt: "Corrigido: \(before) → \(after)",
            .ja: "修正しました：\(before) → \(after)",
            .zh: "已修正：\(before) → \(after)",
        ]
        return table[language] ?? "Fixed: \(before) → \(after)"
    }

    /// What the fourteen bars come to, for a reader who cannot see them.
    ///
    /// The chart carried `fortnight` — «Last fourteen days» — and no numbers at
    /// all, which is the tall tile's whole reason for being read out as a span
    /// with nothing in it. Both figures, because the total answers «is this
    /// worth anything» and today's answers «is it still happening».
    ///
    /// Interpolated, so it keeps its own table.
    static func fortnightSummary(total: Int, today: Int,
                                 language: AppLanguage = AppLanguage.current) -> String {
        // `wordsPutRight` is the noun phrase alone — «слов исправлено», not
        // «37 слов исправлено» — so the figure is spelled here. Caught by
        // the guard, in all eight languages at once.
        let words = "\(total) " + wordsPutRight(count: total, language: language)
        let table: [AppLanguage: String] = [
            .ru: "Последние четырнадцать дней: \(words), сегодня — \(today)",
            .es: "Últimos catorce días: \(words), hoy \(today)",
            .fr: "Quatorze derniers jours\u{00A0}: \(words), aujourd\u{2019}hui \(today)",
            .de: "Letzte vierzehn Tage: \(words), heute \(today)",
            .pt: "Últimos catorze dias: \(words), hoje \(today)",
            .ja: "過去14日間：\(words)、本日 \(today)",
            .zh: "过去十四天：\(words)，今天 \(today)",
        ]
        return table[language] ?? "Last fourteen days: \(words), \(today) today"
    }

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
