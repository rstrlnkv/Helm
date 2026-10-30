// Every inline table is wrapped, one language per line; the English key, which is
// never split, is one line.

import HelmRuntime
import HelmUI
import Module_Layout_Engine

enum LyStr {
    /// Broader than "layout" on purpose: the module id stays `layout`, but the
    /// name has room for whatever else belongs to the keyboard later.
    static var moduleName: String { L(.keyboard) }
    static var summary: String { L(.fixesWordsTypedInTheWrongKeyboardLayout) }
    static var automatic: String { L(.fixAsIType) }
    /// The rule, said once. `introWhen` said it again as step 1's second point —
    /// sixteen translated rows for one sentence, both of them drawn inside one
    /// three-step tour. «Once swapped» was also opaque (swapped what?) where «in
    /// the other layout» is the thing itself.
    static var automaticNote: String { L(.onlyWhenWhatYouTypedIs) }
    static var suspended: String { L(.pausedAPasswordFieldIsIn) }
    static var exceptions: String { L(.wordsToLeaveAlone) }
    /// **It said «One per line.» until the list stopped being lines.** That was
    /// a description of a `TextEditor` — true of the control, and the control is
    /// gone. A note under a list is the place to say what the list *does*, not
    /// how it is typed into: the shape is visible and the rule is not.
    static var exceptionsHint: String {
        L(.theseAreLeftExactlyAsYou)
    }
    static var addApp: String { L("Add app…") }
    static var ruleOn: String { L(.fix) }
    static var ruleOff: String { L(.dontFix) }
    /// The layout picker's «leave it alone» value, and the first one offered.
    /// Not «Off»: the row's other picker already uses that shape for a
    /// different question, and this one names what does not happen.
    static var layoutUnchanged: String { L(.asTheSystemHasIt) }

    /// The picker's own name, which a reader with VoiceOver hears in place of
    /// «pop-up button». Its *value* is the layout's own name, from the system.
    static var appLayout: String { L(.layout) }
    /// «Сочетания клавиш» is what macOS calls these — 12 tables to 0 for
    /// `Keyboard shortcut`, and 2 to 0 for the plural. «Горячие клавиши» is a
    /// colloquialism the system never uses, and this file already said the
    /// right thing thirty lines down (`orShortcut`). One name per thing.
    /// The system's own term, read from `KeyboardSettings.appex`'s loctable
    /// (key `Keyboard Shortcuts`) rather than shortened. Bare «Shortcuts» is
    /// what five of the seven translations call the *Shortcuts app*:
    /// `Kurzbefehle`, `Raccourcis`, `Atajos`, `Atalhos`, `ショートカット`.
    /// Russian was already right, because in Russian the compound is the
    /// ordinary name — which is why one English key fixes all five.
    static var shortcuts: String { L("Keyboard shortcuts") }
    static var apps: String { L(.rulesForSpecificApps) }
    /// One caption for the list, and it explains the rows above it rather than
    /// describing a rule the page keeps invisible.
    ///
    /// It replaces two: an empty state saying «a few terminals and password
    /// managers are left alone already» and a footer saying almost the same
    /// thing, neither of which named one of them. The apps are drawn now.
    static var appsWhy: String {
        L(.terminalsAndPasswordManagersStartSwitched)
    }
    static var lastChange: String { L(.lastChange) }

    /// The tile's estimate, without the period on the end: the caption above it
    /// already carries the period, and saying it twice on a 280 pt tile reads as
    /// two different spans. `timeIn(_:)` is the page's version, which has to carry
    /// it because the page has no caption above the figure. Takes a language rather
    /// than reading `AppLanguage.current`, so a guard can ask it about German. This
    /// machine runs in Russian, so a test that reads `.current` exercises exactly
    /// one of eight — CLAUDE.md § What not to do, and what breaks if you do.
    static func notSpentTypingAgain(language: AppLanguage = AppLanguage.current) -> String {
        L(.notSpentTypingAgain, language: language)
    }


