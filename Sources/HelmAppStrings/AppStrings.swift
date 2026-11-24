import Foundation
import HelmRuntime
import HelmUI

/// Localized strings for the app shell (settings window chrome).
public enum AppStr {
    /// Rows that exist only on a dev build. Not translated cheaply — the point
    /// of the section is reading the app in another language, so its own labels
    /// have to be right in that language too.
    public static var developerSection: String { L(.developerSection) }
    public static var interfaceLanguage: String { L(.interfaceLanguage) }
    /// Named after the place the answer comes from, the way macOS names it
    /// there: «System Settings», «Настройки системы», and so on out of each
    /// language's own System Settings.
    public static var systemLanguage: String { L(.systemLanguage) }
    public static var interfaceLanguageNote: String { L(.interfaceLanguageNote) }
    /// The names of `HelmBarAppearance`'s two cases; "Liquid Glass" is
    /// macOS's own name for its material, spelled as System Settings spells it.
    public static var barAppearanceFlat: String { L(.barAppearanceFlat) }
    public static var barAppearanceLiquidGlass: String { L(.barAppearanceLiquidGlass) }
    /// The header row's three choices (`HelmHeaderChoices`): the row's name and its two answers, then the tabs' name and
    /// their three, then Always Collapse Search. Only the page header's is offered in General (`PageHeaderRow`); all three
    /// are in the row's right-click menu (`HeaderBarMenu`).
    public static var pageBar: String { L(.pageBar) }
    public static var pageBarWithIcon: String { L(.pageBarWithIcon) }
    public static var pageBarWithoutIcon: String { L(.pageBarWithoutIcon) }
    public static var tabLabels: String { L(.tabLabels) }
    public static var tabLabelsText: String { L(.tabLabelsText) }
    public static var tabLabelsIcons: String { L(.tabLabelsIcons) }
    public static var tabLabelsIconsAndText: String { L(.tabLabelsIconsAndText) }
    /// The row's right-click menu's fourth part, offered only where the page has a search (`HeaderBarMenu`).
    public static var alwaysCollapseSearch: String { L(.alwaysCollapseSearch) }
    /// The General row choosing between them (`BarAppearanceRow`).
    public static var barAppearanceTitle: String { L(.barAppearanceTitle) }

    /// The badge beside a module's name in its page header.
    ///
    /// «Active» is a module that is working. Its partner, `moduleIdle`, is the
    /// ordinary state.
    public static var moduleActive: String { L(.moduleActive) }
    /// The Tweaks entry's name and its one line; each tweak's own words are in its own target's catalog.
    public static var tweaksName: String { L(.tweaksName) }
    public static var tweaksSummary: String { L(.tweaksSummary) }
    /// The negative of `moduleActive`, so the two come as a pair.
    public static var moduleIdle: String { L(.moduleIdle) }

    /// The settings window's own title. Never drawn (the window hides its
    /// title bar text) and read aloud all the same: VoiceOver announces it on
    /// focus, and the Window menu lists it.
    ///
    /// "Helm Settings", the shape macOS uses for an app's own settings window,
    /// with each language's word for the pane taken from `settingsPane` so the
    /// title and the sidebar cannot disagree.
    public static var settingsWindowTitle: String { L(.settingsWindowTitle) }
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    public static var settingsPane: String { L(.settingsPane) }
    /// The first of the Settings page's three tabs. Not "General": that word is
    /// a glyph category's name, another meaning, and one English text means one thing.
    public static var settingsTabGeneral: String { L(.settingsTabGeneral) }
    /// The light/dark control, which macOS calls «Appearance», the same word as
    /// its section. A section and its first row reading identically hide the
    /// heading, so the row says what it chooses between.
    public static var lightOrDark: String { L(.lightOrDark) }
    public static var checking: String { L(.checking) }
    public static var upToDate: String { L(.upToDate) }
    /// Said to somebody running a build the channel has not published yet —
    /// which is a state worth naming rather than calling "up to date", because
    /// the person in it is usually the person testing something.
    public static func aheadOfChannel(_ newest: String) -> String {
        L(.aheadOfChannel(newest))
    }
    public static var download: String { L(.download) }
    public static var updateReady: String { L(.updateReady) }
    public static var updateAndRelaunch: String { L(.updateAndRelaunch) }
    public static var downloadingUpdate: String { L(.downloadingUpdate) }
    public static var installingUpdate: String { L(.installingUpdate) }
    /// Not `updateFailed`. A download that does not match what the release
    /// published is not a network hiccup, and Retry is the wrong offer: the
    /// honest next step is to look at the release itself.
    public static var updateDigestMismatch: String { L(.updateDigestMismatch) }
    public static var updateFailed: String { L(.updateFailed) }

