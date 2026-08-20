import Foundation
import HelmUI
import HelmRuntime
import Module_KeepAwake_Engine

/// Localized strings for the Keep Awake module UI. English is the base; the
/// tables carry zh/es/fr/de/ja/ru/pt.
enum KAStr {
    static var moduleName: String {
        L("Keep Awake")
    }
    static var summary: String {
        L("Keep the Mac from falling asleep")
    }
    /// Window title: no ellipsis — that belongs to the menu entry that opens it.
    static var customTimeTitle: String { L("Custom duration") }
    /// The button that opens the free-form duration field.
    ///
    /// **Not «Timer».** That word is already this module's name for the running
    /// countdown — `KAStr.timer`, «Timer colour», «A timer pauses the rule too»
    /// — and the three buttons beside this one *are* timers, so naming only the
    /// fourth one that would say the other three are not. One word, two meanings
    /// on one screen, which is the collision the localization rule exists for.
    ///
    /// `Other…` is macOS's own label for exactly this control: a list of values
    /// and a way to enter one that is not on it. `TB_Other...` in Preview and
    /// `Other…` in Calendar read «Другое…», «Andere\u{00A0}…», «Autre…»,
    /// «Otro…», «その他…», «其他…» — read out of those bundles rather than
    /// translated again, including the German non-breaking space before the
    /// ellipsis, which is Apple's spelling in all three apps that carry it.
    static var customTime: String { L("Other…") }
    static var done: String { L("OK") }
    /// The state of the ⋯ disclosure, read after its name.
    ///
    /// Said in words because there is no other way to say it: SwiftUI's
    /// `AccessibilityTraits` has no expanded member on any platform, and AppKit's
    /// `NSAccessibilityExpanded` — which VoiceOver would voice in the user's own
    /// language — is not reachable from a SwiftUI view. So the button was a
    /// control whose entire purpose is showing and hiding a block, and read
    /// aloud it never said which of the two it had just done. These eight are
    /// the one set of strings in this file not taken from a system table:
    /// macOS does not ship these adjectives anywhere readable.
    static var disclosureExpanded: String {
        L("Expanded")
    }
    static var disclosureCollapsed: String {
        L("Collapsed")
    }
    /// Short forms used under the "Automatically" heading, where the context is
    /// already given by the group title.
    static var onExternalDisplay: String { L("With an external display") }
    static var onPower: String { L("On power") }
    /// Spanish says `Temporizador`, which is what macOS's own Clock says
    /// (Clock.app `Localizable.loctable`, key `TIMER`) and what this file
    /// already said two labels down — so one page carried both words. German
    /// and Brazilian Portuguese genuinely say `Timer` in the same table.
    static var timer: String { L("Timer") }
    static var start: String {
        L("Start")
    }
    static var stop: String {
        L("Stop")
    }
    /// Single-letter units for the narrow preset pills ("15 м", "1 ч").
    static var minutesUnitShort: String {
        L("m")
    }
    /// German abbreviates with a period — `2 Std.` — in CLDR and in ordinary
    /// orthography, and `hoursUnit` two lines down already had one, so the same
    /// duration was spelled two ways. Distinct from `minutesUnitShort` above,
    /// which is deliberately the full `Min.` because the pill was measured.
    static var hoursUnitShort: String {
        L("h")
    }
    static var hoursUnit: String {
        L("h")
    }
    static var minutesUnit: String {
        L("min")
    }

