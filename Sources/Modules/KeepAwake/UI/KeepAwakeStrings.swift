import Foundation
import HelmUI
import HelmRuntime
import Module_KeepAwake_Engine

/// Localized strings for the Keep Awake module UI. English is the base; the
/// module's `Localizable.xcstrings` carries all eight languages, and the
/// few words other modules share are `HelmWord`'s, because a catalog's symbols
/// are internal to its target.
enum KAStr {
    static var moduleName: String { L(.keepAwake) }
    static var summary: String { L(.summary) }
    /// Window title: no ellipsis — that belongs to the menu entry that opens it.
    static var customTimeTitle: String { L(.customDuration) }
    /// The button that opens the free-form duration field.
    ///
    /// Not «Timer»: that word already names the running countdown
    /// (`KAStr.timer`, «Timer colour», `KAStr.timerEndsAutomation`), and the
    /// three buttons beside this one are timers too. One word, one meaning.
    ///
    /// `Other…` is macOS's own label for a list of values with a way to enter
    /// one not on it. The translations are read out of Preview (`TB_Other...`)
    /// and Calendar (`Other…`), German non-breaking space before the ellipsis
    /// included.
    static var customTime: String { L(.other) }
    static var done: String { L(.done) }
    /// Short forms used under the "Automatically" heading, where the context is
    /// already given by the group title.
    static var onExternalDisplay: String { L(.withAnExternalDisplay) }
    static var onPower: String { L(.onPower) }
    /// Spanish says `Temporizador`, which is what macOS's own Clock says
    /// (Clock.app `Localizable.loctable`, key `TIMER`). German and Brazilian
    /// Portuguese genuinely say `Timer` in the same table.
    static var timer: String { HelmWord.timer }
    static var start: String { L(.start) }
    /// Single-letter units for the narrow preset pills ("15 м", "1 ч").
    static var minutesUnitShort: String { L(.minutesShort) }
    /// German abbreviates with a period — `2 Std.` — in CLDR and in ordinary
    /// orthography. One getter, so one duration has one spelling. Distinct from
    /// `minutesUnitShort` above, which is the full `Min.` because the pill has
    /// room for it.
    static var hoursUnitShort: String { L(.hoursShort) }
    static var minutesUnit: String { L(.minutesAbbreviated) }

    /// "45 min" / "1 h" / "1 h 30 min" — minutes below an hour, hours above.
    /// `compact` uses the single-letter units, for the narrow preset pills.
    ///
    /// The two hour presets in the settings picker keep their own keys and do
    /// not come from here: composed, they would read "1 ч" where Russian has
    /// «1 час». The abbreviation is what a narrow pill needs, not what a
    /// settings row wants.
    static func duration(_ minutes: Int, compact: Bool = false) -> String {
        let mUnit = compact ? minutesUnitShort : minutesUnit
        let hUnit = hoursUnitShort
        guard minutes >= 60 else { return "\(minutes)\u{00A0}\(mUnit)" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)\u{00A0}\(hUnit)" : "\(h)\u{00A0}\(hUnit) \(m)\u{00A0}\(mUnit)"
    }
    /// Over the enum, not its wire string, so the switch is exhaustive: a new
    /// case is a build error rather than an identifier drawn on screen.
    static func condition(_ condition: ActiveCondition) -> String {
        switch condition {
        case .manual: return L(.manual)
        case .timer: return HelmWord.timer
        case .externalDisplay: return L(.externalDisplay)
        case .power: return L(.onPower)
        case .app: return L(.app)
        }
    }

    // MARK: - Settings

