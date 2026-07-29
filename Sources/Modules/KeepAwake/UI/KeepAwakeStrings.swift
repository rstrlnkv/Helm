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
    static var lidClosed: String {
        L("Lid closed — staying awake")
    }

    static func condition(_ wire: String) -> String {
        switch wire {
        case "manual": return L("Manual")
        case "timer": return L("Timer")
        case "externalDisplay": return L("External display")
        case "power": return L("On power")
        case "app": return L("App")
        default: return wire
        }
    }

    // MARK: - Settings

    static var automation: String { L("Automation") }
    static var withExternalDisplay: String { L("Keep awake with external display") }
    static var whileOnPower: String { L("Keep awake while on power") }
    static var appsSection: String { L("Apps that keep the Mac awake") }
    static func triggerCondition(_ condition: AppTrigger.Condition) -> String {
        switch condition {
        case .always: return L("Always")
        case .externalDisplay: return L("With an external display")
        case .power: return L("On power")
        case .displayAndPower: return L("Display and power")
        }
    }
    static var noAppsYet: String { L("No apps yet.") }
    static var behavior: String { L("Behavior") }
    static var keepDisplayOn: String { L("Keep display on") }
    static var movePointer: String { L("Move pointer periodically") }
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
                  .ja: "\(n)分ごと", .zh: "每 \(n) 分钟",
                  .pt: n == 1 ? "A cada minuto" : "A cada \(n) min"])
    }
    static var defaultDuration: String { L("Default duration") }
    static var oneHour: String { L("1 hour") }
    static var twoHours: String { L("2 hours") }
    static var indefinite: String { L("Indefinite") }
    static var pointerNeedsAccessibility: String { L("Needs Accessibility, or the pointer will not move.") }
    /// Russian was the odd one out: «хоткей» is slang, and Helm's own Layout
    /// page already says «сочетание клавиш». macOS calls it «Сочетание клавиш»
    /// (KeyboardSettings.appex, key "Keyboard shortcut"), so that is the word.
    /// The other seven already carry their own system's root — de Kurzbefehl,
    /// es Atajo, fr Raccourci, zh 快捷键, ja ショートカット, pt Atalho — checked
    /// against the same table rather than assumed.
    static var globalShortcut: String { L("Global shortcut") }
    static var toggleAction: String { L("Toggle Keep Awake") }
    static var keepAwakeLidClosed: String { L("Keep awake with the lid closed") }
    /// What the person is about to face and what they get for it. `pmset` was
    /// the tool's name, which answers a question nobody asked: the two things
    /// worth knowing are that the password prompt is macOS's own — not this
    /// app's — and that the setting is system-wide, so it outlives a restart
    /// and Helm is not what keeps it. The wording for the password follows the
    /// system's own (SecurityPrivacyExtension.appex, "Require an administrator
    /// password to access system-wide settings").
    static var adminNote: String { L("macOS asks for an administrator password once. The setting is system-wide and survives a restart.") }
    static var turnOffLowBattery: String { L("Turn off on low battery") }
    static func belowPercent(_ n: Int) -> String { L("Below \(n)%", [.ru: "Ниже \(n) %", .es: "Por debajo del \(n) %", .fr: "En dessous de \(n) %", .de: "Unter \(n) %", .ja: "\(n)% 未満", .zh: "低于 \(n)%", .pt: "Abaixo de \(n)%"]) }
    static var activeIconColor: String { L("Active icon color") }
    static var ringColorNote: String { L("Applies while Keep Awake is on; otherwise the shared menu-bar icon is used.") }
    static var addApp: String { L("Add app…") }
    static var ringTimer: String { L("Countdown ring in the menu bar") }
    static var ringTimerNote: String { L("While a timer runs, the ring empties clockwise.") }
    static var showTimerText: String { L("Show remaining time in the menu bar") }
    static var timerColor: String { L("Timer color") }
    static var menuBarIcon: String { L("Menu-bar icon") }
    static var customActiveIcon: String { L("Custom icon when active") }
    static var min15: String { "15 " + minutesUnit }
    static var metricState: String { L("STATE") }
    /// Whole words. Three of these were clipped with a period into a cell that
    /// fits them: the strip's label style is 9 pt semibold at 0.7 tracking and
    /// the cell is a third of the 704 pt settings column, about 230 pt, while
    /// `TEMPORIZADOR` measures 84, `AUTOMATIZACIONES` 109 and
    /// `AUTOMATISATIONS` 101. Chinese was `计时` — the verb "to time" — where
    /// every other language has the noun; macOS's own Clock says `计时器`
    /// (`Localizable.loctable`, key `TIMER`), which measures 29.
    static var metricTimer: String { L("TIMER") }
    static var metricRules: String { L("AUTOMATIONS") }
    static var metricOn: String { L("ON") }
    static var metricOff: String { L("OFF") }
}
