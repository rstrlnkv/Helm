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
    @State private var footerButtons = Dictionary(
        uniqueKeysWithValues: PanelFooterSetting.Button.allCases.map { ($0, AppSettings.shows($0)) })
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
    /// reaches the login keychain, and on an ad-hoc build a keychain read is a
    /// modal authorization dialog. A `@State` initial value is evaluated inside
    /// `SettingsWindow.init`, so the dialog would stand in front of a window
    /// that has drawn nothing (Architecture/StoredSettings.md § Sealed settings),
    /// the same fact that keeps `clamshellEnabled` unsealed. Nil rather than an
    /// empty set: an empty off-list means every scan is on, and standing in for
    /// "not read yet" with it would show a whole-volume walk switched on to
    /// somebody who never said so.
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
    /// Static and taking its three facts, so it can be tested: what a person is
    /// asked about must be `ScanRunner.scannableModules` and not a second list
    /// written for the view, or a scan added there would run with nobody asked.
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
        // Over the scroll view, not above it, so the strip's material has
        // something to blur; `safeAreaInset` reserves the header's height.
        settingsPage
            .helmPageHeader(symbol: "gearshape", tint: ModuleTint.hostColour, title: AppStr.settingsPane)
    }

    /// The switch's label, by the button it governs.
    private func footerLabel(_ button: PanelFooterSetting.Button) -> String {
        switch button {
        case .settings: AppStr.showSettingsButton
        case .edit: AppStr.showPanelEditButton
        case .quit: AppStr.showQuitButton
        }
    }

    /// One scan, named by its module and captioned with when it last came back.
    ///
    /// The date is `lastScanAt`, when a scan **finished** with a report, not
    /// the attempt: the caption answers "what has Helm read".
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

    /// Write, then read back, for the reason `disabledScans` above gives.
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
    /// **Every read of that setting on this page goes through here.** The
    /// setting verifies a seal on every read, the key comes from the login
    /// keychain, and on an ad-hoc build a keychain read is a modal dialog that
    /// would hang the thread that draws. So the answer is asked for only when
    /// it costs nothing, and the round trip happens in a task the main actor is
    /// not standing on. Nil stays nil meanwhile: the rows draw nothing.
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
            // is wrong right now, and the section that answers it is below the
            // fold. The sidebar's triangle sends people here.
            //
            // Only when something is withheld: a row saying everything is
            // granted teaches people to ignore this space.
            //
            // A `HelmBanner`, whose field sets it apart from the rows of settings.
            // The circle rather than the banner's default triangle, for the
            // reason `HelmPermissionNote` gives.
            if !withheldPermissions.isEmpty {
                HelmBanner(AppStr.permissionsWithheld(count: withheldPermissions.count,
                                                      modules: affectedModuleCount),
                           symbol: "exclamationmark.circle.fill") {
                    // One withheld grant has one place to go, so go there.
                    // Several do not, and a button that picks one of them
                    // for you is a button that lies about what it opened.
                    if withheldPermissions.count == 1, let only = withheldPermissions.first {
                        Button(HelmWord.grant) { only.openSettings() }
                            .controlSize(.small)
                    } else {
                        Button(AppStr.showPermissions) {
                            // A token, never a bare `withAnimation`: the
                            // default spring does not stop under Reduce
                            // Motion, and this is a long scroll.
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
                // while this window is open.
                Toggle(HelmWord.openHelmAtLogin,
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

            // What Helm does when nobody is at the desk: three modules reading
            // the volume once a day, said on the page that is about Helm.
            //
            // Only when there is a row: an empty card under a heading says
            // nothing. Nil until the off-list has been read (the task below),
            // so nothing is claimed about a switch nobody has looked up yet.
            if let scanRows, !scanRows.isEmpty {
                HelmSettingsSection(AppStr.backgroundScansSection) {
                    ForEach(scanRows, id: \.id) { row in scanRow(row) }
                    HelmSettingsNote(AppStr.backgroundScansNote)
                }
            }

            // Which modules there are and how they are grouped, which is not
            // behaviour. The composing happens in a sheet.
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
                // Three pictures, the way System Settings asks the same question.
                AppearancePicker(selection: $appearance, title: AppStr.lightOrDark)
                    .onChange(of: appearance) { _, choice in AppSettings.appearance = choice }
                PageHeaderRow()
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
                // `allCases` is the order the page draws them: settings, pencil, Quit.
                ForEach(PanelFooterSetting.Button.allCases, id: \.self) { button in
                    Toggle(footerLabel(button), isOn: Binding(
                        get: { footerButtons[button] ?? true },
                        set: { footerButtons[button] = $0 }))
                        .onChange(of: footerButtons[button]) { _, v in
                            if let v { AppSettings.setShows(button, v) }
                        }
                }
                // Helm is `LSUIElement`: no Dock icon, no application menu, so
                // the footer's Settings button and this menu are the whole set
                // of doors — and this sentence is one of exactly two places the
                // app says the menu exists.
                HelmSettingsNote(AppStr.panelFooterNote)
            }

            // Only when there is one: `neededPermissions` filters to what the
            // enabled modules declare, and a section with an empty body still
            // draws its heading over no card.
            if !neededPermissions.isEmpty {
                // Driven by the table, so a new permission shows up here
                // without anyone adding a row, but only the ones an enabled
                // module uses, as in `PermissionAudit.run()`: asking for a
                // grant nothing needs teaches people to grant without reading.
                HelmSettingsSection(AppStr.permissions) {
                    ForEach(neededPermissions, id: \.self) { need in
                        let granted = need.state(accessibility: accessibility,
                                                 fullDisk: diskAccess,
                                                 screenRecording: screenRecording) == .granted
                        // The mark is the row's own: the circle changes what it
                        // says and the ring stays put, so the grant arriving is
                        // news rather than a cut (`helmSymbolSwap`).
                        HelmSettingRow(AppStr.permissionTitle(need),
                                       // Both, never the caveat instead of the
                                       // reason: what the grant is for is what
                                       // the decision is made on.
                                       note: !granted && adHocBuild
                                           ? AppStr.permissionWhy(need) + "\n"
                                               + AppStr.fullDiskAccessAdHoc
                                           : AppStr.permissionWhy(need),
                                       mark: granted ? .holding : .attention,
                                       // Not granted is spoken by the Grant button beside it.
                                       markSpoken: granted ? AppStr.permissionGranted : nil) {
                            if !granted {
                                Button(HelmWord.grant) { need.openSettings() }
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
        // The grants through the trackers rather than this page's own `.task`
        // and `didBecomeActive`: the disk probe is blocking file reads, and both
        // of those run on the thread that draws. The trackers read off the
        // cooperative pool.
        .helmTracksFullDiskAccess($diskAccess)
        .helmTracksAccessibility($accessibility)
        .helmTracksScreenRecording($screenRecording)
        .task {
            // Not in the state's initial value, and not awaited here either: a
            // `.task` continuation is drained by the layout pass that draws the
            // page, so awaiting the keychain here would delay the first frame.
            // `readTheOffList` takes the answer if it is in hand and otherwise
            // leaves it nil until a task it does not wait for brings one.
            readTheOffList()
        }
        .confirmationDialog(AppStr.resetConfirmTitle, isPresented: $confirmingReset,
                            titleVisibility: .visible) {
            Button(AppStr.resetConfirmAction, role: .destructive) { ResetEverything.run() }
            Button(HelmWord.cancel, role: .cancel) {}
        } message: {
            Text(AppStr.resetConfirmBody)
        }
        }
    }

    /// What the counter line at the top scrolls to.
    private static let permissionsAnchor = "settings.permissions"
}

/// **Flat or Liquid Glass**, written to `AppSettings.barAppearance`, whose setter posts
/// `.helmBarAppearanceChanged` for the header row (`helmTracksBarAppearance`).
/// Its own `@State`, so the page holds nothing for it. The header row's right-click menu
/// (`HeaderBarMenu`) writes the same setting, so the row listens for the notification and takes the value
/// the store holds.
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
                AppSettings.barAppearance = new
            }
            .onReceive(NotificationCenter.default.publisher(for: .helmBarAppearanceChanged)) { _ in
                choice = AppSettings.barAppearance
            }
        }
    }
}

/// **With Icon or Without Icon**, written to `AppSettings.pageBarStyle` (`PageBarStyle`), whose setter posts
/// `.helmHeaderChoicesChanged` for the header row (`helmTracksHeaderChoices`). The row's right-click menu
/// (`HeaderBarMenu`) writes the same setting, so this row listens for the notification and takes the value the
/// store holds; the page is not rebuilt for it.
struct PageHeaderRow: View {
    @State private var choice = AppSettings.pageBarStyle

    var body: some View {
        HelmSettingRow(AppStr.pageBar) {
            Picker(AppStr.pageBar, selection: $choice) {
                Text(AppStr.pageBarWithIcon).tag(PageBarStyle.moduleName)
                Text(AppStr.pageBarWithoutIcon).tag(PageBarStyle.windowTitle)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: choice) { _, new in
                AppSettings.pageBarStyle = new
            }
            .onReceive(NotificationCenter.default.publisher(for: .helmHeaderChoicesChanged)) { _ in
                choice = AppSettings.pageBarStyle
            }
        }
    }
}
