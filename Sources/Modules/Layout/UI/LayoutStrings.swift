import HelmRuntime
import HelmUI
import Module_Layout_Engine

enum LyStr {
    /// Broader than "layout" on purpose: the module id stays `layout`, but the
    /// name has room for whatever else belongs to the keyboard later.
    static var moduleName: String { L(.keyboard) }
    static var summary: String { L(.fixesWordsTypedInTheWrongKeyboardLayout) }
    static var automatic: String { L(.fixAsIType) }
    /// The rule, said once. «In the other layout» names the thing itself.
    static var automaticNote: String { L(.onlyWhenWhatYouTypedIs) }
    static var suspended: String { L(.pausedAPasswordFieldIsIn) }
    static var exceptions: String { L(.wordsToLeaveAlone) }
    /// What the list does, not how it is typed into: the shape is visible and
    /// the rule is not.
    static var exceptionsHint: String {
        L(.theseAreLeftExactlyAsYou)
    }
    static var ruleOn: String { L(.fix) }
    static var ruleOff: String { L(.dontFix) }
    /// The layout picker's «leave it alone» value, and the first one offered.
    /// Not «Off»: the row's other picker already uses that shape for a
    /// different question, and this one names what does not happen.
    static var layoutUnchanged: String { L(.asTheSystemHasIt) }

    /// The picker's own name, which a reader with VoiceOver hears in place of
    /// «pop-up button». Its *value* is the layout's own name, from the system.
    static var appLayout: String { L(.layout) }
    /// The system's own term, read from `KeyboardSettings.appex`'s loctable
    /// (key `Keyboard Shortcuts`) rather than shortened: «Сочетания клавиш», not
    /// the colloquial «Горячие клавиши». Bare «Shortcuts» is what five of the
    /// seven translations call the Shortcuts app: `Kurzbefehle`, `Raccourcis`,
    /// `Atajos`, `Atalhos`, `ショートカット`.
    static var shortcuts: String { HelmWord.keyboardShortcuts }
    static var apps: String { L(.rulesForSpecificApps) }
    /// One caption for the list, and it explains the rows above it, which draw
    /// the apps left alone, rather than describing a rule the page keeps
    /// invisible.
    static var appsWhy: String {
        L(.terminalsAndPasswordManagersStartSwitched)
    }
    static var lastChange: String { L(.lastChange) }

    /// The tile's estimate, without the period on the end: the caption above it
    /// already carries the period, and saying it twice on a 280 pt tile reads as
    /// two different spans. The hero names the period in the same caption line,
    /// through `wordsIn(_:count:)`. Takes a language rather than reading
    /// `AppLanguage.current`, so a guard can ask it about German
    /// (Architecture/Localization.md § Catalogs and the words kept in Swift).
    static func notSpentTypingAgain(language: AppLanguage = AppLanguage.current) -> String {
        L(.notSpentTypingAgain, language: language)
    }

    /// «≈ 3 min not spent typing again» for a period's figures; nil when nothing was put right or
    /// the estimate spells to nothing — one string for the hero's caption and the tile.
    static func timeSaved(_ figures: LedgerFigures) -> String? {
        guard figures.words > 0 else { return nil }
        let spelled = HelmDuration.string(TimeSaved.seconds(words: figures.words,
                                                            characters: figures.characters))
        guard !spelled.isEmpty else { return nil }
        return "≈ " + spelled + " " + notSpentTypingAgain()
    }


    /// Without the grant the typing half can do nothing at all, so the page
    /// says that instead of drawing every setting under a banner. Not «every
    /// setting»: the language indicator reads the input source through TIS,
    /// works without the grant, and is drawn below this message.
    static var deniedTitle: String { L(.helmIsNotWatchingTheKeyboard) }

    /// The hero's own words without the grant. Short, because the hero is a
    /// figure and not a paragraph — the long sentence lives once, under it.
    ///
    /// «Not watching», not «Not running»: the module is running and the tap is
    /// not, and the window header already says «Not active» in its own words.
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
    /// No route at the end: a string naming a way to somewhere goes on naming
    /// it, in eight languages, after the way moves.
    static var introWhere: String { L(.neverInAPasswordFieldAnd) }
    // MARK: - The tour

    /// The button on the row headed `tourTitle`. A row names, a button acts:
    /// spelling both with `tourTitle` would draw «How it works [How it works]».
    static var showTour: String { HelmWord.show }