    /// "45 min" / "1 h" / "1 h 30 min" — minutes below an hour, hours above.
    /// `compact` uses the single-letter units, for the narrow preset pills.
    ///
    /// The panel tile owned this privately while the settings page composed
    /// "15 " + `minutesUnit` for the same duration one file away. The two hour
    /// presets in that picker keep their own keys and do **not** come from here:
    /// composed, they would read "1 ч" where Russian has «1 час» and "1 Std."
    /// where German has "1 Stunde" — the abbreviation is what a narrow pill
    /// needs, not what a settings row wants.
    static func duration(_ minutes: Int, compact: Bool = false) -> String {
        let mUnit = compact ? minutesUnitShort : minutesUnit
        let hUnit = compact ? hoursUnitShort : hoursUnit
        guard minutes >= 60 else { return "\(minutes)\u{00A0}\(mUnit)" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)\u{00A0}\(hUnit)" : "\(h)\u{00A0}\(hUnit) \(m)\u{00A0}\(mUnit)"
    }
    /// **The case, not its spelling.** This took the wire string and ended in
    /// `default: return wire` — so a condition this build did not know was
    /// drawn on screen as `externalDisplay`, in every language, and a renamed
    /// case would have shown its identifier to the person rather than failing
    /// anywhere. Over the enum the switch is exhaustive and a new case is a
    /// build error.
    static func condition(_ condition: ActiveCondition) -> String {
        switch condition {
        case .manual: return L("Manual")
        case .timer: return L("Timer")
        case .externalDisplay: return L("External display")
        case .power: return L("On power")
        case .app: return L("App")
        }
    }

    // MARK: - Settings

