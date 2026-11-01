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
    /// Named after the place the answer comes from, and named the way macOS
    /// names it there — «System Settings» in English, «Настройки системы» in
    /// Russian, and so on out of each language's own System Settings. «Same as
    /// the Mac» described a relationship; this points at the pane.
    public static var systemLanguage: String { L(.systemLanguage) }
    /// It used to end «windows already open keep the language they were drawn
    /// in», which was true of the first attempt and is not true now: both the
    /// settings window and the panel take a new identity and are rebuilt. A
    /// note describing a limitation that has been removed is worse than none.
    public static var interfaceLanguageNote: String {
        L(.interfaceLanguageNote)
    }
    /// The names of `HelmBarAppearance`'s two cases; "Liquid Glass" is
    /// macOS's own name for its material, spelled as System Settings spells it.
    public static var barAppearanceFlat: String { L(.barAppearanceFlat) }
    public static var barAppearanceLiquidGlass: String { L(.barAppearanceLiquidGlass) }
    /// The General row choosing between them (`BarAppearanceRow`).
    public static var barAppearanceTitle: String { L(.barAppearanceTitle) }

    /// The badge beside a module's name in its page header.
    ///
    /// «Active» is a module that is working. Its partner, `moduleIdle`, is the
    /// ordinary state, which nothing in the app had a word for before this badge
    /// drew it.
    public static var moduleActive: String { L(.moduleActive) }
    /// The negative of `moduleActive`, so the two come as a pair. Two English
    /// spellings of one idea had already collapsed into one word in German and
    /// Japanese, which is the translators noticing what the source had not.
    public static var moduleIdle: String { L(.moduleIdle) }

    /// The settings window's own title. Never drawn — the window hides its
    /// title bar text — and read aloud all the same: VoiceOver announces it on
    /// focus, and the Window menu lists it. It was the one user-visible English
    /// string in the app that was not behind `L()`, which is exactly the kind of
    /// string that keeps being the last one.
    ///
    /// "Helm Settings", the shape macOS uses for an app's own settings window,
    /// with each language's word for the pane taken from `settingsPane` so the
    /// title and the sidebar cannot disagree.
    public static var settingsWindowTitle: String {
        L(.settingsWindowTitle)
    }
    /// Sidebar entry for the app-level pane (login item, panel layout, menu-bar icon).
    public static var settingsPane: String { L(.settingsPane) }
    /// The first of the Settings page's three tabs. Not "General": that word is
    /// a glyph category's name, another meaning, and one English text means one thing.
    public static var settingsTabGeneral: String { L(.settingsTabGeneral) }
    /// The light/dark control, which macOS itself calls «Appearance» — the same
    /// word as the section it now sits in. A section and its first row reading
    /// identically is how a person stops seeing the heading at all, so the row
    /// says what it chooses between.
    public static var lightOrDark: String { L(.lightOrDark) }
    public static var launchAtLogin: String { HelmWord.openHelmAtLogin }
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
    public static var updateDigestMismatch: String {
        L(.updateDigestMismatch)
    }
    public static var updateFailed: String { L(.updateFailed) }

    /// The banner for a release the daily check found with nobody watching.
    ///
    /// The title is `updateReady`, the card's own words rather than a second
    /// spelling of them: two sentences for one state is how the app came to say
    /// «Configure panel» about a button that says «Edit panel».
    public static func updateFoundNotice(version: String,
                                  language: AppLanguage = AppLanguage.current) -> NoticeText {
        NoticeText(title: updateReady, body: updateFoundBody(version: version, language: language))
    }

    /// **It is the version and the way to it, and no verb.** A banner is not a
    /// button: nothing in Helm answers a click on one, so a sentence that says
    /// «install it» describes something the banner itself cannot do. The path is
    /// spelled in each language exactly as that language's own `Settings` and
    /// `About Helm` are spelled, since those two are what the person will be
    /// reading when they go looking.
    static func updateFoundBody(version: String,
                                language: AppLanguage = AppLanguage.current) -> String {
        L(.updateFoundBody(version), language: language)
    }
    public static var edit: String { HelmWord.edit }
    public static var done: String { HelmWord.done }
    public static var permissionsChanged: String { L(.permissionsChanged) }
    public static var later: String { L(.later) }
    public static var permissions: String { L(.permissions) }
    static var fullDiskAccess: String { L(.fullDiskAccess) }
    static var fullDiskAccessWhy: String { L(.fullDiskAccessWhy) }
    public static var fullDiskAccessAdHoc: String { L(.fullDiskAccessAdHoc) }
    public static var grant: String { HelmWord.grant }
    public static var permissionGranted: String { L(.permissionGranted) }
    /// Beside `grant`, and never a bare "Show": Login Items already labels its
    /// filter menu that way, where the word is a standing choice rather than an
    /// action — Russian tells the two apart («Показывать» against «Показать»)
    /// and one key cannot hold both.
    ///
    /// **Just «Show».** It was `Show permissions`, then `Show all`, and both
    /// were measured: at the panel's width the German `Show permissions` button
    /// took 154 pt and left the notice four lines, and `Show all` left Russian
    /// three. The count beside it already says permissions and the notice says
    /// how many, so the verb is the whole of what the button has to add — and
    /// the shorter it is, the more room the sentence beside it has.
    ///
    /// The word had to be taken back off Leftovers' filter menu, which used it
    /// for the *other* sense: that one is «Показывать: всё», imperfective, a
    /// standing choice; this is «Показать», perfective, done once. One English
    /// key means one thing, so the filter is `Filter` now — which is also what
    /// it is, beside a filter glyph.
    ///
    /// Takes a language, so a test can ask about the seven this machine is not
    /// set to. The suite runs in whatever language this Mac is in, and a check
    /// gated on `.current` never exercises the language it was written for.
    public static func showPermissions(language: AppLanguage = AppLanguage.current) -> String {
        HelmWord.show(language: language)
    }
    public static var showPermissions: String { showPermissions() }

    /// The one thing on the settings page that is wrong right now, said above
    /// everything else. Counted from `permissions` rather than `inertWithout`:
    /// the sidebar's triangle marks a module that can do nothing, and this line
    /// is about every module a missing grant reaches.
    ///
    /// **Both clauses lost their verb, and Russian lost another word.**
    /// Measured on the real row at the panel's 320 pt, one line being 44 pt and
    /// each further line 14: «… · 7 modules affected» put Russian, French and
    /// Portuguese on **three** lines beside a button that is on one. The
    /// trailing participle is what the middle dot already implies — «2
    /// permissions not granted · 7 modules» says the same thing — and that
    /// brought French and Portuguese to two. Russian needed one word more,
    /// because «Показать все» is the widest of the eight buttons at 96 pt:
    /// «Не выдано» → «Нет». All eight are two lines or fewer now, and Chinese
    /// is one.
    /// **The panel says only how many grants are missing.** The module count
    /// is a second fact, and the widget is 320 pt wide with a button on the
    /// same line: two facts there is a paragraph wrapped around a control, at
    /// the top of the first thing anybody opens when something is wrong. The
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
    /// Split into named parts rather than written as one expression: the
    /// concatenation of eight interpolated ternaries is more than the
    /// type-checker will take in one go, and «try breaking up the expression»
    /// is not a hint worth rediscovering.
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
        case .fullDiskAccess: return fullDiskAccessWhy
        case .accessibility: return accessibilityWhy
        case .screenRecording: return screenRecordingWhy
        }
    }
    static var accessibility: String { L(.accessibility) }
    /// The pane's own name on this macOS (`SCREENANDAUDIOCAPTURE` in the Security &
    /// Privacy extension's table), which replaced «Screen Recording» — a person is
    /// looking for this word in a list, and the old one is not in it.
    static var screenRecording: String { L(.screenRecording) }
    /// Says what the grant is *for*, and that Helm records nothing: the name is
    /// macOS's and it reads as a camera, which is what a person weighs the ask by.
    static var screenRecordingWhy: String {
        L(.screenRecordingWhy)
    }
    /// Names both things the grant buys, because one of them is that Helm can
    /// see every keystroke in every application. The lapsed-grant alert
    /// (`permissionReason`) already said so; this is the caption a person reads
    /// *while deciding*, and it described a mouse jiggle.
    static var accessibilityWhy: String { L(.accessibilityWhy) }
    public static var writeLog: String { L(.writeLog) }
    public static var logNoteStable: String { L(.logNoteStable) }
    public static var revealLog: String { HelmWord.showInFinder }
    public static var copyLog: String { L(.copyLog) }
    /// Next to the button whose whole purpose is pasting this into a bug report.
    /// `HelmLog` puts every app name, VPN name and path through `Redact` before
    /// writing, and that is a reason to press the button rather than a footnote.
    public static var logRedactionNote: String {
        L(.logRedactionNote)
    }
    public static var clearLog: String { HelmWord.clear }

    public static func loginItemNeedsApproval(language: AppLanguage = AppLanguage.current) -> String {
        L(.loginItemNeedsApproval, language: language)
    }
    public static func loginItemRefused(language: AppLanguage = AppLanguage.current) -> String {
        L(.loginItemRefused, language: language)
    }

    /// Named the way macOS names the row, so the row Helm points at is the row
    /// that is found: on macOS 27 it is «Login Items & Extensions»
    /// (`LoginItems.appex`), and each language's spelling is that bundle's.
    public static func openLoginItems(language: AppLanguage = AppLanguage.current) -> String {
        L(.openLoginItems, language: language)
    }
    public static var openLoginItems: String { openLoginItems() }

    public static var modulesSection: String { L(.modulesSection) }
    /// The section that says Helm reads the disk with nobody at the desk.
    ///
    /// It had no screen at all: `ScanCoordinator` walks the volume for three
    /// modules while the Mac is idle, and `AppSettings.disabledScans` — the one
    /// switch — was written by nothing in `Sources/`. The heading names the act
    /// rather than the setting, because the setting is not what the person is
    /// being asked about.
    ///
    /// Each takes a language, for the reason `showPermissions` does: the suite
    /// runs in this Mac's own, so a check gated on `.current` never reads the
    /// other seven.
    public static func backgroundScansSection(language: AppLanguage = AppLanguage.current) -> String {
        L(.backgroundScansSection, language: language)
    }
    public static var backgroundScansSection: String { backgroundScansSection() }

    public static func backgroundScansNote(language: AppLanguage = AppLanguage.current) -> String {
        L(.backgroundScansNote,
          language: language)
    }
    public static var backgroundScansNote: String { backgroundScansNote() }

    /// The row's own caption. «Not yet» rather than «never»: a scan that has not
    /// run today is the ordinary state of a Mac somebody uses.
    public static func scanNeverRun(language: AppLanguage = AppLanguage.current) -> String {
        L(.scanNeverRun, language: language)
    }
    public static var scanNeverRun: String { scanNeverRun() }

    public static func scanLastRun(_ when: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L(.scanLastRun(when), language: language)
    }

    // MARK: - What a scan nobody watched turned up

    /// The banner three modules share, and the only thing a background scan
    /// ever says out loud.
    ///
    /// **A finding, never a claim of action.** «Duplicates / 7 items since the
    /// last check — 34,2 GB» — not «cleaned», and not «freed». Helm did not
    /// clean anything: it walked the volume while the Mac was idle and this is
    /// what it saw. A banner claiming an act the person did not ask for is the
    /// one thing a channel like this cannot come back from, so the words that
    /// would claim one are held out of all eight languages by a test rather than
    /// by this paragraph.
    ///
    /// Titled with the module's name, because a notification with no title is
    /// drawn as the app's name and a body, and «Helm» does not say which of ten
    /// modules is speaking. The name comes from the registry rather than being
    /// written again here — `ScanCoordinator` passes what the sidebar shows.
    ///
    /// The count and the size are written in the sentence's language first and
    /// the catalog's template wraps them.
    public static func scanFindingNotice(module: String, finding: ScanNews.Finding,
                                  language: AppLanguage = AppLanguage.current) -> NoticeText {
        NoticeText(title: module,
                   body: scanFindingBody(finding, language: language))
    }

    /// The body alone, so a test can read the sentence in a language without
    /// having to build the pair around it — and so the eight-language check is
    /// of the words rather than of the assembly.
    public static func scanFindingBody(_ finding: ScanNews.Finding,
                                language: AppLanguage = AppLanguage.current) -> String {
        let code = language.rawValue
        return L(.scanFindingBody(Plural.items(finding.count, language: code),
                                  HelmBytes.string(finding.bytes, language: code)),
                 language: language)
    }

    /// «in your menu bar» was false and had been since the panel: Helm is also
    /// a panel, a settings window and a sidebar the person arranges. A tagline
    /// under the wordmark is the app's own claim about itself, so it names the
    /// machine it serves rather than one of the places it appears in.
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
        case .fullDiskAccess: return openDiskAccessPane
        case .accessibility: return openAccessibilityPane
        case .screenRecording: return openScreenRecordingPane
        }
    }

    /// The Uninstaller's button and this one open the same pane and said two
    /// different things — and the seven translations of both were identical,
    /// which is the proof they were one concept with two English spellings.
    /// One key each, naming the pane the way System Settings does.
    static var openDiskAccessPane: String { HelmWord.openFullDiskAccess }
    static var openAccessibilityPane: String { L(.openAccessibilityPane) }
    static var openScreenRecordingPane: String { L(.openScreenRecordingPane) }
    public static var retry: String { L(.retry) }
    /// Shown when a release publishes no digest for its asset: the updater
    /// refuses to swap a bundle it cannot check, and hands the user the page.
    public static var updateManualInstall: String { L(.updateManualInstall) }
    public static var updateCannotReplaceItself: String { L(.updateCannotReplaceItself) }
    public static var updateCheckFailed: String { L(.updateCheckFailed) }
    public static func lastChecked(_ when: String) -> String { L(.lastChecked(when)) }
    public static var neverChecked: String { L(.neverChecked) }
    public static var updateChannel: String { L(.updateChannel) }
    static var channelBeta: String { L(.channelBeta) }
    static var channelDev: String { L(.channelDev) }
    static var channelBetaNote: String { L(.channelBetaNote) }
    /// Set in capitals like `betaBadge`: they sit side by side and a pair
    /// where one shouts and the other does not reads as two kinds of thing.
    public static var devBadge: String { L(.devBadge) }
    public static var betaBadge: String { L(.betaBadge) }
    static var channelDevNote: String { L(.channelDevNote) }

    /// The two above, chosen by the channel rather than by a ternary at the
    /// call site — the same shape `openPane(_:)` takes for a permission. The
    /// About page asked for each of these three times over: the pill's label,
    /// the pill's tooltip, the note under the row, and the badge's tooltip.
    public static func channelName(_ channel: UpdateCheck.Channel) -> String {
        switch channel {
        case .beta: return channelBeta
        case .dev: return channelDev
        }
    }

    public static func channelNote(_ channel: UpdateCheck.Channel) -> String {
        switch channel {
        case .beta: return channelBetaNote
        case .dev: return channelDevNote
        }
    }

    /// The sidebar's warning next to a module macOS is currently blocking.
    public static var moduleBlockedByPermission: String {
        L(.moduleBlockedByPermission)
    }

    /// The value a blocked module's row carries after its name, so it names no
    /// subject of its own.
    public static var moduleRowBlockedByPermission: String {
        L(.moduleRowBlockedByPermission)
    }

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
    /// A row tells info from warn from error with a 6 % wash and a 3 pt rule:
    /// nothing at all to a screen reader, which was handed the row as one
    /// combined element whose value never named the level, and a hue-only
    /// distinction between the two that matter for everybody else.
    ///
    /// Singular, and deliberately not the filter's «Warnings» / «Errors»: one
    /// English text means one thing, and those two name a *filter setting*. Nil
    /// for an ordinary line — a value on every row would be a word read out
    /// nine hundred times to say nothing happened.
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
    /// **This sentence is owed a rewrite, and it is a localizer's.** It was
    /// written when `total` was everything this process had logged, so «45 of 45
    /// lines» was true twice over. The tail is seeded from the file now, so
    /// `total` is the last thousand lines of a log that may hold five thousand,
    /// and the same words read as «the log is 1 000 lines long». Eight languages
    /// say it, and the fix is the English text — «Showing the last N lines», or a
    /// count of the file — not seven corrections underneath the wrong one.
    public static func logCount(_ shown: Int, _ total: Int) -> String {
        L(.logCount(String(shown), String(total)))
    }

    public static var aboutHelm: String { L(.aboutHelm) }
    /// Not «Sidebar» any more: the same arrangement now orders the panel and
    /// the icon menu, so naming one of the three places it shows up was the
    /// kind of half-truth that sends somebody looking for a second control
    /// that does not exist.
    public static var sidebarSections: String { L(.sidebarSections) }
    /// The one thing the sheet did not say. Every explanatory word in it was
    /// about dragging and sections; the column of switches carried none.
    public static var moduleSwitchNote: String { L(.moduleSwitchNote) }
    public static var newSection: String { L(.newSection) }
    public static var renameSection: String { HelmWord.rename }
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
    /// What the sheet is for, said once at the top of it. The block on the
    /// page carried this note in its edit mode, where it was only ever read by
    /// somebody who had already worked out what to do.
    ///
    /// One name. It was two — `sidebarSectionsNote` holding the sentence and
    /// this forwarding to it — with nothing but the sheet calling either. A
    /// rename that stopped halfway leaves the old name reachable, and the next
    /// person has to work out which of the two is the one to change.
    public static var sidebarComposerNote: String {
        L(.sidebarComposerNote)
    }

    /// What is arranged, without opening anything. Counted from the
    /// arrangement rather than from the registry: a section somebody emptied
    /// is still a section they made.
    public static func sidebarSummary(on: Int, of total: Int, sections: Int) -> String {
        // «9 modules in 4 sections» was `ModuleRegistry.all.count` rendered as
        // if it were state: `reconciled` guarantees every registered module
        // appears in exactly one section, so the number could not change. Turn
        // four modules off and the row still said nine. What a person wants to
        // know from a summary is what they have done, and how many are on is
        // the only number here that is theirs.
        let (a, b, c) = (String(on), String(total), String(sections))
        switch form(sections, AppLanguage.current) {
        case .one: return L(.sidebarSummaryOne(a, b, c))
        case .few: return L(.sidebarSummaryFew(a, b, c))
        case .many: return L(.sidebarSummaryMany(a, b, c))
        }
    }

    /// The two menu-bar rows, and they say **menu bar** because nothing else in
    /// their section does. They sat under «Appearance» beside the theme as
    /// «Icon shape» and «Icon size», with no word anywhere on the page saying
    /// which icon — and the app's own term for it is one Keep Awake already uses
    /// as a heading over the same picker. `IconShapePicker`'s own
    /// default title stays as it is: it is titled by that heading there.
    public static var menuBarIconShape: String { L(.menuBarIconShape) }
    public static var menuBarIconSize: String { L(.menuBarIconSize) }
    public static var settings: String { L(.settings) }
    public static var panel: String { L(.panel) }
    public static var utilities: String { L(.utilities) }

    // MARK: - The panel, arranged

    /// The name of the panel’s setup mode, in the **two** places that offer it:
    /// the footer’s pencil and the menu-bar icon’s right-click menu.
    ///
    /// One property because they were two — «Edit panel» on the button and «Edit
    /// widgets» in the menu, for the same mode, in eight languages each. The
    /// caption under the panel’s switch tells people the buttons are also in
    /// that menu, which is a promise about a name and was false about one of
    /// them. Read from one place it cannot drift, which is the fix
    /// `VPNStr.secretNeedsAPress` is built the same way for.
    public static var editPanel: String { L(.editPanel) }
    public static var showSettingsButton: String { L(.showSettingsButton) }
    public static var showPanelEditButton: String { L(.showPanelEditButton) }
    public static var showQuitButton: String { L(.showQuitButton) }
    /// Why any of the three may be hidden at all: none of them is the only way
    /// to what it does. This caption is also one of exactly two places the app
    /// teaches the right-click menu, and Helm is `LSUIElement` — no Dock icon,
    /// no application menu — so those two places are the whole set of doors
    /// somebody can be told about.
    public static var panelFooterNote: String {
        L(.panelFooterNote)
    }
    public static var panelSetup: String { L(.panelSetup) }
    public static var removeWidget: String { L(.removeWidget) }
    public static var widgetSize: String { L(.widgetSize) }
    public static var addWidget: String { L(.addWidget) }
    public static var chooseUtilities: String { L(.chooseUtilities) }
    public static var tabIcon: String { L(.tabIcon) }
    public static var newTab: String { L(.newTab) }
    public static var closeTab: String { L(.closeTab) }
    public static var tabLabel: String { L(.tabLabel) }
    /// The name of the tab Helm seeds, read in the reader's language rather
    /// than stored in whichever language it was created in.
    static var mainTab: String { L(.mainTab) }
    /// An unnamed tab is numbered.
    ///
    /// Every unnamed tab used to answer «Вкладка», so a strip of three read
    /// «Главная · Вкладка · Вкладка» — and the care `addingTab` takes to hand
    /// out a different glyph is invisible at the default label style, which is
    /// text.
    public static func tabTitle(_ tab: PanelLayout.Tab, number: Int? = nil) -> String {
        if let name = tab.name { return name }
        if tab.seed == "main" { return mainTab }
        guard let number else { return tabLabel }
        return tabLabel + " " + "\(number)"
    }
    public static var moduleIsOff: String { L(.moduleIsOff) }
    public static var nothingOnThisTab: String { L(.nothingOnThisTab) }
    public static var nothingOnThisTabHint: String { L(.nothingOnThisTabHint) }
    /// The same sentence for a panel whose pencil has been switched off. It
    /// pointed at the button either way, so with the button hidden the hint
    /// named a control that was not on screen — and the door it did not
    /// mention is the one that cannot be closed.
    public static var nothingOnThisTabHintNoButton: String {
        L(.nothingOnThisTabHintNoButton)
    }

    public static var noModules: String { L(.noModules) }
    public static var noModulesHint: String { L(.noModulesHint) }
    public static var whatsNew: String { L(.whatsNew) }

    public static var author: String { L(.author) }
    /// A name, so it is written the way it is written — in Cyrillic where the
    /// reader has an alphabet for it, transliterated where they do not. Not a
    /// translation: nobody translates a name, they only spell it.
    ///
    /// In the catalog like everything else. It was an inline table with
    /// one row in it, which is six languages absent from a table nothing
    /// guards — the exact shape the changelog's twenty tables had when one of
    /// them shipped English to six languages.
    public static var authorName: String { L(.authorName) }
    public static var close: String { HelmWord.close }
    public static var quit: String { L(.quit) }
    /// Explains the tint rule without naming a specific module (the icon is no
    /// longer ring-only, and module names are themselves localized).
    public static var menuBarNote: String {
        L(.menuBarNote)
    }

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

    public static var turnOn: String { HelmWord.turnOn }
    public static var cancel: String { HelmWord.cancel }
    public static var resetSection: String {
        L(.resetSection)
    }
    public static var resetAll: String {
        L(.resetAll)
    }
    public static var resetNote: String {
        L(.resetNote)
    }
    public static var resetConfirmTitle: String {
        L(.resetConfirmTitle)
    }
    public static var resetConfirmBody: String {
        L(.resetConfirmBody)
    }
    public static var resetConfirmAction: String {
        L(.resetConfirmAction)
    }
}