    static var automation: String { L(.automation) }
    /// The note under a rule that is doing its job, and under one that is not.
    ///
    /// Without the second, a rule switched on that never fires and a rule
    /// nobody switched on are the same row with the same silence under it.
    static var ruleApplies: String { L(.appliesRightNow) }
    static var ruleWaiting: String { L(.notApplyingRightNow) }
    /// What a rule would do, said while it is still switched off: the one
    /// moment a person needs to know what a rule means.
    static func ruleMeaning(_ condition: ActiveCondition) -> String {
        switch condition {
        case .externalDisplay: return L(.whileExternalDisplay)
        case .power: return L(.whilePower)
        // Neither is a rule anybody switches on, so neither has a row here.
        case .manual, .timer, .app: return ""
        }
    }
    /// The whole note in one place, so the row's states and the cases that
    /// decide them are read from the same list.
    ///
    /// `.paused` re-uses `automationPaused`, the banner's own sentence, so one
    /// fact has one spelling. `.vetoed` re-uses the battery notice in its short
    /// form: the banner above the card carries the way out, and repeating it on
    /// every rule row would say «plug in» four times.
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
    /// The lid row's line, from the four states the machine can be in. Two of
    /// them say that something was attempted and did not work, which the
    /// standing explanation would hide. See `LidRowNote`.
    static func lidNote(_ note: LidRowNote) -> String {
        switch note {
        case .refused: return lidRefused
        case .grantRemains: return lidGrantRemains
        case .sleepIsOff: return sleepIsOffNote
        case .whatItCosts: return adminNote
        }
    }
    /// What the ⓘ beside the row's name opens, per state — `nil` where the row
    /// has said everything there is.
    ///
    /// Only the state in which a password is about to be asked for offers one.
    /// `refused` and `grantRemains` already name the gesture that deals with
    /// the rule; `sleepIsOff` is a report. The deciding state is also the only
    /// one where the hand-removal command can be read before it is needed: the
    /// case it is for is a Helm that has been deleted and draws nothing.
    static func lidExplainer(_ note: LidRowNote) -> HelmExplainer.Content? {
        switch note {
        case .refused, .grantRemains, .sleepIsOff:
            return nil
        case .whatItCosts:
            return HelmExplainer.Content(title: keepAwakeLidClosed, blocks: [
                .text(L(.ruleRemovesItself)),
                .text(L(.deleteHelmLeavesRule)),
                // The path from the engine that writes it, never typed again
                // here: a command naming a file Helm stopped writing is worse
                // than no command at all.
                .command("sudo rm \(SudoersRule.installedPath)"),
            ])
        }
    }
    /// The reason line under the figure: «External display · Safari».
    ///
    /// The `.app` case names the apps, so a person with four apps in the list
    /// can tell which one is holding the Mac.
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
    static func triggerCondition(_ condition: AppTrigger.Condition) -> String {
        switch condition {
        case .always: return L(.always)
        case .externalDisplay: return L(.withAnExternalDisplay)
        case .power: return L(.onPower)
        case .displayAndPower: return L(.displayAndPower)
        }
    }
    static var noAppsYet: String { L(.noAppsChosen) }
    /// A rules string in the file that nothing can read.
    ///
    /// The reader answers «no rules» for it, which fails in the safe direction —
    /// the Mac sleeps — and looks exactly like having chosen no apps at all.
    /// Says what was lost and what follows from it, because the second half is
    /// what the person noticed.
    ///
    /// And then what to do: the string in the file will not become readable by
    /// waiting, and picking the apps again rewrites the key and takes the
    /// banner away with it.
    static var appRulesUnreadable: String { L(.appRulesUnreadable) }
    /// What an app rule is, said where somebody would otherwise find out by
    /// trying, and only while the list is empty.
    static var noAppsYetNote: String { L(.appRulesEmptyHint) }
    static var keepDisplayOn: String { L(.keepTheDisplayOn) }
    static var movePointer: String { L(.moveThePointer) }
    /// "Каждые 1 мин" is wrong, and the menu starts at 1: the Russian
    /// quantifier agrees with the last digit, with the 11–14 exception
    /// `Plural.russian` already knows.
    static func everyMinutes(_ n: Int) -> String {
        // Every language says "Every minute" rather than "Every 1 min", and
        // the menu opens on one.
        if n == 1 { return L(.everyMinute) }
        // Russian alone has a word that changes with the figure (21, 31 … take
        // the singular's «Каждую»); the other seven carry the same text under
        // both keys.
        return Plural.form(n, language: AppLanguage.current.rawValue) == .one
            ? L(.everyMinutesOne(String(n))) : L(.everyMinutes(String(n)))
    }
    static var defaultDuration: String { L(.defaultDuration) }
    static var oneHour: String { L(.oneHour) }
    static var twoHours: String { L(.twoHours) }
    static var indefinite: String { L(.indefinite) }

    // MARK: - The hero
    //
    // The top of the page says what is happening and offers the verbs for it.