    /// Without the grant the *typing* half can do nothing at all, so the page
    /// says that instead of drawing every setting under a banner. Not «every
    /// setting»: the language indicator reads the input source through TIS and
    /// works without the grant — the page draws it below this message, and a
    /// message claiming otherwise called its own neighbour a lie.
    static var deniedTitle: String { L(.helmIsNotWatchingTheKeyboard) }

    /// The hero's own words without the grant. Short, because the hero is a
    /// figure and not a paragraph — the long sentence lives once, under it.
    ///
    /// **«Not watching», not «Not running».** The module is running; the tap is
    /// not. And the window header already says «Not active» in its own words,
    /// so a third spelling of the same fact on one screen is what this avoids.
    static var heroNotWatching: String { L(.notWatching) }
    static var heroNotWatchingWhy: String { L(.macosIsNotDeliveringKeystrokesTo) }

    /// What the empty state is for once the hero has said the rest: the two
    /// things somebody weighing this permission actually wants to know.
    static var deniedGuarantee: String {
        L(.helmNeverReadsAPasswordA)
    }
    static var indicatorWorksAnyway: String {
        L(.theLanguageIndicatorBelowWorksWithout)
    }

    static var introWhat: String { L(.typeGhbdtnInTheWrongLayout) }
    /// **No route at the end.** It said «add any others in Settings» — from
    /// inside Settings, about a list that lives in the «Words and apps» window
    /// now. The 0.9.0 «Configure panel» failure: a string naming a way to
    /// somewhere, translated faithfully into seven languages after the way
    /// moved.
    static var introWhere: String { L(.neverInAPasswordFieldAnd) }
    // The two faces of one control, so a reader who opened the points can put
    // them away again — a disclosure that only opens is a disclosure that has
    // stopped being one.
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

    static var tourTitle: String { L(.howItWorks) }
    static var tourBack: String { L("Back") }
    static var tourNext: String { L("Next") }
    /// «2 of 4». Interpolated, so it keeps its own table.
    static func tourStep(_ index: Int, of total: Int,
                         language: AppLanguage = AppLanguage.current) -> String {
        L("\(index) of \(total)",
          [.ru: "\(index) из \(total)",
           .es: "\(index) de \(total)",
           .fr: "\(index) sur \(total)",
           .de: "\(index) von \(total)",
           .pt: "\(index) de \(total)",
           // `\(total)分の\(index)` is the *fraction* — «one quarter» —
           // and not a step counter at all.
           .ja: "\(index) / \(total)",
           .zh: "第\(index)步，共\(total)步"],
          language: language)
    }
    static var tourWhatTitle: String { L(.whatItDoes) }
    static var tourSwitchesTitle: String { L(.whatYouCanSwitchOn) }
    static var introStart: String { L(.gotIt) }
    /// **The example is Latin now, and the note says what the rule does.**
    /// The old one listed three refusals — never shouting, never a digit, never
    /// three letters — from which the only available conclusion was that
    /// abbreviations were safe. They were not: `IPhone`, `IPad`, `OSes`,
    /// `ТВшник` were all rewritten, measured by running the rule. The engine
    /// asks the dictionary now, so the note can name the condition instead of
    /// the exceptions. The example was also Cyrillic in the English, Japanese
    /// and Chinese rows — a slip demonstrated in an alphabet those readers are
    /// not typing in.
    ///
    /// **The English was the wrong half of the pair.** It named a cause — a
    /// Shift held a beat too long — where ja and zh had both already named the
    /// rule, which is what the switch actually does. The translators were right
    /// and the key was wrong, so it is one fix rather than seven. The Russian
    /// also borrowed the root of macOS's Sticky Keys («Залипание клавиш»), a
    /// feature that does something else entirely.
    static var fixCapitals: String { L(.fixTwoCapitalsAtTheStart) }
    static var fixCapitalsNote: String { L(.helloHelloButOnlyWhenThe) }
    static var tryIt: String { L(.tryIt) }
    static var tryItPlaceholder: String { L(.typeGhbdtnAndPressSpace) }
    /// **Seventeen words doing one job through a colon.** The step above it
    /// said «not a demonstration» too, and so did the placeholder — one idea
    /// across four strings and 32 translated rows. The Russian also leaked the
    /// word «модуль» onto a page the reader knows as «Клавиатура».
    static var tryItHint: String { L(.helmWorksInThisFieldExactly) }
    static var indicator: String { L(.languageIndicator) }
    static var indicatorShow: String { L(.showItInTheMenuBar) }
    static var indicatorHint: String { L(.macosShowsAnIndicatorOfIts) }
    static var tapKey: String { L(.fixWith) }
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
    static var tapKeyHint: String { L(.tapItOnItsOwnIt) }

