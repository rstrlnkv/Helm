import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

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
    @State private var style: String = AppSettings.menuBarIconStyle
    @State private var size: String = AppSettings.menuBarIconSize
    /// The state macOS is in, not the answer the switch was given — and
    /// re-probed on activation like the permission rows below it.
    @State private var launchAtLogin: LoginItemState = LoginItem.current()
    @State private var appearance: AppAppearance = AppSettings.appearance
    @State private var language: String? = AppSettings.language?.rawValue
    @State private var sidebarStyle: SidebarStyle = AppSettings.sidebarStyle
    @State private var tabLabels = AppSettings.tabLabelStyle
    @State private var showPanelEditButton = AppSettings.showPanelEditButton
    @State private var showSettingsButton = AppSettings.showSettingsButton
    @State private var showQuitButton = AppSettings.showQuitButton
    @State private var diskAccess: PermissionState = .granted
    @State private var accessibility: PermissionState = .granted
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
    /// before the window had drawn anything (ARCHITECTURE.md § A seal needs a
    /// signature — the same fact that keeps `clamshellEnabled` unsealed, reached
    /// through a second door). Nil rather than an empty set: an empty off-list
    /// means every scan is on, and standing in for "not read yet" with it would
    /// show a whole-volume walk switched on to somebody who never said so.
    @State private var disabledScans: Set<String>?
    @State private var lastScanAt = AppSettings.lastScanAt
    private let adHocBuild = PermissionCheck.isAdHocSigned()

    /// The needed permissions macOS is currently withholding.
    private var withheldPermissions: [PermissionNeed] {
        PermissionSummary.withheld(accessibility: accessibility, fullDisk: diskAccess)
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
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "gearshape", tint: .gray,
                           title: AppStr.settingsPane)
            Divider()
            settingsForm
        }
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               action: @escaping () -> Void) -> some View {
        // The two share their circle, so the mark inside it is what changes
        // and the ring stays put — the swap is worth having here rather than a
        // cut precisely because the grant arriving is news.
        let symbol = granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        return HStack(alignment: .top, spacing: HelmSpace.s5) {
            Image(systemName: symbol)
                .helmSymbolSwap(symbol)
                .foregroundStyle(granted ? HelmSignal.success : HelmSignal.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(AppStr.grant, action: action).controlSize(.small)
            }
        }
    }

    /// One scan, named by its module and captioned with when it last came back.
    ///
    /// The date is `lastScanAt` — when a scan **finished**, with a report — and
    /// not the attempt beside it: "we started looking on Tuesday" is not an
    /// answer to "what has Helm read".
    private func scanRow(_ row: ScanConsent.Row) -> some View {
        let module = ModuleRegistry.descriptor(row.id)
        return Toggle(isOn: Binding(get: { row.isOn },
                                    set: { setScan(row.id, on: $0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(module?.moduleMetadata.name ?? row.id)
                Text(row.lastRun.map { AppStr.scanLastRun(HelmDates.relative($0)) }
                        ?? AppStr.scanNeverRun)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
            }
        }
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
        self.disabledScans = AppSettings.disabledScans
    }

    private var settingsForm: some View {
        ScrollViewReader { scroll in
        Form {
            // Above everything, because it is the only thing on this page that
            // is *wrong right now* — and because the section that answers it
            // was 919 pt down a form in a 587 pt viewport, entirely below the
            // fold at the default window. The sidebar's triangle sends people
            // here; this is the first thing they see when they arrive.
            //
            // Only when something is withheld. A row saying everything is
            // granted is a row teaching people to ignore this space.
            if !withheldPermissions.isEmpty {
                Section {
                    HStack(spacing: HelmSpace.s5) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(HelmSignal.warning)
                        Text(AppStr.permissionsWithheld(count: withheldPermissions.count,
                                                        modules: affectedModuleCount))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
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
            }

            // What Helm does on its own.
            Section(header: HelmSectionTitle(HelmSectionName.behaviour)) {
                // The switch draws what macOS says, and the write answers with
                // what macOS says afterwards: `register()` can throw, and the
                // person can take the registration away in System Settings
                // while this window is open. Both used to leave the switch on.
                Toggle(AppStr.launchAtLogin,
                       isOn: Binding(get: { launchAtLogin.isOn },
                                     set: { launchAtLogin = LoginItem.setEnabled($0) }))
                if let note = AppStr.loginItemNote(launchAtLogin) {
                    HStack(alignment: .top, spacing: HelmSpace.s5) {
                        Text(note)
                            .font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
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
                Section(header: HelmSectionTitle(AppStr.backgroundScansSection)) {
                    ForEach(scanRows, id: \.id) { row in scanRow(row) }
                    Text(AppStr.backgroundScansNote)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Which modules there are and how they are grouped, which is not
            // behaviour — it was under that heading and did not belong to it.
            //
            // The composing happens in a sheet. As a block it was the largest
            // thing on this page by a distance and 10 pt wider than everything
            // around it, because it was drawn as a section *header* to avoid a
            // card inside a card.
            Section(header: HelmSectionTitle(AppStr.modulesSection)) {
                SidebarComposerRow(host: ModuleHost.shared, composing: $composing)
            }

            // Everything that decides how Helm looks, in one list. It was
            // three: the theme and the module icons under «General», the
            // menu-bar glyph under «Menu Bar» — so choosing how the app looks
            // meant visiting two headings and knowing which held what.
            // Dev builds only. This is a tool for reading the app in a
            // language this Mac is not set to — eight of them, where the only
            // other way to see the seventh is to change the system preference
            // and log out. It is not a feature: macOS decides an app's
            // language, and a second answer in Helm's own settings would be
            // two places to look on a shipping build.
            if AppBuild.isDev {
                Section(header: HelmSectionTitle(AppStr.developerSection)) {
                    Picker(AppStr.interfaceLanguage, selection: $language) {
                        Text(AppStr.systemLanguage).tag(String?.none)
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Text(lang.endonym).tag(String?.some(lang.rawValue))
                        }
                    }
                    .onChange(of: language) { _, code in
                        AppSettings.language = code.flatMap(AppLanguage.init(rawValue:))
                    }
                    Text(AppStr.interfaceLanguageNote)
                        .font(.system(size: 11))
                        .foregroundStyle(HelmText.quiet)
                }
            }

            Section(header: HelmSectionTitle(AppStr.appearance)) {
                // Three pictures, the way System Settings asks the same
                // question. It was a pop-up of three accurate words that are
                // not what anybody is choosing between.
                AppearancePicker(selection: $appearance, title: AppStr.lightOrDark)
                    .onChange(of: appearance) { _, choice in AppSettings.appearance = choice }
                // Worth offering only because the tint is the module's own: a
                // choice between four modules in one blue and grey is not one.
                Picker(AppStr.moduleIcons, selection: $sidebarStyle) {
                    Text(AppStr.moduleIconsColour).tag(SidebarStyle.colour)
                    Text(AppStr.moduleIconsPlain).tag(SidebarStyle.plain)
                }
                .pickerStyle(.segmented)
                .onChange(of: sidebarStyle) { _, choice in AppSettings.sidebarStyle = choice }
                // No `LabeledContent`: the picker carries its own title now,
                // and a labelled control inside a labelled row says it twice.
                // Given the chosen size, so its glyph is the icon as it will
                // be drawn in the bar rather than a sample at a fixed size.
                IconShapePicker(selection: $style, title: AppStr.iconShape, size: size)
                    .onChange(of: style) { _, v in AppSettings.menuBarIconStyle = v }
                LabeledContent(AppStr.iconSize) {
                    IconSizePicker(selection: $size)
                        .onChange(of: size) { _, v in AppSettings.menuBarIconSize = v }
                }
                Text(AppStr.menuBarNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            }

            // The panel keeps its own arrangement, so there is exactly one
            // thing about it to decide here: whether the way in is on it.
            Section(header: HelmSectionTitle(AppStr.panel)) {
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
                Text(AppStr.panelEditButtonNote)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                // Here rather than in the panel's own edit mode: it is how the
                // panel *looks*, decided once, and that mode is about which
                // widgets are on it.
                Picker(AppStr.tabLabels, selection: $tabLabels) {
                    ForEach(TabLabelStyle.allCases, id: \.self) { style in
                        Text(AppStr.tabLabelStyle(style)).tag(style)
                    }
                }
                .onChange(of: tabLabels) { _, chosen in AppSettings.tabLabelStyle = chosen }
            }

            // Only when there is one. `neededPermissions` filters to what the
            // *enabled* modules declare, so switching off the five that ask for
            // something emptied it — and a `Section` with an empty body still
            // draws its heading. The result was a heading with no card under
            // it, 71.5 pt of gap instead of the page's uniform 56, and «Сброс»
            // 7.5 pt below it reading as its subtitle: the destructive card
            // looked like what Permissions contained.
            if !neededPermissions.isEmpty {
                Section(header: HelmSectionTitle(AppStr.permissions)) {
                // Driven by the table, so a new permission shows up here
                // without anyone remembering to add a row — but only the ones
                // an enabled module actually uses. Listing all of them asked
                // someone who has switched Keyboard and Keep Awake off to grant
                // Accessibility for nothing, which is how people learn to grant
                // everything without reading. `PermissionAudit.run()` already
                // filters this way; the two disagreed.
                ForEach(neededPermissions, id: \.self) { need in
                    let granted = need.state(accessibility: accessibility,
                                             fullDisk: diskAccess) == .granted
                    permissionRow(AppStr.permissionTitle(need),
                                  // Both, never one instead of the other: the
                                  // ad-hoc caveat used to replace the sentence
                                  // saying what the grant is for, and every build
                                  // anybody runs is ad-hoc — so the Accessibility
                                  // decision was made without the words "every
                                  // keystroke in every app" ever being shown.
                                  detail: !granted && adHocBuild
                                      ? AppStr.permissionWhy(need) + "\n"
                                          + AppStr.fullDiskAccessAdHoc
                                      : AppStr.permissionWhy(need),
                                  granted: granted) { need.openSettings() }
                }
                }
                .id(Self.permissionsAnchor)
            }
            Section(header: HelmSectionTitle(AppStr.resetSection)) {
                // `role: .destructive` alone draws as an ordinary link in a
                // grouped Form on macOS — the role reaches menus and dialogs,
                // not form rows. The token, not SwiftUI's `.red`: HelmSignal
                // exists because literal colours measured under the 4.5:1
                // floor in light mode.
                Button(AppStr.resetAll, role: .destructive) { confirmingReset = true }
                    .foregroundStyle(HelmSignal.danger)
                Text(AppStr.resetNote)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $composing) {
            SidebarComposerSheet(host: ModuleHost.shared)
        }
        .formStyle(.grouped)
        // A grouped Form caps its content at 704 pt and centres it, so past a
        // 994 pt window its leading edge walks away from everything Helm draws
        // itself — measured at 36 pt on a 1070 pt window, 181 pt on 1360.
        // Capping it at 704 + 2×20 keeps the system on the branch where the
        // inset is a constant 20, which is what the page header uses.
        .helmSettingsColumn()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user grants in System Settings and comes back; the row has
            // to notice without being told.
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
            // A background scan runs when the person is away, which is exactly
            // the interval this window spends inactive: coming back is when
            // «hasn't run yet» can have stopped being true.
            lastScanAt = AppSettings.lastScanAt
            disabledScans = AppSettings.disabledScans
            // Login Items is one of the panes a person leaves this window for,
            // and the registration can be taken away there. The refusal Helm
            // remembers survives only while the system still agrees with it.
            launchAtLogin = LoginItem.current(refused: launchAtLogin == .refused)
        }
        .task {
            diskAccess = PermissionCheck.currentFullDiskAccess()
            accessibility = PermissionCheck.currentAccessibility()
            // Here and not in the state's initial value: this getter verifies a
            // seal, which reaches the login keychain, and on an ad-hoc build a
            // keychain read is a modal dialog.
            //
            // The task alone is not the fix, and it was measured not being one:
            // a `.task` continuation is drained by the very layout pass that
            // draws the page, so a blocking read inside it still delays the
            // first frame. Warming first is what moves the round trip off this
            // thread — the await suspends, the page lays out and draws, and the
            // read below is then memory (`SealKeyCache`).
            await AppSettings.scanGuard.warmKey()
            disabledScans = AppSettings.disabledScans
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
