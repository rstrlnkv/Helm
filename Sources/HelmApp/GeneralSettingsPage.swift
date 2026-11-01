import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// The settings page the window opens on: the icon, the sidebar, what launches
/// at login, and the grants macOS is holding back.
///
/// Internal rather than `private` because the router that chooses it lives in
/// `SettingsWindow.swift`, and nothing outside `HelmApp` names it.
struct MenuBarSettingsView: View {
    /// Observed for the same reason the sidebar observes it: the consent rows
    /// below are filtered by which modules are on, and that is switched in the
    /// composer sheet this very page opens.
    @ObservedObject private var host = ModuleHost.shared
    @State private var composing = false
    /// The pickers' own currency is a rawValue, and the setting is typed — so
    /// the conversion happens here, at the one boundary, rather than the page
    /// carrying a second opinion about what an unrecognised value means.
    @State private var style = AppSettings.menuBarIconStyle.rawValue
    @State private var size = AppSettings.menuBarIconSize.rawValue
    /// The state macOS is in, not the answer the switch was given — and
    /// re-probed on activation like the permission rows below it.
    @State private var launchAtLogin: LoginItemState = LoginItem.current()
    @State private var appearance: AppAppearance = AppSettings.appearance
    @State private var language: String? = AppSettings.language?.rawValue
    @State private var showPanelEditButton = AppSettings.showPanelEditButton
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
    @State private var screenRecording: PermissionState = .granted
    @State private var confirmingReset = false
    /// Read back after every write rather than kept as the answer given: a
    /// broken seal answers "every scan is off" whatever was just pressed, and a
    /// switch that stays where the finger left it would be the screen telling
    /// the person something the coordinator does not believe.
    ///
    /// **Nil until the task below has read it, and never read on the way in.**
    /// This is the one setting on the page whose getter is sealed, so getting it
    /// reaches the login keychain — and on an ad-hoc build, where the cdhash
    /// changes with every build and no ACL an earlier one wrote still matches, a
    /// keychain read is a modal authorization dialog. As a `@State` initial value
    /// it was evaluated when SwiftUI installed the state, which is inside
    /// `SettingsWindow.init`, so the dialog stood in front of the settings window
    /// before the window had drawn anything (ARCHITECTURE.md § Sealed settings —
    /// the same fact that keeps `clamshellEnabled` unsealed, reached
    /// through a second door). Nil rather than an empty set: an empty off-list
    /// means every scan is on, and standing in for "not read yet" with it would
    /// show a whole-volume walk switched on to somebody who never said so.
    @State private var disabledScans: Set<String>?
    @State private var lastScanAt = AppSettings.lastScanAt
    private let adHocBuild = PermissionCheck.isAdHocSigned()

    /// The needed permissions macOS is currently withholding.
    private var withheldPermissions: [PermissionNeed] {
        PermissionSummary.withheld(accessibility: accessibility, fullDisk: diskAccess,
                                   screenRecording: screenRecording)
    }

    private var affectedModuleCount: Int {
        PermissionSummary.affected(by: withheldPermissions)
    }

    /// The permissions an enabled module actually uses, in table order.
    private var neededPermissions: [PermissionNeed] { PermissionSummary.needed() }

    /// The consent rows, from the list the coordinator itself loops over.
    ///
    /// Static and taking its three facts, so the screen's half of finding 4 is
    /// testable at all: what a person is asked about must be
    /// `ScanRunner.scannableModules` and not a second list written for the view
    /// — a scan added there and forgotten here would run with nobody asked.
    static func scanRows(enabled: Set<String>, disabledScans: Set<String>?,
                         lastRun: [String: Date]) -> [ScanConsent.Row]? {
        ScanConsent.rows(scannable: ScanRunner.scannableModules, enabled: enabled,
                         disabledScans: disabledScans, lastRun: lastRun)
    }

    private var scanRows: [ScanConsent.Row]? {
        Self.scanRows(enabled: host.enabledModuleIDs,
                      disabledScans: disabledScans, lastRun: lastScanAt)
    }