    /// The one value that means the control does nothing, which the note used
    /// to describe as if it did.
    static var tapKeyOff: String {
        L(.nothingFixesTheSelectionOrThe)
    }

    /// Behind the ⓘ beside «Fix with». Assembled from the key in force, so a
    /// key with nothing special about it opens two blocks and no warnings.
    static func tapKeyExplainer(_ key: TapKey) -> HelmExplainer.Content? {
        guard key != .off else { return nil }
        var blocks: [HelmExplainer.Block] = [
            .text(L(.tapAgainToPutTheChange)),
            .text(L(.heldDownOrPressedTogetherWith)),
        ]
        if key == .globe { blocks.append(.text(globeNote)) }
        if key.isFrequentlyUsed { blocks.append(.text(leftKeyNote)) }
        if key == .leftControl || key == .rightControl { blocks.append(.text(controlKeyNote)) }
        return HelmExplainer.Content(title: tapKey, blocks: blocks)
    }

    /// Shown for either Control. A solo Control tap is VoiceOver's own
    /// «pause speech» gesture, so for a VoiceOver user this binding fires
    /// both at once.
    static var controlKeyNote: String { L(.tappingControlOnItsOwnAlso) }

    /// Shown only when 🌐︎ is chosen. macOS may already have that key doing
    /// something, and Helm cannot make it stop — the setting is the person's.
    static var globeNote: String { L(.macosMayAlreadyUseToSwitch) }

    /// Shown when a left-hand key is chosen. Not a warning against it — it is
    /// their keyboard — but the trade should be visible at the moment it is
    /// made, not discovered later.
    static var leftKeyNote: String { L(.thisIsAKeyYouType) }

    /// The one chord, for keyboards with no right-hand modifier to tap.
    static var orShortcut: String { L(.orAKeyCombination) }
    static func tapKeyName(_ key: TapKey) -> String {
        switch key {
        case .off: return L(.noKey)
        case .rightCommand: return L(.rightCommand)
        case .rightOption: return L(.rightOption)
        case .rightControl: return L(.rightControl)
        case .rightShift: return L(.rightShift)
        case .leftCommand: return L(.leftCommand)
        case .leftOption: return L(.leftOption)
        case .leftControl: return L(.leftControl)
        case .leftShift: return L(.leftShift)
        case .globe: return L(.globe)
        }
    }
    static var badgeStyle: String { L(.style) }
    static func badgeStyleName(_ style: BadgeStyle) -> String {
        switch style {
        case .plain: return L(.letters)
        case .filled: return L(.lettersOnAFilledBadge)
        case .outlined: return L(.lettersInAFrame)
        case .flagDrawn: return L(.flag)
        // **Not the system's «Show Input Source Name», though it draws the same
        // thing.** That is macOS's name for a *switch*, and here it is the value
        // of a «Style» picker, so the row read «Вид: Показывать имя источника
        // ввода» — an instruction sitting where a noun belongs. The rule about
        // reading the system's spelling covers a thing macOS also names; macOS
        // names the switch, not the style, and this is the style.
        case .sourceName: return L(.layoutName)
        }
    }
    static var badgePreview: String { L(.yourLayoutsAsTheyWillLook) }
    static var flagNote: String { L(.aLayoutThatNamesNoCountry) }
    /// The system's own spelling of its input menu's last item, read from
    /// `TextInputMenuCore.bundle` (key `Open Keyboard Settings`) rather than
    /// translated again — German keeps the table's no-break space before the
    /// ellipsis. This key used to be «Open Keyboard settings…», a near-copy
    /// with four of eight rows retranslated by hand.
    static var openKeyboardSettings: String { L(.openKeyboardSettings) }
    /// The emoji door's full title, built the way the system input menu builds
    /// it: the `Show palette class IM` template (`TextInputMenuCore.bundle`)
    /// around the palette's own name — so the sentence cannot drift from the
    /// palette it opens, the same construction as `VPNStr.secretNeedsAPress`.
    /// Interpolated, so the template keeps its own table.
    static func showEmojiPanel(language: AppLanguage = AppLanguage.current) -> String {
        let name = L(.emojiAndSymbols, language: language)
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
    /// The window's own title. Not «Settings» and not the module's name — the
    /// window holds two lists and says so, because a window titled «Keyboard»
    /// beside a settings window titled «Keyboard» is two of one thing.
    static var listsWindowTitle: String { L(.wordsAndApps) }
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
        guard count > 0 else { return L(.noWordsYet, language: language) }
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
        guard count > 0 else { return L(.everyAppButTheOnesHelm, language: language) }
        return Plural.apps(count, language: language.rawValue)
    }