    static var automation: String { L("Automation") }
    /// The note under a rule that is doing its job, and under one that is not.
    ///
    /// The second is the state v3 exists to draw: switched on, and nothing
    /// happening. Without it a rule that never fires and a rule nobody switched
    /// on are the same row with the same silence under it.
    static var ruleApplies: String { L("Applies right now") }
    static var ruleWaiting: String { L("Not applying right now") }
    /// What a rule would do, said while it is still switched off.
    ///
    /// The row was a bare label until you turned it on — the notes only
    /// appeared afterwards, so the one moment a person needs to know what a
    /// rule means is the one moment the row said nothing.
    static func ruleMeaning(_ condition: ActiveCondition) -> String {
        switch condition {
        case .externalDisplay: return L("While an external display is connected")
        case .power: return L("While the Mac is on power")
        // Neither is a rule anybody switches on, so neither has a row here.
        case .manual, .timer, .app: return ""
        }
    }
    /// The whole note in one place, so the row's four states and the four cases
    /// that decide them are read from the same list.
    ///
    /// `.paused` deliberately re-uses `automationPaused` — the banner's own
    /// sentence. Two spellings of one fact was the defect; a second key here
    /// would have been a third. `.vetoed` re-uses the battery notice for the
    /// same reason, in its short form: the banner above the card carries the way
    /// out, and repeating it on every rule row would be the page saying «plug
    /// in» four times.
    static func ruleNote(_ note: RuleNote, _ condition: ActiveCondition,
                         batteryFloor: Int) -> String {
        switch note {
        case .meaning: return ruleMeaning(condition)
        case .applies: return ruleApplies
        case .waiting: return ruleWaiting
        case .paused: return automationPaused
        case .vetoed: return stoppedByBatteryShort(batteryFloor)
        }
    }
    /// The lid row's line, from the four states the machine can be in.
    ///
    /// Two of them are new and both are the same kind of silence the rest of this
    /// module has been spending the release closing: something was attempted, it
    /// did not work, and the row went on explaining what the password buys. See
    /// `LidRowNote`.
    static func lidNote(_ note: LidRowNote) -> String {
        switch note {
        case .refused: return lidRefused
        case .grantRemains: return lidGrantRemains
        case .sleepIsOff: return sleepIsOffNote
        case .whatItCosts: return adminNote
        }
    }
    /// The reason line under the figure: «External display · Safari».
    ///
    /// The composition lived in the hero, and the `.app` case answered «App» —
    /// the only rule type anybody actually uses, and the only one that could
    /// not say what it was about. A person with four apps in the list could not
    /// tell which was holding the Mac, on the screen whose whole job is to
    /// answer that.
    ///
    /// Names are resolved by the caller from the bundle ids the engine
    /// publishes; several apps read as a list, and none at all falls back to
    /// the generic word rather than leaving a gap.
    static func conditionsLine(_ conditions: Set<ActiveCondition>,
                               appNames: [String]) -> String {
        conditions.map { condition in
            guard condition == .app, !appNames.isEmpty else { return self.condition(condition) }
            return appNames.joined(separator: ", ")
        }
        .sorted()
        .joined(separator: " · ")
    }
    static var appsSection: String { L("Apps") }
    static func triggerCondition(_ condition: AppTrigger.Condition) -> String {
        switch condition {
        case .always: return L("Always")
        case .externalDisplay: return L("With an external display")
        case .power: return L("On power")
        case .displayAndPower: return L("Display and power")
        }
    }
    static var noAppsYet: String { L("No apps chosen") }
    /// A rules string in the file that nothing can read.
    ///
    /// The reader answers «no rules» for it, which fails in the safe direction —
    /// the Mac sleeps — and looks exactly like having chosen no apps at all. The
    /// engine wrote one line in the log at launch and that was the entire account
    /// of it: the apps somebody picked stopped holding the Mac awake, and this
    /// page went on looking perfectly well. Says what was lost and what follows
    /// from it, because the second half is what the person actually noticed.
    ///
    /// **And then what to do.** «Could not be read» is a passive report of a
    /// state, and the state is not recoverable by waiting: the string in the file
    /// is not going to become readable, and the only way back is to pick the apps
    /// again — which rewrites the key and takes the banner away with it. The
    /// English is the key and the meaning gained a verb, so this is a new key
    /// rather than eight corrections.
    static var appRulesUnreadable: String {
        L("Helm cannot read the saved app rules, so no app is keeping the Mac awake. Add the apps again")
    }
    /// What an app rule *is*, said where somebody would otherwise find out by
    /// trying. The section heading used to carry this job in its own tail —
    /// «Apps that keep the Mac awake» — which explained it again on every visit
    /// for ever, including to the people who already had a list.
    static var noAppsYetNote: String {
        L("Add an app and the Mac stays awake while it is running. You can limit a rule to power, to an external display, or to both.")
    }
    static var keepDisplayOn: String { L("Keep the display on") }
    static var movePointer: String { L("Move the pointer") }
    /// "Каждые 1 мин" is wrong, and the stepper starts at 1: the Russian
    /// quantifier agrees with the last digit, with the 11–14 exception
    /// `Plural.russian` already knows.
    static func everyMinutes(_ n: Int) -> String {
        // Every other language says "Every minute" rather than "Every 1 min",
        // and the stepper starts at one, so Russian was reading «Каждую 1 мин»
        // in the state the setting opens in.
        let ru = n == 1 ? "Каждую минуту"
                        : "Кажд" + Plural.russian(n, "ую", "ые", "ые") + " \(n) мин"
        return L(n == 1 ? "Every minute" : "Every \(n) min",
                 [.ru: ru,
                  .es: n == 1 ? "Cada minuto" : "Cada \(n) min",
                  .fr: n == 1 ? "Chaque minute" : "Toutes les \(n) min",
                  .de: n == 1 ? "Jede Minute" : "Alle \(n) Min.",
                  .ja: "\(n)分ごと", .zh: n == 1 ? "每分钟" : "每 \(n) 分钟",
                  .pt: n == 1 ? "A cada minuto" : "A cada \(n) min"])
    }
    static var defaultDuration: String { L("Default duration") }
    static var oneHour: String { L("1 hour") }
    static var twoHours: String { L("2 hours") }
    static var indefinite: String { L("Indefinite") }

    // MARK: - The hero
    //
    // The top of the page says what is happening and offers the verbs for it.
    // It was three metric cells reading «ВЫКЛ · — · 0» — two of the three
    // figures the unreadable kind this house does not draw at all — above
    // twenty controls and no way to begin or end a session at all.