    var body: some View {
        // Over the scroll view, not above it: that is what gives the strip's
        // material something to blur and its rule something to be the edge of.
        // The inset the header costs is the header's own height —
        // `safeAreaInset` reserves it — so the first section starts exactly
        // under it.
        settingsPage
            .helmPageHeader(symbol: "gearshape", tint: ModuleTint.hostColour, title: AppStr.settingsPane)
    }

    /// One scan, named by its module and captioned with when it last came back.
    ///
    /// The date is `lastScanAt` — when a scan **finished**, with a report — and
    /// not the attempt beside it: "we started looking on Tuesday" is not an
    /// answer to "what has Helm read".
    private func scanRow(_ row: ScanConsent.Row) -> some View {
        let module = ModuleRegistry.descriptor(row.id)
        let caption = Self.scanCaption(lastRun: row.lastRun)
        let name = module?.moduleMetadata.name ?? row.id
        return HelmSettingRow(name, note: caption) {
            Toggle(name, isOn: Binding(get: { row.isOn },
                                       set: { setScan(row.id, on: $0) }))
                .labelsHidden()
        }
    }

    /// The line under a scan's name: when it last came back, «never», or —
    /// for a stamp with no age to draw — nothing at all.
    ///
    /// **Not `AppStr.scanNeverRun` for that third case.** The scan did run; a
    /// stamp this side of a second old, or one an NTP step has left ahead of
    /// the clock, is only a stamp `HelmDates.age` will not word. Saying «never»
    /// there would contradict the switch on the same row.
    private static func scanCaption(lastRun: Date?) -> String? {
        let language = AppLanguage.current
        guard let lastRun else { return AppStr.scanNeverRun(language: language) }
        return HelmDates.age(lastRun, language: language.rawValue)
            .map { AppStr.scanLastRun($0, language: language) }
    }

    /// Write, then read back — the reverse channel this switch would otherwise
    /// be missing. `disabledScans` refuses a value that is not Helm's own and
    /// answers "every scan off"; a screen that kept the answer it was given
    /// would be the last place that fact could be seen.
    private func setScan(_ id: String, on: Bool) {
        // There is no row to press until the off-list has been read, so this is
        // unreachable rather than a case with a policy — and the policy it would
        // otherwise need is "write a list you have not seen", which is how a
        // scan somebody switched off comes back on.
        guard let disabledScans else { return }
        AppSettings.disabledScans = ScanConsent.toggling(id, to: on, in: disabledScans)
        self.disabledScans = AppSettings.disabledScansIfWarm
    }

    /// Take the off-list if it is free, and pay for it elsewhere if it is not.
    ///
    /// **Every read of that setting on this page goes through here**, and
    /// `TheSettingsPageNeverWaitsForTheKeychainTests` reads this file to say so.
    /// The setting verifies a seal on every read, the key behind that seal comes
    /// from the login keychain, and on an ad-hoc build a keychain read is a
    /// modal authorization dialog — 19,09 s of it in
    /// `HelmApp_2026-08-19-235500_MacBook.hang`, taken on the thread that draws
    /// while the window could not answer a mouse-up.
    ///
    /// So the answer is asked for only when it costs nothing, and the round trip
    /// happens in a task the main actor is not standing on. Nil stays nil
    /// meanwhile: the rows read it as «not read yet» and draw nothing, which is
    /// the state the `Set<String>?` exists for.
    private func readTheOffList() {
        if let warm = AppSettings.disabledScansIfWarm {
            disabledScans = warm
            return
        }
        Task {
            await AppSettings.scanGuard.warmKey()
            disabledScans = AppSettings.disabledScansIfWarm
        }
    }

