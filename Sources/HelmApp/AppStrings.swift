import HelmRuntime
import HelmUI

/// Localized strings for the app shell (settings window chrome).
enum AppStr {
    /// The settings window's own title. Never drawn — the window hides its
    /// title bar text — and read aloud all the same: VoiceOver announces it on
    /// focus, and the Window menu lists it. It was the one user-visible English
    /// string in the app that was not behind `L()`, which is exactly the kind of
    /// string that keeps being the last one.
    ///
    /// "Helm Settings", the shape macOS uses for an app's own settings window,
    /// with each language's word for the pane taken from `settingsPane` so the
    /// title and the sidebar cannot disagree.
    static var settingsWindowTitle: String {
        L("Helm Settings")
    }
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    static var settingsPane: String { L("Settings") }
    /// What Helm does on its own. `General` was the name when the section held
    /// three unrelated decisions — a login item, a theme and a colour choice —
    /// and a heading that promises nothing is a heading nobody reads.
    static var behaviour: String { L("Behaviour") }
    /// The light/dark control, which macOS itself calls «Appearance» — the same
    /// word as the section it now sits in. A section and its first row reading
    /// identically is how a person stops seeing the heading at all, so the row
    /// says what it chooses between.
    static var lightOrDark: String { L("Light or dark") }
    static var launchAtLogin: String { L("Open Helm at login") }
    static var checking: String { L("Checking…") }
    static var upToDate: String { L("You’re on the latest version.") }
    /// Said to somebody running a build the channel has not published yet —
    /// which is a state worth naming rather than calling "up to date", because
    /// the person in it is usually the person testing something.
    static func aheadOfChannel(_ newest: String) -> String {
        L("Your build is newer than the channel — its latest is \(newest).",
          [.ru: "Ваша сборка новее канала — в нём последняя \(newest).",
           .es: "Tu compilación es más reciente que el canal: la última de este es \(newest).",
           .fr: "Votre version est plus récente que le canal — la dernière y est \(newest).",
           .de: "Dein Build ist neuer als der Kanal — dessen neuester ist \(newest).",
           .ja: "お使いのビルドはチャンネルより新しいバージョンです（チャンネルの最新は \(newest)）。",
           .zh: "你的版本比该通道更新——通道中的最新版本是 \(newest)。",
           .pt: "Sua build é mais recente que o canal — a última dele é \(newest)."])
    }
    static var download: String { L("Download") }
    static var updateReady: String { L("Update ready") }
    static var updateAndRelaunch: String { L("Update & Relaunch") }
    static var downloadingUpdate: String { L("Downloading…") }
    static var installingUpdate: String { L("Installing…") }
    /// Not `updateFailed`. A download that does not match what the release
    /// published is not a network hiccup, and Retry is the wrong offer: the
    /// honest next step is to look at the release itself.
    static var updateDigestMismatch: String {
        L("The download did not match what the release published, so Helm did not install it.")
    }
    static var updateFailed: String { L("Update failed") }
    static var edit: String { L("Edit") }
    static var done: String { L("Done") }
    static var permissionsChanged: String { L("Helm is missing permissions it needs") }
    static var later: String { L("Later") }
    static var permissions: String { L("Permissions") }
    static var fullDiskAccess: String { L("Full Disk Access") }
    static var fullDiskAccessWhy: String { L("Needed to remove app containers and to read every folder when scanning the disk.") }
    static var fullDiskAccessAdHoc: String { L("Access is tied to one exact copy of Helm, so grant it again after every update: remove Helm with “−”, then add it with “+”.") }
    static var grant: String { L("Grant…") }
    static var show: String { L("Show") }