    static var heroIdle: String { L("The Mac sleeps as usual") }
    /// Two different silences, and they want different sentences: nothing is
    /// switched on, and something is switched on but does not apply. The first
    /// is an invitation, the second is an explanation.
    static var heroNoRules: String { L("No rule is switched on") }
    static var heroIdleReason: String { L("No rule applies right now") }
    /// One figure for «awake», whatever is holding it, and the reason on the
    /// line below — which is what the countdown state already does.
    ///
    /// There were two sentences here, and they were not parallel: «A rule is
    /// holding the Mac» described the machinery, «Awake until you stop it»
    /// described a deadline, and the reader had to parse a new construction for
    /// each state of one screen. The figure answers one question — is this Mac
    /// going to sleep — and everything about *why* moved to where the timer
    /// already keeps it.
    static var heroAwake: String { L("The Mac is staying awake") }
    /// The reason line for a session with no deadline. «Until you stop it» is
    /// the whole answer, and it is the same shape as the conditions listed for
    /// a session a rule is holding.
    static var heroUntilYouStop: String { L("Until you stop it") }
    /// Said beside the button that does it, rather than left for the log.
    static var heroStopSuppresses: String {
        L("Stop pauses the rule until it applies again")
    }

    /// What VoiceOver says for the countdown, once, when asked.
    ///
    /// Interpolated, so it composes from a localized word rather than from a
    /// table of its own — the same shape `duration` uses. The figure on screen
    /// is `1:23:45` and is announced as it reads; the word in front is what
    /// makes it a duration rather than a time of day.
    static func a11yRemaining(_ label: String) -> String {
        "\(L("Time remaining")): \(label)"
    }
    /// «Таймер до 15:42» — the deadline as a clock, which is what a person
    /// checks against. `HelmDates.timeOfDay` writes it in the app's language,
    /// not the system's.
    static func timerUntil(_ end: Date) -> String {
        let time = HelmDates.timeOfDay(end)
        return L("Timer until \(time)",
                 [.ru: "Таймер до \(time)", .es: "Temporizador hasta las \(time)",
                  .fr: "Minuteur jusqu’à \(time)", .de: "Timer bis \(time)",
                  .ja: "\(time) までのタイマー", .zh: "计时至 \(time)",
                  .pt: "Temporizador até \(time)"])
    }
    /// The second half of that line: what is still holding the Mac when the
    /// countdown reaches zero.
    ///
    /// **Three whole sentences, not one sentence with a name dropped into it.**
    /// It composed «then \(name) keeps it awake» from the row label, and a row
    /// label is not a noun phrase a sentence can take: English got «then on
    /// power keeps it awake», German a capitalised noun with no article,
    /// French «ensuite c\u{2019}est écran externe qui le maintient». The
    /// interpolation is what made it ungrammatical in five languages at once —
    /// and interpolation is also what forced the inline tables. Written whole,
    /// each of the three lives in the `.strings` files with the rest.
    static func thenHeldBy(_ condition: ActiveCondition) -> String {
        switch condition {
        case .externalDisplay: return L("then the external display keeps the Mac awake")
        case .power: return L("then being on power keeps the Mac awake")
        case .app: return L("then the app keeps the Mac awake")
        // `SessionHero.holderAfterTimer` only ever answers one of the three
        // above; the switch is exhaustive so a fourth automatic condition is a
        // build error here rather than a sentence nobody wrote.
        case .manual, .timer: return ""
        }
    }
    /// The third answer at zero, and the one that was missing. With «A timer
    /// pauses the rule too» switched on the note stopped at «Timer until
    /// 16:03» — the one state where that setting decides anything was the one
    /// state nothing on the page mentioned it.
    static var thenRulePaused: String {
        L("then the rule is paused until it applies again")
    }
    static var pointerNeedsAccessibility: String { L("Needs Accessibility, or the pointer will not move") }
    /// Russian was the odd one out: «хоткей» is slang, and Helm's own Layout
    /// page already says «сочетание клавиш». macOS calls it «Сочетание клавиш»
    /// (KeyboardSettings.appex, key "Keyboard shortcut"), so that is the word.
    /// The other seven already carry their own system's root — de Kurzbefehl,
    /// es Atajo, fr Raccourci, zh 快捷键, ja ショートカット, pt Atalho — checked
    /// against the same table rather than assumed.
    static var globalShortcut: String { L("Global shortcut") }
    static var toggleAction: String { L("Toggle Keep Awake") }
    static var keepAwakeLidClosed: String { L("Stay awake with the lid closed") }
    /// Sleep is off, and **for the whole Mac** — the scope is the point.
    ///
    /// What the setting does is turn system sleep off machine-wide, through a
    /// sudoers rule that outlives this process: the one thing this module does
    /// that a person cannot see by looking at their menu bar. «Sleep is off right
    /// now» could be read as Keep Awake holding an assertion, which is what every
    /// other row on the page does and is nothing like this. So the new English
    /// says whose sleep — and a Mac whose sleep is off is a Mac that will not
    /// sleep in a bag, which is the fact worth spelling out.
    ///
    /// This is the panel's spelling of it, in the subtitle beside the switch. That
    /// subtitle is a fragment in a list joined with « · » inside a 320 pt card, so
    /// it takes the sentence and not the way out of it; the settings row, which
    /// has the width, takes `sleepIsOffNote` — the same sentence with the
    /// revocation clause after it. One wording, two lengths, and
    /// `testTheLidNoteOpensOnTheSentenceThePanelDraws` fails, in all eight, if the
    /// long form stops opening on the short one.
    ///
    /// It replaced `lidClosed` — «Lid closed — staying awake» — which named the
    /// lid in a list of what was holding the Mac. The lid is not what is holding
    /// it; the lid is the thing that is safe to close *because* sleep is off, and
    /// saying so was the half the panel never had.
    static var sleepIsOffNow: String { L("Sleep is off for the whole Mac right now") }
    /// The same fact where there is room for the way back out of it.
    ///
    /// A row that reports a system-wide setting has to say what un-does it, and
    /// this one is not obvious: nothing in `/etc/sudoers.d` is going to un-do
    /// itself, and the control that takes it back is the switch on this very row.
    /// Without the second clause the row stated a permanent-sounding change to
    /// somebody's Mac and left them looking for a way out of it.
    ///
    /// **«Brings it back» lost its antecedent in four of the eight.** The clause
    /// names two things a pronoun could point at — the setting and the Mac's
    /// sleep — and in ru, es, de and pt the two have different genders, so the
    /// translations had to pick one and half of them picked the setting. The
    /// English says which noun comes back, and `adminNote` two states over
    /// already had the verb for it.
    static var sleepIsOffNote: String {
        L("Sleep is off for the whole Mac right now. Switching this off turns sleep back on")
    }
    /// macOS said no.
    ///
    /// `reallyEngage` reads `setDisableSleep(true)` — `sudo -n pmset disablesleep
    /// 1` — and it fails whenever the NOPASSWD rule is not what Helm wrote:
    /// removed by an admin, edited by a migration, tidied out of
    /// `/etc/sudoers.d`. The engine logs it and holds `active` false, and the row
    /// then drew the standing explanation of what the password buys, as though
    /// nothing had been attempted. This is the one state in which the switch says
    /// one thing and the machine does another, and a closed lid on that promise is
    /// a flat battery in a bag.
    ///
    /// Names the file, because the person who can fix this is the person who can
    /// read that directory.
    ///
    /// **And names what the person loses**, which the sentence never did: the
    /// switch is still on, so a reader who is told only that macOS refused
    /// something will close the lid and believe the Mac keeps working. It is the
    /// closed lid that is the consequence, and it belongs in the first clause
    /// rather than behind the file name.
    static var lidRefused: String {
        // One literal, however long: `NoOrphanTranslationsTests` looks for
        // `"<the whole key>"` in the concatenated source, and a key split over a
        // `+` is a key nothing in the tree asks for.
        L("macOS refused to turn sleep off, so closing the lid will let the Mac sleep. The rule in /etc/sudoers.d may have been changed")
    }
    /// The option went off and the rule did not go with it.
    ///
    /// `releaseIfUnneeded` asks for the rule to be removed, which raises an
    /// administrator dialog; a declined dialog is an answer, and the rule stays.
    /// Its `Bool` was discarded, so the only record was a log line accusing
    /// something else of having written a rule Helm wrote itself. A passwordless
    /// `pmset disablesleep` for this account is not something to leave behind
    /// silently.
    static var lidGrantRemains: String {
        L("The rule in /etc/sudoers.d is still there. Switch this on and off again to remove it")
    }
    /// What the person is about to face and what they get for it. `pmset` was
    /// the tool's name, which answers a question nobody asked: the two things
    /// worth knowing are that the password prompt is macOS's own — not this
    /// app's — and that the setting is system-wide, so it outlives a restart
    /// and Helm is not what keeps it. The wording for the password follows the
    /// system's own (SecurityPrivacyExtension.appex, "Require an administrator
    /// password to access system-wide settings").
    /// Two questions, so two sentences: what Helm does to the Mac, and what it
    /// costs. "The setting is system-wide" named no setting — what is system-wide
    /// is `pmset disablesleep`, i.e. sleep is off for the whole machine — and
    /// It now names the *grant*, not only the dialog. A security review put it
    /// plainly: the sentence explained the password box and never said what the
    /// box buys — a permanent passwordless-sudo rule for `pmset disablesleep`
    /// in `/etc/sudoers.d`, which outlives quitting Helm and deleting it, and
    /// which switching this option off is what takes back out.
    ///
    /// "once" was wrong, because the sudoers rule is removed when the toggle goes
    /// off, so switching it off and on asks again. The second sentence used to
    /// say «it stays off», where «it» could attach to Helm as easily as to
    /// sleep — and the Russian resolved it to the wrong one, promising that
    /// *Helm* would start at Helm's next start. The noun is repeated.
    ///
    /// **And the third sentence was simply false.** «If Helm quits while sleep is
    /// off, sleep stays off until Helm runs again» describes a Mac that cannot
    /// sleep for as long as its owner leaves Helm closed, and that is not what
    /// this code does: `applicationWillTerminate` calls `deactivate()` on every
    /// live engine, which calls `ClamshellCoordinator.tearDown`, which puts sleep
    /// back **synchronously** before the process goes. The state the old sentence
    /// described is the crash and the force-quit — the two ways out that run no
    /// code — and those are what `recoverAtLaunch` exists for. So the sentence now
    /// says what happens, which is also the reassuring half; it read as a warning
    /// about the ordinary case for eight languages.
    ///
    /// **And it now names the file and says how to get rid of it by hand.** The
    /// sentence described a grant with no way to find it: `/etc/sudoers.d` was
    /// mentioned in the two failure notes above and never here, where the
    /// decision is made. What a person needs before they type a password is
    /// where the thing lands, what takes it away, and what to do if nothing
    /// does — and the last of those is a real case: deleting Helm while it is
    /// running leaves the rule behind, and nothing in the app can reach it then
    /// (`ClamshellCoordinator.withdrawAtQuit`).
    static var adminNote: String {
        // swiftlint:disable:next line_length
        L("macOS asks for an administrator password the first time, and keeps a rule at /etc/sudoers.d/helm-keepawake that lets Helm turn sleep off without asking again. The rule permits its own removal, so switching this off takes it out without a second password, and so does quitting Helm. If Helm is deleted while it is still running, the rule stays behind: remove it with sudo rm /etc/sudoers.d/helm-keepawake. Quitting Helm turns sleep back on; if Helm crashes or is force-quit, the next launch turns it back on.")
    }
    /// A timer started while a rule is already holding the Mac ends the rule as
    /// well. Says «too» because the timer already ends the session it started —
    /// what the setting adds is the second half.
    static var timerEndsAutomation: String { L("A timer pauses the rule too") }
    /// The same words as the state it produces. It used to say «until the app
    /// is launched again», which is the way back for one of the three rules
    /// and false for the other two — a display rule comes back when the display
    /// does. That defect was found once in `automationPaused` and fixed there;
    /// this line was the second copy of it, translated faithfully eight times.
    static var timerEndsAutomationNote: String {
        L("When the timer runs out, the rule is paused until it applies again")
    }
    /// Shown wherever the state is shown. A Mac that slept with the rule's app
    /// still on screen is the one thing this module must not leave unexplained.
    /// «Paused until the rule fires again» — the rule, not the app.
    ///
    /// It said «until the app comes back», which is true of one of the three
    /// rules and false of the other two: a display rule comes back when the
    /// display is plugged in again and a power rule when the charger is, and
    /// neither involves an app. All eight languages had faithfully translated
    /// the wrong half. It is also the shortest of the three sentences, which is
    /// what lets the panel draw it beside a button in a 320 pt strip instead of
    /// hyphenating across three lines.
    static var automationPaused: String { L("Paused until the rule applies again") }
    /// The same fact for the panel, which is 320 pt with a button beside it.
    /// The long form wrapped to four lines there — a paragraph in a card that
    /// is otherwise a row and a switch. «Until it applies again» is what the
    /// settings page has room to add; here the word «paused» is the whole of
    /// what has to arrive, and the button beside it says what to do about it.
    static var automationPausedShort: String { L("Rule paused") }
    /// The boundary itself, mid-sentence: «при 20 % и ниже», «bei 20 % oder
    /// weniger», «20% 以下».
    ///
    /// **One declaration, three sentences.** The floor is named by the row under
    /// the slider, by the panel's notice and by the hero's, and each of the three
    /// used to spell it again in eight languages — twenty-four spellings of one
    /// phrase, which is how «below» survived in one of them for ten days after it
    /// had been corrected in another (`BatteryGuard.shouldDeactivate` is
    /// `percent <= threshold`, so the boundary is inclusive: 以下 and 及以下, never
    /// 未満 or 低于). The three sentences are composed from this one now, so a
    /// person who reads the row and then the banner reads the same words, and
    /// `TheBoundaryIsSpelledOnceTests` fails on any of the three that stops
    /// containing it.
    ///
    /// **The space before the sign is per language, not universal**, which is
    /// what the note on this function used to claim. Counted over the 1176
    /// `.loctable` files macOS ships, for a number and a literal per-cent sign:
    /// ru, de, fr and es put a no-break space there, while pt-BR joins (143
    /// joined, 0 spaced) and ja and zh join as a matter of course. English joins.
    static func atPercentOrLess(_ n: Int) -> String {
        L("at \(n)% or less",
          [.ru: "при \(n)\u{00A0}% и ниже", .es: "al \(n)\u{00A0}% o menos",
           .fr: "à \(n)\u{00A0}% ou moins", .de: "bei \(n)\u{00A0}% oder weniger",
           .ja: "\(n)% 以下", .zh: "\(n)% 及以下", .pt: "em \(n)% ou menos"])
    }