    private var settingsPage: some View {
        ScrollViewReader { scroll in
        ScrollView {
        VStack(alignment: .leading, spacing: HelmSpace.s7) {
            // Above everything, because it is the only thing on this page that
            // is *wrong right now* — and because the section that answers it
            // was 919 pt down a form in a 587 pt viewport, entirely below the
            // fold at the default window. The sidebar's triangle sends people
            // here; this is the first thing they see when they arrive.
            //
            // Only when something is withheld. A row saying everything is
            // granted is a row teaching people to ignore this space.
            //
            // A `HelmBanner`: it carries its own field, which a bare row of a
            // mark, a sentence and a button lacked — the one statement on this
            // page that says something is wrong looked like a row of settings.
            //
            // The circle rather than the banner's default triangle, because a
            // withheld grant is the one notice macOS itself draws and this is
            // the glyph it uses — the reason `HelmPermissionNote` gives.
            if !withheldPermissions.isEmpty {
                HelmBanner(AppStr.permissionsWithheld(count: withheldPermissions.count,
                                                      modules: affectedModuleCount),
                           symbol: "exclamationmark.circle.fill") {
                    // One withheld grant has one place to go, so go there.
                    // Several do not, and a button that picks one of them
                    // for you is a button that lies about what it opened.
                    if withheldPermissions.count == 1, let only = withheldPermissions.first {
                        Button(AppStr.grant) { only.openSettings() }
                            .controlSize(.small)
                    } else {
                        Button(AppStr.showPermissions) {
                            // A token, and the only bare `withAnimation`
                            // left in the app. The default is a spring
                            // nobody chose, and — the reason this one
                            // matters more than most — it does not stop
                            // under Reduce Motion, which is a 900 pt
                            // scroll flung past somebody who asked the
                            // machine not to do that.
                            withAnimation(HelmMotion.interface) {
                                scroll.scrollTo(Self.permissionsAnchor, anchor: .top)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }

            // What Helm does on its own.
            HelmSettingsSection(HelmSectionName.behaviour) {
                // The switch draws what macOS says, and the write answers with
                // what macOS says afterwards: `register()` can throw, and the
                // person can take the registration away in System Settings
                // while this window is open. Both used to leave the switch on.
                Toggle(AppStr.launchAtLogin,
                       isOn: Binding(get: { launchAtLogin.isOn },
                                     set: { launchAtLogin = LoginItem.setEnabled($0) }))
                if let note = AppStr.loginItemNote(launchAtLogin) {
                    HStack(alignment: .top, spacing: HelmSpace.s5) {
                        HelmSettingsNote(note)
                        Spacer(minLength: HelmSpace.s5)
                        // A door, not only a sentence: this state is finished
                        // by one press in a pane nobody navigates to by name.
                        if launchAtLogin == .needsApproval {
                            Button(AppStr.openLoginItems) { LoginItem.openSettings() }
                                .controlSize(.small)
                        }
                    }
                }
            }

            // What Helm does when nobody is at the desk, on the one page that
            // is about Helm rather than about a module. It is the app's largest
            // difference in kind from the tools it is compared to — three
            // modules reading the volume twice a day — and until this section
            // the only place it was ever said was the log.
            //
            // Only when there is a row: with all three of those modules
            // switched off the heading would stand over an empty card, which is
            // the gap the Permissions section documents just below.
            // Nil until the off-list has been read, which happens in the task
            // below rather than on the way in: nothing is claimed about a scan
            // whose switch nobody has looked up yet.
            if let scanRows, !scanRows.isEmpty {
                HelmSettingsSection(AppStr.backgroundScansSection) {
                    ForEach(scanRows, id: \.id) { row in scanRow(row) }
                    HelmSettingsNote(AppStr.backgroundScansNote)
                }
            }

            // Which modules there are and how they are grouped, which is not
            // behaviour — it was under that heading and did not belong to it.
            // The composing happens in a sheet.
            HelmSettingsSection(AppStr.modulesSection) {
                SidebarComposerRow(host: ModuleHost.shared, composing: $composing)
            }

            // Dev builds only. This is a tool for reading the app in a
            // language this Mac is not set to — eight of them, where the only
            // other way to see the seventh is to change the system preference
            // and log out. It is not a feature: macOS decides an app's
            // language, and a second answer in Helm's own settings would be
            // two places to look on a shipping build.
            if AppBuild.isDev {
                HelmSettingsSection(AppStr.developerSection) {
                    HelmSettingRow(AppStr.interfaceLanguage) {
                        Picker(AppStr.interfaceLanguage, selection: $language) {
                            Text(AppStr.systemLanguage).tag(String?.none)
                            ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                                Text(lang.endonym).tag(String?.some(lang.rawValue))
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .helmSectionMenu()
                        .onChange(of: language) { _, code in
                            AppSettings.language = code.flatMap(AppLanguage.init(rawValue:))
                        }
                    }
                    HelmSettingsNote(AppStr.interfaceLanguageNote)
                }
            }

            // Everything that decides how Helm looks, in one list.
            HelmSettingsSection(AppStr.appearance) {
                // Three pictures, the way System Settings asks the same
                // question. It was a pop-up of three accurate words that are
                // not what anybody is choosing between.
                AppearancePicker(selection: $appearance, title: AppStr.lightOrDark)
                    .onChange(of: appearance) { _, choice in AppSettings.appearance = choice }
                BarAppearanceRow()
                // The picker carries its own title for VoiceOver, hidden here
                // because the row beside it says it: a labelled control inside
                // a labelled row says it twice. Given the chosen size, so its
                // glyph is the icon as it will be drawn in the bar rather than
                // a sample at a fixed size.
                HelmSettingRow(AppStr.menuBarIconShape) {
                    IconShapePicker(selection: $style, title: AppStr.menuBarIconShape, size: size)
                        .labelsHidden()
                        .fixedSize()
                        .helmSectionMenu()
                        .onChange(of: style) { _, v in
                            AppSettings.menuBarIconStyle = MenuBarIconStyle(stored: v)
                        }
                }
                HelmSettingRow(AppStr.menuBarIconSize) {
                    IconSizePicker(selection: $size)
                        .onChange(of: size) { _, v in
                            AppSettings.menuBarIconSize = MenuBarIconSize(stored: v)
                        }
                }
                HelmSettingsNote(AppStr.menuBarNote)
            }

            // The panel keeps its own arrangement, so what is decided here is
            // how it is dressed: which of the three ways out are on it.
            HelmSettingsSection(AppStr.panel) {
                Toggle(AppStr.showSettingsButton, isOn: $showSettingsButton)
                    .onChange(of: showSettingsButton) { _, v in
                        AppSettings.showSettingsButton = v
                    }
                Toggle(AppStr.showPanelEditButton, isOn: $showPanelEditButton)
                    .onChange(of: showPanelEditButton) { _, v in
                        AppSettings.showPanelEditButton = v
                    }
                Toggle(AppStr.showQuitButton, isOn: $showQuitButton)
                    .onChange(of: showQuitButton) { _, v in
                        AppSettings.showQuitButton = v
                    }
                // Helm is `LSUIElement`: no Dock icon, no application menu, so
                // the footer's Settings button and this menu are the whole set
                // of doors — and this sentence is one of exactly two places the
                // app says the menu exists.
                HelmSettingsNote(AppStr.panelFooterNote)
            }

            // Only when there is one. `neededPermissions` filters to what the
            // *enabled* modules declare, so switching off the five that ask for
            // something emptied it — and a section with an empty body still
            // draws its heading over no card.
            if !neededPermissions.isEmpty {
                // Driven by the table, so a new permission shows up here
                // without anyone remembering to add a row — but only the ones
                // an enabled module actually uses. Listing all of them asked
                // someone who has switched Keyboard and Keep Awake off to grant
                // Accessibility for nothing, which is how people learn to grant
                // everything without reading. `PermissionAudit.run()` already
                // filters this way; the two disagreed.
                HelmSettingsSection(AppStr.permissions) {
                    ForEach(neededPermissions, id: \.self) { need in
                        let granted = need.state(accessibility: accessibility,
                                                 fullDisk: diskAccess,
                                                 screenRecording: screenRecording) == .granted
                        // The mark is the row's own: the circle changes what it
                        // says and the ring stays put, so the grant arriving is
                        // news rather than a cut (`helmSymbolSwap`).
                        HelmSettingRow(AppStr.permissionTitle(need),
                                       // Both, never one instead of the other: the
                                       // ad-hoc caveat used to replace the sentence
                                       // saying what the grant is for, and every build
                                       // anybody runs is ad-hoc — so the Accessibility
                                       // decision was made without the words "every
                                       // keystroke in every app" ever being shown.
                                       note: !granted && adHocBuild
                                           ? AppStr.permissionWhy(need) + "\n"
                                               + AppStr.fullDiskAccessAdHoc
                                           : AppStr.permissionWhy(need),
                                       mark: granted ? .holding : .attention,
                                       // Not granted is spoken by the Grant button beside it.
                                       markSpoken: granted ? AppStr.permissionGranted : nil) {
                            if !granted {
                                Button(AppStr.grant) { need.openSettings() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .id(Self.permissionsAnchor)
            }
            HelmSettingsSection(AppStr.resetSection) {
                // `HelmButtonStyle` inks `.destructive` itself; the role alone
                // drew as an ordinary link in a grouped Form.
                Button(AppStr.resetAll, role: .destructive) { confirmingReset = true }
                HelmSettingsNote(AppStr.resetNote)
            }
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s6)
        // Caps the column, centres it, and idles the page while its window is
        // off screen — the part of `helmSettingsColumn` a `Form` page called by
        // itself.
        .helmSettingsColumn()
        }
        .sheet(isPresented: $composing) {
            SidebarComposerSheet(host: ModuleHost.shared)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // A background scan runs when the person is away, which is exactly
            // the interval this window spends inactive: coming back is when
            // «hasn't run yet» can have stopped being true.
            lastScanAt = AppSettings.lastScanAt
            readTheOffList()
            // Login Items is one of the panes a person leaves this window for,
            // and the registration can be taken away there. The refusal Helm
            // remembers survives only while the system still agrees with it.
            launchAtLogin = LoginItem.current(refused: launchAtLogin == .refused)
        }
        // The grants through the trackers rather than through this page's own
        // `.task` and its `didBecomeActive`: the disk probe is four blocking file
        // reads, and both of those run on the thread that draws — the `.task`
        // continuation is drained by the very layout pass that builds the first
        // frame. The trackers do the same «once, and again when Helm comes back»
        // off the cooperative pool.
        .helmTracksFullDiskAccess($diskAccess)
        .helmTracksAccessibility($accessibility)
        .helmTracksScreenRecording($screenRecording)
        .task {
            // Not in the state's initial value, and not awaited here either.
            // A `.task` continuation is drained by the very layout pass that
            // draws the page, so awaiting the keychain inside it delayed the
            // first frame even with the round trip on another thread — measured
            // 2026-08-15. `readTheOffList` takes the answer if it is already in
            // hand and otherwise leaves it nil until a task it does not wait for
            // brings one.
            readTheOffList()
        }
        .confirmationDialog(AppStr.resetConfirmTitle, isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button(AppStr.resetConfirmAction, role: .destructive) { ResetEverything.run() }
            Button(AppStr.cancel, role: .cancel) {}
        } message: {
            Text(AppStr.resetConfirmBody)
        }
        }
    }

    /// What the counter line at the top scrolls to.
    private static let permissionsAnchor = "settings.permissions"
}

/// **General's mirror of the bar menu's Appearance section**: Flat or Liquid Glass, kept in step with the
/// menu's choice through `.helmBarAppearanceChanged`. Its own `@State`, so the page holds nothing for it. The
/// `guard` in `onChange` keeps a choice made in the menu from being written a second time.
struct BarAppearanceRow: View {
    @State private var choice = AppSettings.barAppearance

    var body: some View {
        HelmSettingRow(AppStr.barAppearanceTitle) {
            Picker(AppStr.barAppearanceTitle, selection: $choice) {
                Text(AppStr.barAppearanceFlat).tag(HelmBarAppearance.flat)
                Text(AppStr.barAppearanceLiquidGlass).tag(HelmBarAppearance.liquidGlass)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: choice) { _, new in
                guard new != AppSettings.barAppearance else { return }
                AppSettings.barAppearance = new
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .helmBarAppearanceChanged)) { _ in
            choice = AppSettings.barAppearance
        }
    }
}