    static var heroIdle: String { L(.macSleepsAsUsual) }
    /// Two different silences, and they want different sentences: nothing is
    /// switched on, and something is switched on but does not apply. The first
    /// is an invitation, the second is an explanation.
    static var heroNoRules: String { L(.noRuleOn) }
    static var heroIdleReason: String { L(.noRuleApplies) }
    /// One figure for «awake», whatever is holding it, and the reason on the
    /// line below, as the countdown state does. The figure answers one
    /// question: is this Mac going to sleep.
    static var heroAwake: String { L(.macStaysAwake) }
    /// The reason line for a session with no deadline. «Until you stop it» is
    /// the whole answer, and it is the same shape as the conditions listed for
    /// a session a rule is holding.
    static var heroUntilYouStop: String { L(.untilStopped) }
    /// Said beside the button that does it, rather than left for the log.
    static var heroStopSuppresses: String { L(.stopPausesRule) }

    /// What VoiceOver says for the countdown, once, when asked.
    ///
    /// One key with the figure inside it, not a word and a literal colon: the
    /// colon and the space before it are the language's, French and Japanese
    /// write them differently. The figure on screen is `1:23:45` and is
    /// announced as it reads; the words in front make it a duration rather
    /// than a time of day.
    static func a11yRemaining(_ label: String) -> String {
        L(.timeRemainingFigure(label))
    }
    /// «Таймер до 15:42» — the deadline as a clock, which is what a person
    /// checks against. `HelmDates.timeOfDay` writes it in the app's language,
    /// not the system's.
    static func timerUntil(_ end: Date) -> String {
        L(.timerUntil(HelmDates.timeOfDay(end)))
    }
    /// The second half of that line: what is still holding the Mac when the
    /// countdown reaches zero.
    ///
    /// Three whole sentences, not one sentence with a row label dropped into
    /// it: a row label is not a noun phrase a sentence can take («then on power
    /// keeps it awake»), and no language's grammar survives the interpolation.
    static func thenHeldBy(_ condition: ActiveCondition) -> String {
        switch condition {
        case .externalDisplay: return L(.thenDisplayKeeps)
        case .power: return L(.thenPowerKeeps)
        case .app: return L(.thenAppKeeps)
        // `SessionHero.afterTimer` only ever answers `.heldBy` with one of the three
        // above; the switch is exhaustive so a fourth automatic condition is a
        // build error here rather than a sentence nobody wrote.
        case .manual, .timer: return ""
        }
    }
    /// The third answer at zero: with «A timer pauses the rule too» on, this is
    /// the one state where that setting decides anything, so the note says it.
    static var thenRulePaused: String { L(.thenRulePaused) }
    static var pointerNeedsAccessibility: String { L(.pointerNeedsAccessibility) }
    /// macOS calls it «Сочетание клавиш» (KeyboardSettings.appex, key
    /// "Keyboard shortcut"), as Helm's Layout page does; «хоткей» is slang.
    /// The other seven carry their system's root — de Kurzbefehl, es Atajo,
    /// fr Raccourci, zh 快捷键, ja ショートカット, pt Atalho — checked against
    /// the same table.
    static var globalShortcut: String { L(.globalShortcut) }
    static var toggleAction: String { L(.toggleKeepAwake) }
    static var keepAwakeLidClosed: String { L(.stayAwakeWithTheLid) }
    /// Sleep is off, and for the whole Mac — the scope is the point.
    ///
    /// The setting turns system sleep off machine-wide, through a sudoers rule
    /// that outlives this process. «Sleep is off right now» alone could be read
    /// as an assertion, which is what every other row on the page holds and is
    /// nothing like this; a Mac whose sleep is off will not sleep in a bag.
    ///
    /// This is the panel's spelling, a fragment in a list joined with « · »
    /// inside a 320 pt card, so it takes the sentence and not the way out of
    /// it; the settings row has the width and takes `sleepIsOffNote`, the same
    /// sentence with the revocation clause after it. One wording, two lengths.
    ///
    /// The lid is not what holds the Mac: it is what is safe to close because
    /// sleep is off.
    static var sleepIsOffNow: String { L(.sleepOffNow) }
    /// The same fact where there is room for the way back out of it.
    ///
    /// A row that reports a system-wide setting has to say what undoes it, and
    /// here it is not obvious: nothing in `/etc/sudoers.d` undoes itself, and
    /// the control that takes it back is the switch on this very row.
    ///
    /// The English says which noun comes back. «Brings it back» could point at
    /// the setting or at the Mac's sleep, and in ru, es, de and pt the two have
    /// different genders, so a pronoun makes the translation pick one.
    static var sleepIsOffNote: String { L(.sleepOffNowSwitchingBack) }
    /// macOS said no.
    ///
    /// `reallyEngage` reads `setDisableSleep(true)` — `sudo -n pmset disablesleep
    /// 1` — and it fails whenever the NOPASSWD rule is not what Helm wrote:
    /// removed by an admin, edited by a migration, tidied out of
    /// `/etc/sudoers.d`. The engine holds `active` false. This is the one state
    /// in which the switch says one thing and the machine does another, and a
    /// closed lid on that promise is a flat battery in a bag.
    ///
    /// Names the file, because the person who can fix this is the person who can
    /// read that directory. Names what the person loses in the first clause:
    /// the switch is still on, and a reader told only that macOS refused
    /// something will close the lid and believe the Mac keeps working.
    static var lidRefused: String { L(.lidGrantRefused) }
    /// The option went off and the rule did not go with it.
    ///
    /// `releaseIfUnneeded` asks for the rule to be removed, which raises an
    /// administrator dialog; a declined dialog is an answer, and the rule stays.
    /// A passwordless `pmset disablesleep` for this account is not something to
    /// leave behind silently.
    static var lidGrantRemains: String { L(.lidRuleStillThere) }
    /// What the person is about to face and what they get for it.
    ///
    /// The password prompt is macOS's own, not this app's, and its wording
    /// follows the system's (SecurityPrivacyExtension.appex, "Require an
    /// administrator password to access system-wide settings"). The sentence
    /// names the grant, not only the dialog: a passwordless-sudo rule for
    /// `pmset disablesleep` in `/etc/sudoers.d`, which outlives quitting and
    /// deleting Helm, and which switching this option off takes back out.
    ///
    /// It says nothing about how often the password is asked: the rule is
    /// removed when the switch goes off, so off-and-on asks again, and «once» or
    /// «the first time» would be false. The noun is repeated where «it» could
    /// attach to Helm as easily as to sleep.
    ///
    /// Quitting puts sleep back: `applicationWillTerminate` calls `deactivate()`
    /// on every live engine, and `ClamshellCoordinator.tearDown` restores sleep
    /// synchronously before the process goes. A crash and a force-quit run no
    /// code, and those are what `recoverAtLaunch` is for.
    ///
    /// The sentence keeps what the decision needs — a password, a rule, and
    /// that switching this off takes the rule away. What follows from it (where
    /// the file lands, how to remove it by hand once Helm is deleted,
    /// `ClamshellCoordinator.withdrawAtQuit`) is in `lidExplainer`, behind the ⓘ,
    /// so the row stays a caption.
    static var adminNote: String { L(.lidGrantExplained) }
    /// A timer started while a rule is already holding the Mac ends the rule as
    /// well.
    ///
    /// The name says which timer, which rule and when: the module has a
    /// countdown, a default duration and a «+15», and four rule rows; and
    /// «too» alone would not say it happens at zero. The row's note keeps what
    /// follows from it.
    static var timerEndsAutomation: String { L(.timerPausesRules) }
    /// The Stop button's word for the press it is about to be.
    ///
    /// The switch above and this button are the two ways automation is switched
    /// off, and the difference is where the person is — `StopPress` has the
    /// sentence. The mapping is here, exhaustive, because the word and the act
    /// are one decision: a case added to `StopPress` without a word for it is a
    /// build error rather than a button that goes on saying «Stop» while doing
    /// something else.
    static func stopWord(_ press: StopPress) -> String {
        switch press {
        case .stopEverything, .stopSessionOnly: return HelmWord.stop
        case .turnAutomationOff: return switchOff
        }
    }
    /// Not Leftovers' «Turn off»: that word is the switch on a login item, in
    /// Leftovers' own catalog. One word means one thing, and a catalog's
    /// symbols are internal to its target in any case.
    static var switchOff: String { L(.switchOff) }
    /// The same words as the state it produces: a paused rule comes back when
    /// its condition does (a display rule when the display does), not when an
    /// app is launched again.
    static var timerEndsAutomationNote: String { L(.timerEndPausesRule) }
    /// Shown wherever the state is shown. A Mac that slept with the rule's app
    /// still on screen is the one thing this module must not leave unexplained.
    /// «Paused until the rule fires again» — the rule, not the app.
    ///
    /// The rule, because a display rule comes back with the display and a
    /// power rule with the charger; neither involves an app. It is also the
    /// shortest of the three sentences, so the panel can draw it beside a
    /// button in a 320 pt strip.
    static var automationPaused: String { L(.pausedUntilRuleApplies) }
    /// The same fact for the panel, which is 320 pt with a button beside it,
    /// where the long form wraps to four lines. The word «paused» is the whole
    /// of what has to arrive, and the button beside it says what to do.
    static var automationPausedShort: String { L(.rulePaused) }
    /// macOS said no to the sleep assertion, so the Mac sleeps on its own
    /// schedule while the session believes it is holding. One sentence for the hero
    /// and the panel: it is short enough for the 320 pt card, and there is no way
    /// out to add — a refusal is not something a person can lift.
    static var assertionRefused: String { L(.macOSRefusedToKeepAwake) }
    /// The boundary itself, mid-sentence: «при 20 % и ниже», «bei 20 % oder
    /// weniger», «20% 以下».
    ///
    /// One declaration, three sentences: the row under the slider, the panel's
    /// notice and the hero's are composed from this, so a person reads the same
    /// words in each. The boundary is inclusive (`BatteryGuard.shouldDeactivate`
    /// is `percent <= threshold`): 以下 and 及以下, never 未満 or 低于.
    ///
    /// The space before the sign is per language, as macOS's `.loctable` files
    /// write a number and a per-cent sign: ru, de, fr and es put a no-break
    /// space there; pt-BR, ja, zh and English join.
    static func atPercentOrLess(_ n: Int) -> String {
        L(.atPercentOrLess(String(n)))
    }