    /// The one thing on the settings page that is wrong right now, said above
    /// everything else. Counted from `permissions` rather than `inertWithout`:
    /// the sidebar's triangle marks a module that can do nothing, and this line
    /// is about every module a missing grant reaches.
    static func permissionsWithheld(count: Int, modules: Int) -> String {
        let en = "\(count) " + (count == 1 ? "permission" : "permissions")
            + " not granted · \(modules) " + (modules == 1 ? "module" : "modules") + " affected"
        return L(en,
          [.ru: "Не выдано \(count) "
                + Plural.russian(count, "разрешение", "разрешения", "разрешений")
                + " · затронуто \(modules) "
                + Plural.russian(modules, "модуль", "модуля", "модулей"),
           .es: "Faltan \(count) " + (count == 1 ? "permiso" : "permisos")
                + " · \(modules) " + (modules == 1 ? "módulo afectado" : "módulos afectados"),
           .fr: "\(count) " + (count == 1 ? "autorisation manquante" : "autorisations manquantes")
                + " · \(modules) " + (modules == 1 ? "module concerné" : "modules concernés"),
           .de: "\(count) " + (count == 1 ? "Berechtigung fehlt" : "Berechtigungen fehlen")
                + " · \(modules) " + (modules == 1 ? "Modul betroffen" : "Module betroffen"),
           .ja: "\(count) 件の許可が未付与 · \(modules) 個のモジュールに影響",
           .zh: "\(count) 项权限未授予 · 影响 \(modules) 个模块",
           .pt: "\(count) " + (count == 1 ? "permissão não concedida" : "permissões não concedidas")
                + " · \(modules) " + (modules == 1 ? "módulo afetado" : "módulos afetados")])
    }
    /// The localized face of `PermissionNeed`; the runtime carries English.
    static func permissionTitle(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return fullDiskAccess
        case .accessibility: return accessibility
        }
    }
    static func permissionWhy(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return fullDiskAccessWhy
        case .accessibility: return accessibilityWhy
        }
    }
    static var accessibility: String { L("Accessibility") }
    /// Names both things the grant buys, because one of them is that Helm can
    /// see every keystroke in every application. The lapsed-grant alert
    /// (`permissionReason`) already said so; this is the caption a person reads
    /// *while deciding*, and it described a mouse jiggle.
    static var accessibilityWhy: String { L("Needed for Keyboard to fix the layout of what you type, and for Keep Awake to nudge the pointer. Without it neither works.") }
    static var writeLog: String { L("Write a log file") }
    static var logNoteDev: String { L("Dev builds always log. The file lives in ~/Library/Logs/Helm.") }
    static var logNoteStable: String { L("Turn on before reporting a problem. The file lives in ~/Library/Logs/Helm.") }
    static var revealLog: String { L("Show in Finder") }
    static var copyLog: String { L("Copy log") }
    /// Next to the button whose whole purpose is pasting this into a bug report.
    /// `HelmLog` puts every app name, VPN name and path through `Redact` before
    /// writing, and that is a reason to press the button rather than a footnote.
    static var logRedactionNote: String {
        L("The log records what Helm did, not what you have: app names, VPN names and paths are replaced before anything is written.")
    }
    static var clearLog: String { L("Clear") }
    static var whatsNewSummary: String { L("Everything that landed in Helm, newest first.") }
    /// The four headings under it, in order. It said «module order… and
    /// diagnostics»: the order is one row now and diagnostics is a page of its
    /// own, so the subtitle named one thing that had moved and one that was
    /// not here.
    static var settingsPaneSummary: String {
        L("Behaviour, appearance, permissions and what Helm may remove.")
    }
    static var modulesSection: String { L("Modules") }
    static var tagline: String { L("Modular tools in your menu bar.") }
    static var metricVersion: String { L("VERSION") }
    static var metricBuild: String { L("BUILD") }
    static var metricModules: String { L("MODULES") }
    static var checkNow: String { L("Check") }
    static var appearance: String { L("Appearance") }
    /// Named the way System Settings names them, so the choice reads the same
    /// in both places.
    static func appearanceName(_ choice: AppAppearance) -> String {
        switch choice {
        case .system: return L("Auto")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }
    /// Why Helm wants a permission, named per permission. An unexplained
    /// request is one people deny.
    static func permissionReason(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess:
            return L("Full disk access is off. Without it the disk scan cannot read every folder, and removing an app leaves its containers behind.")
        case .accessibility:
            return L("Accessibility is off. Without it Helm cannot see what you type, so keyboard corrections and the pointer nudge do nothing.")
        }
    }

    static func openPane(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return openDiskAccessPane
        case .accessibility: return openAccessibilityPane
        }
    }

    /// The Uninstaller's button and this one open the same pane and said two
    /// different things — and the seven translations of both were identical,
    /// which is the proof they were one concept with two English spellings.
    /// One key each, naming the pane the way System Settings does.
    static var openDiskAccessPane: String { L("Open Full Disk Access…") }
    static var openAccessibilityPane: String { L("Open Accessibility…") }
    static var retry: String { L("Try again") }
    /// Shown when a release publishes no digest for its asset: the updater
    /// refuses to swap a bundle it cannot check, and hands the user the page.
    static var updateManualInstall: String { L("This release published no checksum. Helm opened its download page instead.") }
    static var updateCheckFailed: String { L("Couldn’t check for updates.") }
    static func lastChecked(_ when: String) -> String { L("Checked \(when)", [.ru: "Проверялось \(when)", .es: "Comprobado \(when)", .fr: "Vérifié \(when)", .de: "Geprüft \(when)", .ja: "確認: \(when)", .zh: "检查于\(when)", .pt: "Verificado \(when)"]) }
    static var neverChecked: String { L("Not checked yet") }
    static var updateChannel: String { L("Update channel") }
    static var channelBeta: String { L("Beta") }
    static var channelDev: String { L("Dev") }
    static var channelBetaNote: String { L("Helm is still in development. Beta builds are the steadier of the two.") }
    static var flagCredit: String { L("Flag artwork: flag-icons, MIT") }
    /// Set in capitals like `betaBadge`: they sit side by side and a pair
    /// where one shouts and the other does not reads as two kinds of thing.
    static var devBadge: String { L("DEV") }
    static var betaBadge: String { L("BETA") }
    static var channelDevNote: String { L("Early builds with new features — expect rough edges.") }
    /// The sidebar's warning next to a module macOS is currently blocking.
    static var moduleBlockedByPermission: String {
        L("Switched on, but macOS is withholding what it needs")
    }
    // MARK: - The live log (dev builds only)

    static var logPane: String { L("Log") }
    static var logPaneSummary: String { L("What Helm is writing, as it writes it.") }
    static var logLevel: String { L("What to show") }
    static var logLevelAll: String { L("Everything") }
    static var logLevelWarnings: String { L("Warnings") }
    static var logLevelErrors: String { L("Errors") }
    static var logAllModules: String { L("All modules") }
    /// Counted, because "1 modules" and „1 Module" are what a bare plural
    /// produces — and this menu shows 1 more often than any other number.
    static func logSomeModules(_ n: Int) -> String {
        L(n == 1 ? "1 module" : "\(n) modules", [.ru: n == 1 ? "1 модуль" : "Модулей: \(n)",
                           .es: n == 1 ? "1 módulo" : "\(n) módulos",
                           .fr: n == 1 ? "1 module" : "\(n) modules",
                           .de: n == 1 ? "1 Modul" : "\(n) Module",
                           .ja: "\(n) 個のモジュール", .zh: "\(n) 个模块",
                           .pt: n == 1 ? "1 módulo" : "\(n) módulos"])
    }
    /// Stays pinned to the newest line while it is on. Off is what somebody
    /// wants the moment they see the line they were waiting for.
    static var logFollow: String { L("Follow") }
    static var logEmpty: String { L("Nothing logged yet.") }
    static var logNothingMatches: String { L("Nothing matches these filters.") }
    static func logCount(_ shown: Int, _ total: Int) -> String {
        L("\(shown) of \(total) lines", [.ru: "Строк: \(shown) из \(total)",
                                          .es: "\(shown) de \(total) líneas",
                                          .fr: "\(shown) sur \(total) lignes",
                                          .de: "\(shown) von \(total) Zeilen",
                                          .ja: "\(total) 行中 \(shown) 行",
                                          .zh: "\(total) 行中的 \(shown) 行",
                                          .pt: "\(shown) de \(total) linhas"])
    }

    static var aboutHelm: String { L("About Helm") }
    /// Not «Sidebar» any more: the same arrangement now orders the panel and
    /// the icon menu, so naming one of the three places it shows up was the
    /// kind of half-truth that sends somebody looking for a second control
    /// that does not exist.
    static var sidebarSections: String { L("Order and sections") }
    /// The one thing the sheet did not say. Every explanatory word in it was
    /// about dragging and sections; the column of switches carried none.
    static var moduleSwitchNote: String { L("A switch turns the module off everywhere in Helm.") }
    static var newSection: String { L("New section") }
    static var renameSection: String { L("Rename") }
    static var removeSection: String { L("Remove section") }
    static var useDefaultSectionName: String { L("Use the default name") }
    /// The empty section's own row. A section somebody just made has no modules
    /// and would otherwise be a heading followed by the next heading — nothing
    /// to aim a drop at.
    static var dragModuleHere: String { L("Drag a module here") }
    /// Marks a section the person made, as against one seeded from a category.
    static var yourSection: String { L("your section") }
    /// Puts the seeded arrangement back. Not `reset`, which in this app means
    /// every setting at once — one English key means one thing.
    static var restoreSections: String { L("Restore defaults") }
    static var sidebarSectionsNote: String {
        L("Drag to reorder. A module can go into any section, and a section you remove hands its modules to its neighbour.")
    }
    /// What the sheet is for, said once at the top of it. The block on the
    /// page carried this note in its edit mode, where it was only ever read by
    /// somebody who had already worked out what to do.
    static var sidebarComposerNote: String { sidebarSectionsNote }

    /// What is arranged, without opening anything. Counted from the
    /// arrangement rather than from the registry: a section somebody emptied
    /// is still a section they made.
    static func sidebarSummary(on: Int, of total: Int, sections: Int) -> String {
        // «9 modules in 4 sections» was `ModuleRegistry.all.count` rendered as
        // if it were state: `reconciled` guarantees every registered module
        // appears in exactly one section, so the number could not change. Turn
        // four modules off and the row still said nine. What a person wants to
        // know from a summary is what they have done, and how many are on is
        // the only number here that is theirs.
        func sectionWord(_ n: Int, _ one: String, _ many: String) -> String {
            n == 1 ? "\(n) \(one)" : "\(n) \(many)"
        }
        let en = "\(on) of \(total) on · " + sectionWord(sections, "section", "sections")
        return L(en,
          [.ru: "\(on) из \(total) включено · \(sections) "
                + Plural.russian(sections, "раздел", "раздела", "разделов"),
           .es: "\(on) de \(total) activados · " + sectionWord(sections, "sección", "secciones"),
           .fr: "\(on) sur \(total) activés · " + sectionWord(sections, "section", "sections"),
           .de: "\(on) von \(total) aktiv · " + sectionWord(sections, "Abschnitt", "Abschnitte"),
           .ja: "\(total) 個中 \(on) 個が有効 · \(sections) セクション",
           .zh: "\(total) 个中 \(on) 个已启用 · \(sections) 个分组",
           .pt: "\(on) de \(total) ativados · " + sectionWord(sections, "seção", "seções")])
    }

    static var moduleIcons: String { L("Module icons") }
    static var moduleIconsColour: String { L("Colour") }
    static var moduleIconsPlain: String { L("Plain") }
    static var iconShape: String { L("Icon shape") }
    static var iconSize: String { L("Icon size") }
    static var settings: String { L("Settings…") }
    static var panel: String { L("Panel") }
    static var utilities: String { L("Utilities") }

    // MARK: - The panel, arranged

    static var configurePanel: String { L("Edit panel") }
    static var editWidgets: String { L("Edit widgets") }
    static var showPanelEditButton: String { L("Show the edit button in the panel") }
    static var showSettingsButton: String { L("Show Settings button") }
    static var showQuitButton: String { L("Show Quit button") }
    /// Why any of these may be hidden at all: none of them is the only way to
    /// what it does.
    static var panelEditButtonNote: String {
        L("All three are also in the menu-bar icon’s right-click menu.")
    }
    static var panelSetup: String { L("Editing the panel") }
    static var removeWidget: String { L("Remove widget") }
    static var widgetSize: String { L("Widget size") }
    static var addWidget: String { L("Add widget") }
    static var chooseUtilities: String { L("Choose what is in the list") }
    static var tabLabels: String { L("Tab labels") }
    static var tabIcon: String { L("Icon") }
    static func tabLabelStyle(_ style: TabLabelStyle) -> String {
        switch style {
        case .text: L("Text")
        case .glyphAndText: L("Glyph and text")
        case .glyph: L("Glyph")
        }
    }
    static var newTab: String { L("New tab") }
    static var closeTab: String { L("Close tab") }
    static var tabLabel: String { L("Tab") }
    /// The name of the tab Helm seeds, read in the reader's language rather
    /// than stored in whichever language it was created in.
    static var mainTab: String { L("Main") }
    /// An unnamed tab is numbered.
    ///
    /// Every unnamed tab used to answer «Вкладка», so a strip of three read
    /// «Главная · Вкладка · Вкладка» — and the care `addingTab` takes to hand
    /// out a different glyph is invisible at the default label style, which is
    /// text.
    static func tabTitle(_ tab: PanelLayout.Tab, number: Int? = nil) -> String {
        if let name = tab.name { return name }
        if tab.seed == "main" { return mainTab }
        guard let number else { return tabLabel }
        return tabLabel + " " + "\(number)"
    }
    static var moduleIsOff: String { L("Module is off") }
    static var nothingOnThisTab: String { L("Nothing on this tab yet") }
    static var nothingOnThisTabHint: String { L("Press the pencil below to add a widget.") }
    /// The same sentence for a panel whose pencil has been switched off. It
    /// pointed at the button either way, so with the button hidden the hint
    /// named a control that was not on screen — and the door it did not
    /// mention is the one that cannot be closed.
    static var nothingOnThisTabHintNoButton: String {
        L("Right-click the menu-bar icon to add a widget.")
    }

    static var noModules: String { L("No modules enabled") }
    static var noModulesHint: String { L("Enable a module in Settings.") }
    static var whatsNew: String { L("What’s New") }

    static var author: String { L("Author") }
    /// A name, so it is written the way it is written — in Cyrillic where the
    /// reader has an alphabet for it, transliterated where they do not. Not a
    /// translation: nobody translates a name, they only spell it.
    static var authorName: String {
        L("Rostislav Strelnikov", [.ru: "Ростислав Стрельников"])
    }
    static var close: String { L("Close") }
    static var quit: String { L("Quit") }
    /// Explains the tint rule without naming a specific module (the icon is no
    /// longer ring-only, and module names are themselves localized).
    static var menuBarNote: String {
        L("The icon is white when idle and takes on the colour of whichever module is active.")
    }

    /// A section's heading: the name somebody typed, or its seed translated.
    ///
    /// Never the stored string on its own — a seeded section has no stored
    /// string precisely so that switching the app's language moves its heading
    /// with it.
    static func sectionTitle(_ section: SidebarLayout.Section) -> String {
        if let name = section.name { return name }
        guard let seed = section.seed, let category = ModuleCategory(rawValue: seed) else { return "" }
        return categoryName(category)
    }

    static func categoryName(_ c: ModuleCategory) -> String {
        switch c {
        case .power: return L("Power")
        case .network: return L("Network")
        case .clipboard: return L("Clipboard")
        case .window: return L("Window")
        case .media: return L("Media")
        case .files: return L("Files")
        case .appearance: return L("Appearance")
        case .utilities: return AppStr.utilities
        case .misc: return L("Miscellaneous")
        }
    }

    static var turnOn: String { L("Turn on") }
    static var cancel: String { L("Cancel") }
    static var resetSection: String {
        L("Reset")
    }
    static var resetAll: String {
        L("Reset all settings…")
    }
    static var resetNote: String {
        L("Helm returns to how it was just after installing. Access you granted in System Settings stays as it is.")
    }
    static var resetConfirmTitle: String {
        L("Reset all settings?")
    }
    static var resetConfirmBody: String {
        L("Each module’s saved data and the diagnostics log go to the Trash, where you can get them back. Your preferences — which modules are on, their order, your shortcuts — are forgotten for good. Helm restarts and greets you as it did the first time.")
    }
    static var resetConfirmAction: String {
        L("Reset and Restart")
    }
}