    /// The battery guard has everything stopped, said where there is room to say
    /// what to do about it: the hero, which is a 40 pt figure and a paragraph's
    /// width under it.
    ///
    /// **The short form was the whole notice, and it named no way out.** «Stopped
    /// at 20 % or less» is a fact; the person reading it has pressed a button and
    /// watched nothing happen, and what they need next is *plug in* — the veto
    /// lifts by itself the moment the charger goes in, which is the one thing
    /// none of the three surfaces said. The panel keeps the short form, because
    /// 320 pt beside a symbol is a row rather than a sentence
    /// (`stoppedByBatteryShort`).
    ///
    /// **And it then said what the 40 pt headline above it already said.** Under
    /// the veto the page draws `heroIdle` — «The Mac sleeps as usual» — and hides
    /// the reason line beneath it, so «Nothing keeps the Mac awake at 20 % or
    /// less» was one fact stated twice on one screen with the weaker,
    /// smaller copy underneath: exactly the duplication `heroIdle`'s own comment
    /// records being removed once already. What the headline cannot say is
    /// *which* setting stopped this and how to lift it, so the banner names the
    /// guard by the feature it belongs to and keeps the way out. This is also
    /// the sentence the system notification carries when nobody is at the
    /// screen (`batteryVetoNotice`).
    static func stoppedByBattery(_ percent: Int) -> String {
        let at = atPercentOrLess(percent)
        return L("The battery guard stops sessions \(at) — plug in",
                 [.ru: "Защита батареи не даёт начать сеанс \(at) — подключите адаптер питания",
                  .es: "La protección de batería detiene las sesiones \(at) — conecta el Mac a la corriente",
                  .fr: "La protection de batterie arrête les sessions \(at) — branchez le Mac sur secteur",
                  .de: "Der Batterieschutz stoppt Sitzungen \(at) — schließe das Netzteil an",
                  .ja: "バッテリー保護により\(at)ではセッションを開始できません。電源に接続してください",
                  .zh: "电量保护会在\(at)时停止会话，请接入电源",
                  .pt: "A proteção de bateria interrompe as sessões \(at) — conecte o Mac a uma fonte de alimentação"])
    }