    static var neverThisWord: String { L(.neverThisWord) }
    static var noExceptions: String { L(.noWordsYet) }
    /// The field's placeholder and its VoiceOver name at once — a placeholder
    /// disappears the moment there is a value to read, so it cannot be the only
    /// thing naming the field.
    static var exceptionPrompt: String { L(.aWordToLeaveAlone) }
    static var addException: String { L("Add") }
    static var audible: String { L(.playASoundWhenAWord) }
    /// Built from the current binding, never spelled by hand — the same
    /// construction as `VPNStr.secretNeedsAPress`, so the sentence cannot
    /// drift from the control it names. `gesture` is the tap key's name or
    /// the recorded chord's label; «press» covers both where «tap» does not.
    /// Interpolated, so it keeps its own table.
    static func undoHint(gesture: String, language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "Отменяется повторным нажатием «\(gesture)» — до того, как набрано что-то еще, в том приложении, где это произошло.",
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
        L(.noKeyIsAssignedThisChange, language: language)
    }
    /// The row's own label when the change it names was taken back: the record
    /// outlives the rejection (that is when «Never this word» earns its keep),
    /// and it must say which state it is in.
    static var lastChangeUndone: String { L(.lastChangeUndone) }
    /// A period's name, on the hero's five buttons and the panel tile's period menu. Words, not glyphs: «7 дней» and
    /// «Всё время» are not a picture anybody would recognise.
    static func periodName(_ period: ConversionPeriod,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch period {
        case .today: return L(.today, language: language)
        case .week: return L(.week, language: language)
        case .month: return L(.month, language: language)
        case .year: return L(.year, language: language)
        case .allTime: return L(.allTime, language: language)
        }
    }

    static var period: String { L(.period) }


