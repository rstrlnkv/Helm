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
    static var customTime: String { L("Custom…") }
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
    static var lidClosed: String {
        L("Lid closed — staying awake")
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
    /// What an app rule *is*, said where somebody would otherwise find out by
    /// trying. The section heading used to carry this job in its own tail —
    /// «Apps that keep the Mac awake» — which explained it again on every visit
    /// for ever, including to the people who already had a list.
    static var noAppsYetNote: String {
        L("Add an app and the Mac stays awake while it is running. You can limit a rule to power, to an external display, or to both.")
    }
    static var behavior: String { L("Behaviour") }
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
    /// "once" was wrong, because the sudoers rule is removed when the toggle goes
    /// off, so switching it off and on asks again. The second sentence used to
    /// say «it stays off», where «it» could attach to Helm as easily as to
    /// sleep — and the Russian resolved it to the wrong one, promising that
    /// *Helm* would start at Helm's next start. The noun is repeated.
    static var adminNote: String {
        L("macOS asks for an administrator password the first time. If Helm quits while sleep is off, sleep stays off until Helm runs again.")
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
    static var resume: String { L("Resume") }
    static var turnOffLowBattery: String { L("Stop on low battery") }
    /// `BatteryGuard.shouldDeactivate` is `percent <= threshold`: at exactly the
    /// figure shown, the session stops. Every language used to say "below" — and
    /// ja/zh said it with 未満 / 低于, the strict operators, in languages that have
    /// the inclusive one. The string named an operator the code does not use.
    ///
    /// The no-break space before the sign is macOS's own: every literal percent
    /// in the system's own extension tables is joined.
    static func belowPercent(_ n: Int) -> String { L("At \(n)% or less", [.ru: "При \(n)\u{00A0}% и ниже", .es: "Al \(n)\u{00A0}% o menos", .fr: "À \(n)\u{00A0}% ou moins", .de: "Bei \(n)\u{00A0}% oder weniger", .ja: "\(n)% 以下", .zh: "\(n)% 及以下", .pt: "Em \(n)\u{00A0}% ou menos"]) }
    static var activeIconColor: String { L("Active icon colour") }
    static var ringColorNote: String { L("Only while the Mac is kept awake. At other times Helm shows its shared icon") }
    static var addApp: String { L("Add app…") }
    static var ringTimer: String { L("Countdown ring in the menu bar") }
    static var ringTimerNote: String { L("While a timer runs, the ring empties clockwise") }
    static var showTimerText: String { L("Show remaining time in the menu bar") }
    static var timerColor: String { L("Timer colour") }
    static var timerColorNote: String { L("Until you pick one, the same as the active colour") }
    static var movePointerNote: String { L("So apps do not decide nobody is at the Mac") }
    static var defaultDurationNote: String {
        L("How long the menu-bar switch and the panel keep the Mac awake")
    }
    static var menuBarIcon: String { L("Menu-bar icon") }
    static var customActiveIcon: String { L("Custom icon when active") }
}
