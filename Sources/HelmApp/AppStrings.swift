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
    /// Section title inside that pane, for the menu-bar icon controls.
    static var menuBar: String { L("Menu Bar") }
    static var general: String { L("General") }
    static var launchAtLogin: String { L("Launch automatically at startup") }
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
    static var updateFailed: String { L("Update failed") }
    static var moduleOrderSection: String { L("Module order") }
    static var edit: String { L("Edit") }
    static var done: String { L("Done") }
    static var moduleOrderEditNote: String { L("Drag a row, or use the arrows.") }
    static var moduleOrderNote: String { L("Used by the panel, the sidebar, and the icon menu.") }
    static var permissionsChanged: String { L("Some permissions need granting again") }
    static var later: String { L("Later") }
    static var permissions: String { L("Permissions") }
    static var fullDiskAccess: String { L("Full Disk Access") }
    static var fullDiskAccessWhy: String { L("Needed to remove app containers and to read every folder when scanning the disk.") }
    static var fullDiskAccessAdHoc: String { L("Access is tied to one exact copy of Helm, so grant it again after every update: remove Helm with “−”, then add it with “+”.") }
    static var grant: String { L("Grant…") }
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
    static var diagnostics: String { L("Diagnostics") }
    static var writeLog: String { L("Write a log file") }
    static var logNoteDev: String { L("Dev builds always log. The file lives in Library/Logs/Helm.") }
    static var logNoteStable: String { L("Turn on before reporting a problem. The file lives in Library/Logs/Helm.") }
    static var revealLog: String { L("Show in Finder") }
    static var copyLog: String { L("Copy log") }
    static var clearLog: String { L("Clear") }
    static var whatsNewSummary: String { L("Everything that landed in Helm, newest first.") }
    static var settingsPaneSummary: String { L("Behaviour, module order, permissions, and diagnostics.") }
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

    static var openDiskAccessPane: String { L("Open disk access…") }
    static var openAccessibilityPane: String { L("Open accessibility…") }
    static var retry: String { L("Try again") }
    /// Shown when a release publishes no digest for its asset: the updater
    /// refuses to swap a bundle it cannot check, and hands the user the page.
    static var updateManualInstall: String { L("This release can’t be verified — install it from the release page.") }
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
    static var aboutHelm: String { L("About Helm") }
    static var iconShape: String { L("Icon shape") }
    static var iconSize: String { L("Icon size") }
    static var settings: String { L("Settings…") }
    static var panel: String { L("Panel") }
    static var showSettingsButton: String { L("Show Settings button") }
    static var showQuitButton: String { L("Show Quit button") }
    static var panelButtonsNote: String { L("Both actions are always available from the icon’s right-click menu.") }
    static var utilities: String { L("Utilities") }
    static var noModules: String { L("No modules enabled") }
    static var noModulesHint: String { L("Enable a module in Settings.") }
    static var whatsNew: String { L("What’s New") }
    static var close: String { L("Close") }
    static var quit: String { L("Quit") }
    /// Explains the tint rule without naming a specific module (the icon is no
    /// longer ring-only, and module names are themselves localized).
    static var menuBarNote: String {
        L("The icon is white when idle and takes on the colour of whichever module is active.")
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
        L("Every preference, every module's saved state and the diagnostics log go to the Trash. Helm restarts and greets you as it did the first time.")
    }
    static var resetConfirmAction: String {
        L("Reset and Restart")
    }
}
