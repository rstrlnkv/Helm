import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// What the person sets for Launchpad: the button and shortcut that open its window, the apps they hid and the way
/// back to the alphabetical arrangement. The arrangement itself is drawn and changed in the window, not here.
///
/// A shortcut that was never recorded holds nothing (`LaunchpadHotkey`), and a taken one is said by the row. Resetting
/// asks first: the press only sets `pendingReset`.
struct LaunchpadSettingsPage: View {
    @ObservedObject private var lvm: LaunchpadViewModel
    @StateObject private var openKey: HelmHotkeyRecorder
    /// Bumped when a shortcut is recorded, so «taken» is judged against the combination now stored.
    @State private var shortcutRevision = 0

    init(lvm: LaunchpadViewModel) {
        self.lvm = lvm
        _openKey = StateObject(wrappedValue: HelmHotkeyRecorder(store: lvm.store, prefix: LaunchpadHotkey.storePrefix))
    }

    var body: some View {
        Form {
            if let notice = lvm.notice {
                Section { HelmBanner(LpStr.text(of: notice)) }
            }
            Section {
                Button(LpStr.openLaunchpad) { lvm.showLaunchpad() }
            }
            Section {
                HelmHotkeyRow(LpStr.toggleLaunchpad, recorder: openKey, taken: HotkeyStatus.isTaken(LaunchpadHotkey.open))
                    .id(shortcutRevision)
            } header: {
                HelmSectionTitle(HelmWord.keyboardShortcuts)
            }
            hiddenSection
            Section {
                HelmSettingRow(LpStr.arrangement, note: LpStr.resetNote) {
                    Button(LpStr.resetArrangement) { lvm.askToReset() }
                }
            }
        }
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        .task { await lvm.whileShown() }
        .onReceive(NotificationCenter.default.publisher(for: .helmHotkeyChanged)) { _ in shortcutRevision += 1 }
        // The press only sets `pendingReset`; the destructive button asks the model to go through with it.
        .confirmationDialog(LpStr.resetQuestion,
                            isPresented: Binding(get: { lvm.pendingReset }, set: { if !$0 { lvm.cancelReset() } }),
                            titleVisibility: .visible) {
            Button(LpStr.resetArrangement, role: .destructive) { Task.immediate { await lvm.confirmReset() } }
            Button(HelmWord.cancel, role: .cancel) { lvm.cancelReset() }
        } message: {
            Text(LpStr.resetNote)
        }
    }

    // MARK: - Hidden

    @ViewBuilder private var hiddenSection: some View {
        let hidden = lvm.snapshot.map { snapshot in
            snapshot.order.filter { snapshot.layout.hidden.contains($0) }.compactMap { snapshot.apps[$0] }
        } ?? []
        Section {
            if hidden.isEmpty {
                Text(LpStr.noHiddenApps).foregroundStyle(HelmText.quiet)
            } else {
                ForEach(hidden, id: \.id) { app in
                    HStack(spacing: HelmSpace.s5) {
                        Image(nsImage: AppInfo.icon(forFile: app.path)).resizable()
                            .frame(width: LaunchpadMetrics.hiddenIcon, height: LaunchpadMetrics.hiddenIcon)
                            .accessibilityHidden(true)
                        Text(app.name).font(HelmText.rowTitle).lineLimit(1)
                        Spacer()
                        Button(HelmWord.show) { Task { await lvm.unhide(app.id) } }
                            .accessibilityLabel(LpStr.show(app.name))
                    }
                }
            }
        } header: {
            HStack(spacing: HelmSpace.s3) {
                HelmSectionTitle(LpStr.hiddenApps)
                if !hidden.isEmpty { HelmBadge("\(hidden.count)") }
            }
        }
    }
}