    /// The same sentence again, for the one surface the person is not looking at.
    ///
    /// The battery veto ends a session with nobody at the Mac, so it is the one
    /// event this app sends a system notification for — and the notification says
    /// what the banner says, rather than a wording of its own. The engine posts
    /// it and cannot write it: `L()` is `HelmUI`'s and no engine target may
    /// import it, so the words are handed over as they are here
    /// (`BatteryVetoChannel`).
    ///
    /// Titled with the module's name because a notification with no title is
    /// drawn as the app's name and a body, and «Helm» does not say which of nine
    /// modules is speaking.
    static func batteryVetoNotice(_ percent: Int) -> NoticeText {
        NoticeText(title: moduleName, body: stoppedByBattery(percent))
    }

    /// The same fact for the panel, and for a rule's own row.
    ///
    /// 320 pt with a symbol beside it: the long form above wraps to four lines
    /// there, which is a paragraph in a card that is otherwise a row — the same
    /// reasoning `automationPausedShort` already carries one screen over. A rule
    /// row's note is 11 pt secondary copy under a title, and the way out belongs
    /// in the banner above it rather than repeated on three rows.
    static func stoppedByBatteryShort(_ percent: Int) -> String {
        let at = atPercentOrLess(percent)
        return L("Stopped \(at)",
                 [.ru: "Остановлено \(at)", .es: "Detenido \(at)", .fr: "Arrêté \(at)",
                  .de: "\(belowPercent(percent)) gestoppt",
                  .ja: "\(at)で停止", .zh: "\(at)时停止",
                  .pt: "Parado \(at)"])
    }
    static var resume: String { L("Resume") }
    static var turnOffLowBattery: String { L("Stop on low battery") }
    /// The boundary as a line of its own — the note under the slider — which is
    /// the same phrase with its first letter raised.
    ///
    /// Raised rather than written out again: the five cased languages of the
    /// eight all differ from `atPercentOrLess` in exactly that character, and ja
    /// and zh open on the figure, where the operation is a no-op. A second table
    /// here is how the two came to disagree about the operator once already.
    static func belowPercent(_ n: Int) -> String {
        let at = atPercentOrLess(n)
        return at.prefix(1).uppercased() + at.dropFirst()
    }
    static var activeIconColor: String { L("Active icon colour") }
    static var ringColorNote: String { L("Only while the Mac is kept awake. At other times Helm shows its shared icon") }
    static var addApp: String { L("Add app…") }
    static var ringTimer: String { L("Countdown ring in the menu bar") }
    static var ringTimerNote: String { L("While a timer runs, the ring empties clockwise") }
    static var showTimerText: String { L("Show remaining time in the menu bar") }
    static var timerColor: String { L("Timer colour") }
    static var timerColorNote: String { L("Until you pick one, the same as the active colour") }
    static var movePointerNote: String { L("So apps do not decide nobody is at the Mac") }
    /// **Names the two controls that actually use it.** It used to say «the
    /// menu-bar switch», and there is no switch in the menu bar: the status
    /// item opens the panel on a left click and a menu on a right click. The
    /// two senders of `toggle` are the panel's own switch and the keyboard
    /// shortcut — the second of which the note never mentioned, so the one
    /// control that starts a session without any window on screen went
    /// unexplained.
    static var defaultDurationNote: String {
        L("How long the panel's switch and the keyboard shortcut keep the Mac awake")
    }
    static var menuBarIcon: String { L("Menu-bar icon") }
    static var customActiveIcon: String { L("Custom icon when active") }
}