    /// The battery guard has everything stopped, said where there is room to say
    /// what to do about it: the hero, which is a 40 pt figure and a paragraph's
    /// width under it.
    ///
    /// It names the way out: the veto lifts by itself the moment the charger
    /// goes in. The panel keeps the short form, because 320 pt beside a symbol
    /// is a row rather than a sentence (`stoppedByBatteryShort`).
    ///
    /// It does not repeat the headline: under the veto the page draws `heroIdle`
    /// and hides the reason line, so the banner names the guard by the feature
    /// it belongs to and how to lift it. This is also the sentence the system
    /// notification carries when nobody is at the screen (`batteryVetoNotice`).
    static func stoppedByBattery(_ percent: Int) -> String {
        L(.stoppedByBattery(atPercentOrLess(percent)))
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
    /// 320 pt with a symbol beside it, where the long form above wraps to four
    /// lines. A rule row's note is 11 pt secondary copy under a title, and the
    /// way out belongs in the banner above it rather than repeated on each row.
    static func stoppedByBatteryShort(_ percent: Int) -> String {
        // German alone puts the phrase first, so it takes the one with its first letter raised.
        L(.stoppedByBatteryShort(AppLanguage.current == .de ? belowPercent(percent) : atPercentOrLess(percent)))
    }
    static var resume: String { L(.resume) }
    static var turnOffLowBattery: String { L(.stopOnLowBattery) }
    /// The boundary as a line of its own — the note under the slider — which is
    /// the same phrase with its first letter raised.
    ///
    /// Raised rather than written out again: the five cased languages of the
    /// eight all differ from `atPercentOrLess` in exactly that character, and ja
    /// and zh open on the figure, where the operation is a no-op. A second
    /// catalog entry would let the two disagree about the operator.
    static func belowPercent(_ n: Int) -> String {
        let at = atPercentOrLess(n)
        return at.prefix(1).uppercased() + at.dropFirst()
    }
    static var activeIconColor: String { L(.activeIconColour) }
    static var ringColorNote: String { L(.activeIconColourHint) }
    static var ringTimer: String { L(.countdownRing) }
    static var ringTimerNote: String { L(.countdownRingHint) }
    static var showTimerText: String { L(.showRemainingTime) }
    static var timerColor: String { L(.timerColour) }
    static var timerColorNote: String { L(.timerColourNote) }
    static var movePointerNote: String { L(.movePointerHint) }
    /// Names the two controls that use it: the panel's own switch and the
    /// keyboard shortcut, the second of which starts a session with no window
    /// on screen. There is no switch in the menu bar: the status item opens the
    /// panel on a left click and a menu on a right click.
    static var defaultDurationNote: String { L(.defaultDurationHint) }
    static var menuBarIcon: String { L(.menuBarIcon) }
    static var customActiveIcon: String { L(.customIconWhenActive) }
}