    static var tourTitle: String { L(.howItWorks) }
    /// «2 of 4». Its own catalog key, because Japanese and Chinese do not say it as a fraction: `%@ / %@` and `第%@步，共%@步`.
    static func tourStep(_ index: Int, of total: Int,
                         language: AppLanguage = AppLanguage.current) -> String {
        L(.tourStep(String(index), String(total)), language: language)
    }
    static var tourWhatTitle: String { L(.whatItDoes) }
    static var tourSwitchesTitle: String { L(.whatYouCanSwitchOn) }
    static var introStart: String { L(.gotIt) }
    /// The note names the condition the engine checks (the dictionary), not a
    /// list of refusals that would make abbreviations look safe. The example is
    /// Latin, an alphabet every reader types in.
    ///
    /// The name says what the switch does, not its cause (a Shift held a beat
    /// too long). The Russian avoids the root of macOS's Sticky Keys
    /// («Залипание клавиш»), a feature that does something else.
    static var fixCapitals: String { L(.fixTwoCapitalsAtTheStart) }
    static var fixCapitalsNote: String { L(.helloHelloButOnlyWhenThe) }
    static var tryIt: String { L(.tryIt) }
    static var tryItPlaceholder: String { L(.typeGhbdtnAndPressSpace) }
    /// One idea in one string, not repeated by the step above and the
    /// placeholder. The Russian says «Клавиатура», the page's name, not
    /// «модуль».
    static var tryItHint: String { L(.helmWorksInThisFieldExactly) }
    static var indicator: String { L(.languageIndicator) }
    static var indicatorShow: String { L(.showItInTheMenuBar) }
    static var indicatorHint: String { L(.macosShowsAnIndicatorOfIts) }
    static var tapKey: String { L(.fixWith) }
    /// «Select it again to change it back», not «tapping again puts it back»:
    /// a fixed selection leaves no undo record (the caret's landing place
    /// after a selection replace is the app's business, so a blind reverse
    /// edit could eat text).
    ///
    /// One line under the row: what the row does. «What happens if I do» is
    /// behind the ⓘ (`HelmExplainer`).
    static var tapKeyHint: String { L(.tapItOnItsOwnIt) }