    /// The banner for a release the daily check found with nobody watching.
    ///
    /// The title is `updateReady`, the card's own words rather than a second
    /// spelling of them: two sentences for one state drift apart.
    public static func updateFoundNotice(version: String,
                                  language: AppLanguage = AppLanguage.current) -> NoticeText {
        NoticeText(title: updateReady, body: updateFoundBody(version: version, language: language))
    }

    /// The version and the way to it, and no verb: nothing in Helm answers a
    /// click on a banner, so «install it» would describe something it cannot
    /// do. The path is spelled in each language exactly as that language's own
    /// `Settings` and `About Helm` are, since those are what the person reads
    /// when they go looking.
    static func updateFoundBody(version: String,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.updateFoundBody(version), language: language)
    }
    public static var permissionsChanged: String { L(.permissionsChanged) }
    public static var later: String { L(.later) }
    public static var permissions: String { L(.permissions) }
    static var fullDiskAccess: String { L(.fullDiskAccess) }
    public static var fullDiskAccessAdHoc: String { L(.fullDiskAccessAdHoc) }
    public static var permissionGranted: String { L(.permissionGranted) }
    /// Just «Show», the action (Russian «Показать», perfective, done once),
    /// never the standing choice a filter menu offers («Показывать»): one
    /// English key means one thing. The notice beside it already says what and
    /// how many, so the verb is all the button adds, and the shorter it is the
    /// more room the sentence has at the panel's width.
    public static var showPermissions: String { HelmWord.show }

    /// The one thing on the settings page that is wrong right now, said above
    /// everything else. Counted from `permissions` rather than `inertWithout`:
    /// the sidebar's triangle marks a module that can do nothing, and this line
    /// is about every module a missing grant reaches.
    ///
    /// Both clauses are verbless («2 permissions not granted · 7 modules»): the
    /// middle dot implies the rest, and every language must fit two lines
    /// beside a button at the panel's width.
    ///
    /// The panel says only how many grants are missing: beside a button on a
    /// narrow widget, two facts are a paragraph wrapped around a control. The
    /// settings page has the room and keeps both.
    public static func permissionsWithheld(count: Int,
                                    language: AppLanguage = AppLanguage.current) -> String {
        permissionsClause(count, language: language)
    }

    public static func permissionsWithheld(count: Int, modules: Int,
                                    language: AppLanguage = AppLanguage.current) -> String {
        let number = String(modules)
        let tail: LocalizedStringResource
        switch form(modules, language) {
        case .one: tail = .permissionsWithheldModulesOne(number)
        case .few: tail = .permissionsWithheldModulesFew(number)
        case .many: tail = .permissionsWithheldModulesMany(number)
        }
        return permissionsClause(count, language: language) + L(tail, language: language)
    }

    /// «2 permissions not granted», in the seven. Shared, so the panel's line
    /// and the page's longer one cannot come to disagree about the half they
    /// have in common.
    ///
    /// Split into named parts rather than one expression: the type-checker
    /// cannot take eight interpolated ternaries in one go.
    private static func permissionsClause(_ count: Int, language: AppLanguage) -> String {
        let number = String(count)
        switch form(count, language) {
        case .one: return L(.permissionsWithheldOne(number), language: language)
        case .few: return L(.permissionsWithheldFew(number), language: language)
        case .many: return L(.permissionsWithheldMany(number), language: language)
        }
    }

    /// `Plural.form`, except that these sentences write zero in the plural in
    /// French too («0 sections»), where the shared rule counts zero with the
    /// singular — a sentence that said otherwise would be a change of wording.
    private static func form(_ count: Int, _ language: AppLanguage) -> Plural.Form {
        language == .fr && count == 0 ? .many : Plural.form(count, language: language.rawValue)
    }

    /// The localized face of `PermissionNeed`; the runtime carries English.
    public static func permissionTitle(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return fullDiskAccess
        case .accessibility: return accessibility
        case .screenRecording: return screenRecording
        }
    }
    public static func permissionWhy(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess: return L(.fullDiskAccessWhy)
        // Names both things the grant buys, because one of them is that Helm can
        // see every keystroke in every application, and this is the caption a
        // person reads while deciding.
        case .accessibility: return L(.accessibilityWhy)
        case .screenRecording: return screenRecordingWhy
        }
    }
    static var accessibility: String { L(.accessibility) }
    /// The pane's own name on this macOS (`SCREENANDAUDIOCAPTURE` in the Security &
    /// Privacy extension's table): a person is looking for this word in a list.
    static var screenRecording: String { L(.screenRecording) }
    /// Says what the grant is *for*, and that Helm records nothing: the name is
    /// macOS's and it reads as a camera, which is what a person weighs the ask by.
    static var screenRecordingWhy: String { L(.screenRecordingWhy) }
    public static var writeLog: String { L(.writeLog) }
    public static func logNoteStableAt(_ folder: String) -> String { L(.logNoteStableAt(folder)) }
    public static var copyLog: String { L(.copyLog) }
    /// Next to the button whose whole purpose is pasting this into a bug report.
    /// `HelmLog` tags app and VPN names through `Redact` before writing; paths
    /// keep their folder and file names, and the home folder is written as `~`
    /// (`Redact.path`). That is a reason to press the button rather than a footnote.
    public static var logRedactionNote: String { L(.logRedactionNote) }

    public static func loginItemNeedsApproval(language: AppLanguage = AppLanguage.current) -> String {
        L(.loginItemNeedsApproval, language: language)
    }
    public static func loginItemRefused(language: AppLanguage = AppLanguage.current) -> String {
        L(.loginItemRefused, language: language)
    }

    /// Named the way macOS names the row, so the row Helm points at is the row
    /// that is found: on macOS 27 it is «Login Items & Extensions»
    /// (`LoginItems.appex`), and each language's spelling is that bundle's.
    public static var openLoginItems: String { L(.openLoginItems) }

    public static var modulesSection: String { L(.modulesSection) }
    /// The section that says Helm reads the disk with nobody at the desk.
    ///
    /// `ScanCoordinator` walks the volume for three modules while the Mac is
    /// idle, and `AppSettings.disabledScans` is the one switch. The heading names
    /// the act rather than the setting, because the act is what the person is
    /// being asked about.
    ///
    /// Each takes a language, so a test can ask about the seven this machine is
    /// not set to: the suite runs in whatever language this Mac is in, and a
    /// check gated on `.current` never exercises the language it was written for.
    public static func backgroundScansSection(language: AppLanguage = AppLanguage.current) -> String {
        L(.backgroundScansSection, language: language)
    }
    public static var backgroundScansSection: String { backgroundScansSection() }

    public static func backgroundScansNote(language: AppLanguage = AppLanguage.current) -> String {
        L(.backgroundScansNote, language: language)
    }
    public static var backgroundScansNote: String { backgroundScansNote() }

    /// The row's own caption. «Not yet» rather than «never»: a scan that has not
    /// run today is the ordinary state of a Mac somebody uses.
    public static func scanNeverRun(language: AppLanguage = AppLanguage.current) -> String {
        L(.scanNeverRun, language: language)
    }

    public static func scanLastRun(_ when: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.scanLastRun(when), language: language)
    }

    // MARK: - What a scan nobody watched turned up

    /// The banner three modules share, and the only thing a background scan
    /// ever says out loud.
    ///
    /// **A finding, never a claim of action.** «Duplicates / 7 items since the
    /// last check — 34,2 GB», not «cleaned» or «freed»: Helm walked the volume
    /// and this is what it saw. A test keeps the words that would claim an act
    /// out of all eight languages.
    ///
    /// Titled with the module's name, because an untitled notification is
    /// drawn as the app's name and «Helm» does not say which module is
    /// speaking. `ScanCoordinator` passes the name the sidebar shows.
    ///
    /// The count and the size are written in the sentence's language first and
    /// the catalog's template wraps them.
    public static func scanFindingNotice(module: String, finding: ScanNews.Finding,
                                  language: AppLanguage = AppLanguage.current) -> NoticeText {
        NoticeText(title: module,
                   body: scanFindingBody(finding, language: language))
    }

    /// The body alone, so the eight-language check reads the words rather than
    /// the assembly.
    public static func scanFindingBody(_ finding: ScanNews.Finding,
                                language: AppLanguage = AppLanguage.current) -> String {
        let code = language.rawValue
        return L(.scanFindingBody(Plural.items(finding.count, language: code),
                                  HelmBytes.string(finding.bytes, language: code)),
                 language: language)
    }

    /// The app's own claim about itself, so it names the machine it serves
    /// rather than one of the places it appears in (menu bar, panel, window).
    public static var tagline: String { L(.tagline) }
    public static var metricVersion: String { L(.metricVersion) }
    public static var metricBuild: String { L(.metricBuild) }
    public static var metricModules: String { L(.metricModules) }
    public static var checkNow: String { L(.checkNow) }
    public static var appearance: String { L(.appearance) }
    /// Why Helm wants a permission, named per permission. An unexplained
    /// request is one people deny.
    public static func permissionReason(_ need: PermissionNeed) -> String {
        switch need {
        case .fullDiskAccess:
            return L(.fullDiskAccessReason)
        case .accessibility:
            return L(.accessibilityReason)
        case .screenRecording:
            return L(.screenRecordingReason)
        }
    }

    public static func openPane(_ need: PermissionNeed) -> String {
        switch need {
        // One key per pane, shared with the Uninstaller's button, naming the
        // pane the way System Settings does.
        case .fullDiskAccess: return HelmWord.openFullDiskAccess
        case .accessibility: return L(.openAccessibilityPane)
        case .screenRecording: return L(.openScreenRecordingPane)
        }
    }
    public static var retry: String { L(.retry) }
    /// Shown when a release publishes no digest for its asset: the updater
    /// refuses to swap a bundle it cannot check, and hands the user the page.
    public static var updateManualInstall: String { L(.updateManualInstall) }
    public static var updateCannotReplaceItself: String { L(.updateCannotReplaceItself) }
    /// The last self-update did not finish; names the version still running.
    public static func updateNotInstalled(_ version: String) -> String { L(.updateNotInstalled(version)) }
    public static var updateCheckFailed: String { L(.updateCheckFailed) }
    public static func lastChecked(_ when: String) -> String { L(.lastChecked(when)) }
    public static var neverChecked: String { L(.neverChecked) }
    public static var updateChannel: String { L(.updateChannel) }
    /// Set in capitals like `betaBadge`: they sit side by side and a pair
    /// where one shouts and the other does not reads as two kinds of thing.
    public static var devBadge: String { L(.devBadge) }
    public static var betaBadge: String { L(.betaBadge) }

    /// The channel names, chosen by the channel rather than by a ternary at
    /// each call site, as `openPane(_:)` does for a permission: the About page
    /// asks for each in several places.
    public static func channelName(_ channel: UpdateCheck.Channel) -> String {
        switch channel {
        case .beta: return L(.channelBeta)
        case .dev: return L(.channelDev)
        }
    }

    public static func channelNote(_ channel: UpdateCheck.Channel) -> String {
        switch channel {
        case .beta: return L(.channelBetaNote)
        case .dev: return L(.channelDevNote)
        }
    }

    /// The sidebar's warning next to a module macOS is currently blocking.
    public static var moduleBlockedByPermission: String { L(.moduleBlockedByPermission) }

    /// The value a blocked module's row carries after its name, so it names no
    /// subject of its own.
    public static var moduleRowBlockedByPermission: String { L(.moduleRowBlockedByPermission) }

    /// The chevron beside the sidebar's foot row, and the row that takes its
    /// place when the sidebar is narrowed to its glyphs.
    public static var hideSidebar: String { L(.hideSidebar) }
    public static var showSidebar: String { L(.showSidebar) }

    // MARK: - The live log

    public static var logPane: String { L(.logPane) }
    public static var logLevelAll: String { L(.logLevelAll) }
    public static var logLevelWarnings: String { L(.logLevelWarnings) }
    public static var logLevelErrors: String { L(.logLevelErrors) }
    public static var logAllModules: String { L(.logAllModules) }
    /// Counted, because "1 modules" and „1 Module" are what a bare plural
    /// produces — and this menu shows 1 more often than any other number.
    public static func logSomeModules(_ n: Int) -> String {
        n == 1 ? L(.logModulesOne) : L(.logModules(String(n)))
    }
    /// The level of one line, **said** rather than shown.
    ///
    /// A row tells the levels apart with a wash and a glyph, nothing to a
    /// screen reader, so this word is the combined element's value.
    ///
    /// Singular, and deliberately not the filter's «Warnings» / «Errors»: one
    /// English text means one thing, and those two name a filter setting. Nil
    /// for an ordinary line, so nothing is read out to say nothing happened.
    public static func logLevelWord(_ level: LogLevel) -> String? {
        switch level {
        case .info: return nil
        case .warn: return L(.logLevelWarning)
        case .error: return L(.logLevelError)
        }
    }
    /// Stays pinned to the newest line while it is on. Off is what somebody
    /// wants the moment they see the line they were waiting for.
    public static var logFollow: String { L(.logFollow) }
    public static var logEmpty: String { L(.logEmpty) }
    public static var logNothingMatches: String { L(.logNothingMatches) }
    /// The footer's line count. The tail is the last thousand lines of a log that
    /// may hold more, so `total` is the tail and not the file: with no filter
    /// (`shown == total`) it says «Showing the last N lines», with one «Showing
    /// 17 of the last 46 lines». The noun follows `total`, the number the
    /// sentence is about; one key per form, as `logErrorCount` has.
    public static func logShowingLast(_ shown: Int, _ total: Int) -> String {
        let (a, b) = (Count(shown), Count(total))
        let form = Plural.form(total, language: AppLanguage.current.rawValue)
        if shown == total {
            switch form {
            case .one: return L(.logShowingLastOne(b))
            case .few: return L(.logShowingLastFew(b))
            case .many: return L(.logShowingLastMany(b))
            }
        }
        switch form {
        case .one: return L(.logShowingOfLastOne(a, b))
        case .few: return L(.logShowingOfLastFew(a, b))
        case .many: return L(.logShowingOfLastMany(a, b))
        }
    }

    public static var aboutHelm: String { L(.aboutHelm) }
    /// Not «Sidebar»: the same arrangement orders the panel and the icon menu
    /// too, and naming one place would send somebody looking for a second
    /// control that does not exist.
    public static var sidebarSections: String { L(.sidebarSections) }
    /// What the sheet's column of switches does.
    public static var moduleSwitchNote: String { L(.moduleSwitchNote) }
    public static var newSection: String { L(.newSection) }
    public static var removeSection: String { L(.removeSection) }
    public static var useDefaultSectionName: String { L(.useDefaultSectionName) }
    /// The empty section's own row. A section somebody just made has no modules
    /// and would otherwise be a heading followed by the next heading — nothing
    /// to aim a drop at.
    public static var dragModuleHere: String { L(.dragModuleHere) }
    /// Marks a section the person made, as against one seeded from a category.
    public static var yourSection: String { L(.yourSection) }
    /// Puts the seeded arrangement back. Not `reset`, which in this app means
    /// every setting at once — one English text means one thing.
    public static var restoreSections: String { L(.restoreSections) }
    /// What the sheet is for, said once at the top of it.
    public static var sidebarComposerNote: String { L(.sidebarComposerNote) }

    /// What is arranged, without opening anything. Counted from the
    /// arrangement rather than from the registry: a section somebody emptied
    /// is still a section they made.
    public static func sidebarSummary(on: Int, of total: Int, sections: Int) -> String {
        // How many are on, of how many: `reconciled` puts every registered
        // module in exactly one section, so the total alone never changes.
        let (a, b, c) = (String(on), String(total), String(sections))
        switch form(sections, AppLanguage.current) {
        case .one: return L(.sidebarSummaryOne(a, b, c))
        case .few: return L(.sidebarSummaryFew(a, b, c))
        case .many: return L(.sidebarSummaryMany(a, b, c))
        }
    }

    /// The two menu-bar rows say **menu bar** because nothing else in their
    /// section says which icon. `IconShapePicker`'s own default title stays: in
    /// Keep Awake a heading over the picker already names it.
    public static var menuBarIconShape: String { L(.menuBarIconShape) }
    public static var menuBarIconSize: String { L(.menuBarIconSize) }
    public static var settings: String { L(.settings) }
    public static var panel: String { L(.panel) }
    public static var utilities: String { HelmWord.utilities }

    // MARK: - The panel, arranged

    /// The name of the panel’s setup mode, in the **two** places that offer it:
    /// the footer’s pencil and the menu-bar icon’s right-click menu.
    ///
    /// One property, so the two cannot drift: the caption under the panel’s
    /// switch promises the buttons are also in that menu, by name.
    public static var editPanel: String { L(.editPanel) }
    public static var showSettingsButton: String { L(.showSettingsButton) }
    public static var showPanelEditButton: String { L(.showPanelEditButton) }
    public static var showQuitButton: String { L(.showQuitButton) }
    /// Why any of the three may be hidden at all: none of them is the only way
    /// to what it does. This caption is also one of exactly two places the app
    /// teaches the right-click menu, and Helm is `LSUIElement` — no Dock icon,
    /// no application menu — so those two places are the whole set of doors
    /// somebody can be told about.
    public static var panelFooterNote: String { L(.panelFooterNote) }
    public static var panelSetup: String { L(.panelSetup) }
    public static var removeWidget: String { L(.removeWidget) }
    public static var widgetSize: String { L(.widgetSize) }
    public static var addWidget: String { L(.addWidget) }
    public static var chooseUtilities: String { L(.chooseUtilities) }
    public static var tabIcon: String { L(.tabIcon) }
    public static var newTab: String { L(.newTab) }
    public static var closeTab: String { L(.closeTab) }
    public static var tabLabel: String { L(.tabLabel) }
    /// An unnamed tab is numbered: the default label style is text, so a
    /// different glyph alone would leave «Tab · Tab» indistinguishable.
    public static func tabTitle(_ tab: PanelLayout.Tab, number: Int? = nil) -> String {
        if let name = tab.name { return name }
        // The seeded tab's name is read in the reader's language rather than
        // stored in whichever language it was created in.
        if tab.seed == "main" { return L(.mainTab) }
        guard let number else { return tabLabel }
        return tabLabel + " " + "\(number)"
    }
    public static var moduleIsOff: String { L(.moduleIsOff) }
    public static var nothingOnThisTab: String { L(.nothingOnThisTab) }
    public static var nothingOnThisTabHint: String { L(.nothingOnThisTabHint) }
    /// The same sentence for a panel whose pencil has been switched off: it
    /// names the icon's menu, the door that cannot be closed, and not a button
    /// that is not on screen.
    public static var nothingOnThisTabHintNoButton: String { L(.nothingOnThisTabHintNoButton) }

    public static var noModules: String { L(.noModules) }
    public static var noModulesHint: String { L(.noModulesHint) }
    public static var whatsNew: String { L(.whatsNew) }

    public static var author: String { L(.author) }
    /// A name, so it is written the way it is written — in Cyrillic where the
    /// reader has an alphabet for it, transliterated where they do not. Not a
    /// translation: nobody translates a name, they only spell it.
    ///
    /// In the catalog like everything else, where the coverage check guards it.
    public static var authorName: String { L(.authorName) }
    public static var quit: String { L(.quit) }
    /// Explains the tint rule without naming a specific module.
    public static var menuBarNote: String { L(.menuBarNote) }

    /// A section's heading: the name somebody typed, or its seed translated.
    ///
    /// Never the stored string on its own — a seeded section has no stored
    /// string precisely so that switching the app's language moves its heading
    /// with it.
    public static func sectionTitle(_ section: SidebarLayout.Section) -> String {
        if let name = section.name { return name }
        guard let seed = section.seed, let category = ModuleCategory(rawValue: seed) else { return "" }
        return categoryName(category)
    }

    static func categoryName(_ c: ModuleCategory) -> String {
        switch c {
        case .power: return L(.categoryPower)
        case .network: return HelmWord.network
        case .clipboard: return HelmWord.clipboard
        case .window: return L(.categoryWindow)
        case .media: return HelmWord.media
        case .files: return L(.categoryFiles)
        case .appearance: return L(.appearance)
        case .utilities: return AppStr.utilities
        case .misc: return L(.categoryMiscellaneous)
        }
    }

    public static var resetSection: String { L(.resetSection) }
    public static var resetAll: String { L(.resetAll) }
    public static var resetNote: String { L(.resetNote) }
    public static var resetConfirmTitle: String { L(.resetConfirmTitle) }
    public static var resetConfirmBody: String { L(.resetConfirmBody) }
    public static var resetConfirmAction: String { L(.resetConfirmAction) }
}