    /// Under the figure when it is showing words: how many, and over what.
    ///
    /// The Russian declines the participle with the noun. «слова исправлено» —
    /// a plural noun under a neuter singular short participle — was wrong for
    /// counts of 2, 3 and 4, which is the bucket a light user sees most.
    static func wordsIn(_ period: ConversionPeriod, count: Int,
                        language: AppLanguage = AppLanguage.current) -> String {
        // German keeps the period name's capital; the other languages write it in lower case.
        let name = periodName(period, language: language)
        return wordsPutRight(count: count, language: language)
            + " · " + (language == .de ? name : name.lowercased())
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
    static var nothingYet: String { L(.watchingYourWords) }
    static var nothingYetNote: String { L(.nothingHasNeededPuttingRightSo) }


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
            .ru: "macOS не дает словаря для \(layouts), поэтому сам Helm на этой раскладке ничего не решает. Исправление клавишей работает.",
            .es: "macOS no tiene diccionario para \(layouts), así que Helm no decide por su cuenta en esa distribución. La corrección con la tecla sigue funcionando.",
            .fr: "macOS ne fournit pas de dictionnaire pour \(layouts)\u{00A0}: Helm ne décide donc rien de lui-même sur cette disposition. La correction à la touche fonctionne toujours.",
            .de: "macOS hat kein Wörterbuch für \(layouts), deshalb entscheidet Helm auf dieser Belegung nichts von selbst. Die Korrektur per Taste funktioniert weiterhin.",
            .pt: "O macOS não tem dicionário para \(layouts), então o Helm não decide sozinho nesse leiaute. A correção pela tecla continua funcionando.",
            .ja: "macOS には \(layouts) の辞書がないため、Helm はこのレイアウトで自分から判断しません。キーによる修正は使えます。",
            .zh: "macOS 没有 \(layouts) 的词典，所以 Helm 不会在该布局上自行判断。按键修正仍然可用。",
        ]
        let english = "macOS has no dictionary for \(layouts), so Helm decides nothing by itself on that layout. Fixing with the key still works."
        return language == .en ? english : table[language] ?? english
    }

    /// The last change, read rather than seen.
    ///
    /// **No arrow.** `ConversionPair` hides the glyph from VoiceOver saying
    /// «the arrow's job is done by the word in the label» — and the label put
    /// the same `→` straight back, so a reader heard it from the one place it
    /// had just been taken out of. Words on both sides now, which also ends a
    /// second mismatch: the caption above says «Последняя замена» and this said
    /// «Исправлено», two nouns for one event two stops apart.
    ///
    /// Interpolated, so it keeps its own table.
    static func pairRead(before: String, after: String,
                         language: AppLanguage = AppLanguage.current) -> String {
        let table: [AppLanguage: String] = [
            .ru: "Было \(before), стало \(after)",
            .es: "Antes \(before), ahora \(after)",
            .fr: "Avant \(before), maintenant \(after)",
            .de: "Vorher \(before), jetzt \(after)",
            .pt: "Antes \(before), agora \(after)",
            .ja: "\(before) を \(after) に修正しました",
            .zh: "已将 \(before) 修正为 \(after)",
        ]
        return table[language] ?? "Was \(before), now \(after)"
    }

    /// The fortnight's total, spelled as each language spells a counted noun.
    ///
    /// **Three defects in one line, and the module already knew all three.**
    /// `wordsPutRight` returns the noun phrase without its figure, so the
    /// figure was glued on with `"\(total) "` — which put a space before the
    /// Japanese and Chinese counters (`37 語を修正`), where those languages
    /// attach the numeral; `exceptionsRow` twenty lines up and `Plural.apps` in
    /// `HelmRuntime` both guard exactly that. It also put the Russian
    /// participle last (`37 слов исправлено`), which is a table cell rather
    /// than a sentence — spoken Russian leads with it. And it spelled the
    /// number by hand, so a busy fortnight drew `1234` where Russian and French
    /// write `1 234`; `Count` exists for that and its own doc records the same
    /// defect found in a scan of `/`.
    static func wordsCounted(_ count: Int,
                             language: AppLanguage = AppLanguage.current) -> String {
        let figure = Count(count, language: language)
        switch language {
        case .ru:
            return "исправлено " + figure + " "
                + Plural.russian(count, "слово", "слова", "слов")
        case .ja: return figure + "語を修正"
        case .zh: return figure + "个词已修正"
        default: return figure + " " + wordsPutRight(count: count, language: language)
        }
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
        let words = wordsCounted(total, language: language)
        let now = Count(today, language: language)
        let table: [AppLanguage: String] = [
            .ru: "Последние четырнадцать дней: \(words), из них сегодня \(now)",
            .es: "Últimos catorce días: \(words), hoy \(now)",
            .fr: "Quatorze derniers jours\u{00A0}: \(words), aujourd\u{2019}hui \(now)",
            .de: "Letzte vierzehn Tage: \(words), heute \(now)",
            .pt: "Últimos catorze dias: \(words), hoje \(now)",
            .ja: "過去14日間：\(words)、本日 \(now)語",
            .zh: "过去十四天：\(words)，今天 \(now)个",
        ]
        return table[language] ?? "Last fourteen days: \(words), \(now) of them today"
    }

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
            .ru: "Отменяется повторным нажатием клавиши — до того, как набрано что-то еще.",
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