    /// The one value that means the control does nothing, said as such.
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
        // Not the system's «Show Input Source Name», though it draws the same
        // thing: that is macOS's name for a switch, and here it is the value of
        // a «Style» picker, where an instruction would sit in a noun's place.
        case .sourceName: return L(.layoutName)
        }
    }
    static var badgePreview: String { L(.yourLayoutsAsTheyWillLook) }
    static var flagNote: String { L(.aLayoutThatNamesNoCountry) }
    /// The system's own spelling of its input menu's last item, read from
    /// `TextInputMenuCore.bundle` (key `Open Keyboard Settings`) rather than
    /// translated again — German keeps the table's no-break space before the
    /// ellipsis.
    static var openKeyboardSettings: String { L(.openKeyboardSettings) }
    /// The emoji door's full title, built the way the system input menu builds
    /// it: the `Show palette class IM` template (`TextInputMenuCore.bundle`)
    /// around the palette's own name — so the sentence cannot drift from the
    /// palette it opens, the same construction as `VPNStr.secretNeedsAPress`.
    /// Interpolated, so the template is a catalog key.
    static func showEmojiPanel(language: AppLanguage = AppLanguage.current) -> String {
        L(.showEmojiPanel(L(.emojiAndSymbols, language: language)), language: language)
    }
    /// The window's own title. Not «Settings» and not the module's name — the
    /// window holds two lists and says so, because a window titled «Keyboard»
    /// beside a settings window titled «Keyboard» is two of one thing.
    static var listsWindowTitle: String { L(.wordsAndApps) }
    /// The rows on the page that open the window, each carrying its own count
    /// so the page answers «how many» without it being opened: a word can land
    /// there from «Never this word» somewhere else.
    ///
    /// The counted nouns come from `Plural`, which already declines them in all
    /// eight languages; the empty case is its own sentence, because «0 words»
    /// is a count where «none» is a state.
    static func exceptionsRow(_ count: Int,
                              language: AppLanguage = AppLanguage.current) -> String {
        guard count > 0 else { return L(.noWordsYet, language: language) }
        let figure = String(count)
        switch Plural.form(count, language: language.rawValue) {
        case .one: return L(.exceptionsRowOne(figure), language: language)
        case .few: return L(.exceptionsRowFew(figure), language: language)
        case .many: return L(.exceptionsRowMany(figure), language: language)
        }
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
    static var addException: String { L(.add) }
    static var audible: String { L(.playASoundWhenAWord) }
    /// Built from the current binding, never spelled by hand — the same
    /// construction as `VPNStr.secretNeedsAPress`, so the sentence cannot
    /// drift from the control it names. `gesture` is the tap key's name or
    /// the recorded chord's label; «press» covers both where «tap» does not.
    /// Interpolated: a catalog key, the argument a `%@`.
    static func undoHint(gesture: String, language: AppLanguage = AppLanguage.current) -> String {
        L(.undoHint(gesture), language: language)
    }
    /// No tap key and no chord means no undo exists, so the line says that
    /// rather than describing a gesture that cannot fire.
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
    /// The Russian declines the participle with the noun: «слова исправлены»
    /// for 2, 3 and 4, the bucket a light user sees most.
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
    /// The period belongs to whichever element can change it (the 2×N tile's
    /// pop-up), and where nothing can (1×1, 2×1) to the caption, so one word
    /// is not drawn twice. Both spellings come from here so they cannot drift.
    static func wordsPutRight(count: Int,
                              language: AppLanguage = AppLanguage.current) -> String {
        switch Plural.form(count, language: language.rawValue) {
        case .one: return L(.wordsPutRightOne, language: language)
        case .few: return L(.wordsPutRightFew, language: language)
        case .many: return L(.wordsPutRightMany, language: language)
        }
    }



    /// The hero when nothing has been put right yet: the state a fresh install
    /// sees.
    static var nothingYet: String { L(.watchingYourWords) }
    static var nothingYetNote: String { L(.nothingHasNeededPuttingRightSo) }


    /// Under the same card when macOS has no dictionary for a layout somebody
    /// has installed.
    ///
    /// It says what still works. The gesture asks no dictionary
    /// (`LayoutVerdict.decideForced` skips it by design), so this is «Helm
    /// cannot decide for itself here», not «this does not work here».
    ///
    /// Interpolated: a catalog key, the layouts a `%@`. The names come from
    /// `InputSourceInfo`, which is macOS's own name for the layout — the same
    /// rule as the pane names: read the system's spelling rather than invent
    /// one.
    static func noDictionary(layouts: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        L(.noDictionary(layouts), language: language)
    }

    /// The last change, read rather than seen.
    ///
    /// No arrow: `ConversionPair` hides the glyph from VoiceOver, and the label
    /// carries the words on both sides, in the caption's noun for the event.
    ///
    /// Interpolated: a catalog key, the argument a `%@`. Not remembered by `L`: the pair is typed
    /// text, and the engine forgets it with `forgetTheWord`.
    static func pairRead(before: String, after: String,
                         language: AppLanguage = AppLanguage.current) -> String {
        L(.pairRead(before, after), language: language, remembered: false)
    }

    /// The fortnight's total, spelled as each language spells a counted noun.
    ///
    /// Japanese and Chinese attach the numeral to the counter with no space
    /// (`37語を修正`), as `exceptionsRow` and `Plural.apps` do; Russian leads
    /// with the participle, as spoken Russian does; and the figure goes through
    /// `Count`, so Russian and French write `1 234`.
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
    /// Both figures, because the total answers «is this worth anything» and
    /// today's answers «is it still happening».
    ///
    /// Interpolated: a catalog key, the argument a `%@`.
    static func fortnightSummary(total: Int, today: Int,
                                 language: AppLanguage = AppLanguage.current) -> String {
        L(.fortnightSummary(wordsCounted(total, language: language), Count(today, language: language)),
          language: language)
    }

    /// What a VoiceOver reader hears when a word is rewritten in the app they
    /// are typing in. The words themselves are in it — an announcement is
    /// spoken and gone, so it is not remembered by `L` either: nothing outlives the engine's
    /// own forgetting. The undo tail rides only when an undo gesture
    /// actually exists. Interpolated: a catalog key, the arguments `%@`.
    static func fixedAnnouncement(before: String, after: String, undoable: Bool,
                                  language: AppLanguage = AppLanguage.current) -> String {
        let head = L(.fixedAnnouncement(before, after), language: language, remembered: false)
        guard undoable else { return head }
        return sentences(head, L(.fixedAnnouncementUndo, language: language), language: language)
    }

    /// Two sentences joined the way the language joins them: the CJK pair runs
    /// on after its full stop, the others take a space.
    private static func sentences(_ head: String, _ tail: String,
                                  language: AppLanguage) -> String {
        head + (language == .ja || language == .zh ? "" : " ") + tail
    }
}
