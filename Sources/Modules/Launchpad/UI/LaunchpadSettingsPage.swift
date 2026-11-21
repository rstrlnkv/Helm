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
    /// The lock in front of the hidden apps' names: asked for by Show, shut again when the page goes (`onDisappear`).
    @StateObject private var hiddenGate: LaunchpadHiddenGate
    /// Bumped when a shortcut is recorded, so «taken» is judged against the combination now stored.
    @State private var shortcutRevision = 0
    /// The manual rows' measured height, for the accordion that shows them while Automatic is off.
    @State private var manualHeight: CGFloat?
    /// The rows under the pinch switch, measured for the accordion that shows them while it is on.
    @State private var pinchHeight: CGFloat?

    init(lvm: LaunchpadViewModel) {
        self.lvm = lvm
        _openKey = StateObject(wrappedValue: HelmHotkeyRecorder(store: lvm.store, prefix: LaunchpadHotkey.storePrefix))
        _hiddenGate = StateObject(wrappedValue: LaunchpadHiddenGate(port: lvm.makeAuth()))
    }

    var body: some View {
        Form {
            if let notice = lvm.notice {
                Section { HelmBanner(LpStr.text(of: notice)) }
            }
            Section {
                Button(LpStr.openLaunchpad) { lvm.showLaunchpad() }
            }
            if let helper = lvm.helperURL {
                // As the Dock and Finder show it (the helper's localized display name), not the file's.
                let helperName = FileManager.default.displayName(atPath: helper.path)
                Section {
                    HelmSettingRow(LpStr.dockIcon, note: LpStr.dockIconNote) {
                        HStack(spacing: HelmSpace.s5) {
                            HelmDraggableFileIcon(helper, size: LaunchpadMetrics.dockIcon, name: LpStr.dockIconNamed(helperName))
                            // The control keeps its words on one line; the note beside it is what wraps.
                            Button { lvm.revealHelper(helper) } label: { Text(HelmWord.showInFinder).fixedSize() }
                                .accessibilityLabel(LpStr.showNamedInFinder(helperName))
                        }
                    }
                }
            }
            Section {
                HelmHotkeyRow(LpStr.toggleLaunchpad, recorder: openKey, taken: HotkeyStatus.isTaken(LaunchpadHotkey.open))
                    .id(shortcutRevision)
            } header: {
                HelmSectionTitle(HelmWord.keyboardShortcuts)
            }
            pinchSection
            gridSection
            Section {
                HelmSettingRow(LpStr.launchCountsTitle, note: LpStr.launchCountsNote) {
                    Button { Task { await lvm.resetLaunchCounts() } } label: { Text(LpStr.resetLaunchCountsNamed).fixedSize() }
                        .disabled(lvm.snapshot?.launchCounts.isEmpty ?? true)
                }
                let moved = lvm.snapshot?.layout.categoryOverrides.count ?? 0
                HelmSettingRow(LpStr.movedApps(moved)) {
                    Button { Task { await lvm.returnAllMoved() } } label: { Text(LpStr.returnAllMoved).fixedSize() }
                        .disabled(moved == 0)
                        .accessibilityLabel(LpStr.returnAllMovedNamed)
                }
            }
            hiddenSection
            Section {
                HelmSettingRow(LpStr.arrangement, note: LpStr.resetNote) {
                    Button { lvm.askToReset() } label: { Text(LpStr.resetArrangement).fixedSize() }
                }
            }
        }
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        .onDisappear { hiddenGate.lock() }
        .task { await lvm.reloadPinch() }
        .task { lvm.reloadGrid(); await lvm.whileShown() }
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

    // MARK: - Pinch

    /// The switch, and under it while it is on what the watch came to and, when the system's own pinch is on too, the way to turn that off.
    private var pinchSection: some View {
        Section {
            VStack(spacing: 0) {
                HelmSettingRow(LpStr.pinchTitle, note: LpStr.pinchNote) {
                    Toggle(LpStr.pinchTitle, isOn: Binding(
                        get: { lvm.pinchOn },
                        set: { on in withAnimation(HelmMotion.disclosure) { lvm.setPinch(on: on) } }))
                        .labelsHidden()
                        .accessibilityLabel(LpStr.pinchTitle)
                }
                VStack(spacing: 0) {
                    Divider()
                    if let line = LpStr.text(of: lvm.pinchState) {
                        // The kit note's own face and ink: the state is a note of the switch, not a row of its own.
                        Text(line).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, HelmSpace.s3)
                    }
                    if lvm.systemPinchIsOn {
                        Divider()
                        HelmSettingRow(LpStr.pinchSystemTitle, note: LpStr.pinchSystemStillOn) {
                            Button { lvm.openTrackpadSettings() } label: { Text(LpStr.pinchOpenTrackpadSettings).fixedSize() }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .helmAccordion(open: lvm.pinchOn, height: $pinchHeight)
            }
        }
    }

    // MARK: - Grid

    /// Automatic is the default; its press flips the switch inside the disclosure animation, then tells the model, which writes.
    private var gridSection: some View {
        let grid = lvm.grid
        return Section {
            // One Form row: the toggle's row, then the manual rows under an accordion, so Automatic leaves no blank band.
            VStack(spacing: 0) {
                HelmSettingRow(LpStr.gridAutomatic, note: LpStr.gridAutomaticNote) {
                    Toggle(LpStr.gridAutomatic, isOn: Binding(
                        get: { grid.automatic },
                        set: { on in withAnimation(HelmMotion.disclosure) { var next = grid; next.automatic = on; lvm.setGrid(next) } }))
                        .labelsHidden()
                        .accessibilityLabel(LpStr.gridAutomatic)
                }
                VStack(spacing: 0) {
                    stepRow(LpStr.gridRows, value: grid.rows, range: LaunchpadGridSettings.rowRange) { var next = grid; next.rows += $0; return next }
                    stepRow(LpStr.gridColumns, value: grid.columns, range: LaunchpadGridSettings.columnRange) { var next = grid; next.columns += $0; return next }
                }
                .fixedSize(horizontal: false, vertical: true)
                .helmAccordion(open: !grid.automatic, height: $manualHeight)
            }
            HelmSettingRow(LpStr.gridIconSize, note: LpStr.gridFitNote) {
                // A drag publishes the grid as it goes and writes once, when it ends.
                Slider(value: Binding(get: { grid.iconSize }, set: { var next = grid; next.iconSize = $0.rounded(); lvm.setGrid(next, live: true) }),
                       in: LaunchpadGridSettings.iconRange) { editing in if !editing { lvm.commitGrid() } }
                    .frame(width: 160)
                    .labelsHidden()
                    .accessibilityLabel(LpStr.gridIconSize)
                    .accessibilityValue(LpStr.gridIconSizeValue(Int(grid.iconSize)))
                ZStack(alignment: .trailing) {
                    Text(LpStr.gridIconSizeValue(Int(LaunchpadGridSettings.iconRange.upperBound))).hidden()
                    Text(LpStr.gridIconSizeValue(Int(grid.iconSize)))
                }
                // The title column has layout priority; without this the figure is squeezed and its unit wraps under it.
                .fixedSize(horizontal: true, vertical: false)
                .helmFigure()
                .accessibilityHidden(true)
            }
            HelmSettingRow(LpStr.gridResetTitle, note: LpStr.gridResetNote) {
                Button { lvm.resetGrid() } label: { Text(LpStr.gridReset).fixedSize() }
                    .disabled(grid.isStandard)
                    .accessibilityLabel(LpStr.gridResetNamed)
            }
        } header: {
            HelmSectionTitle(LpStr.grid)
        }
    }

    /// A number in a range, stepped by one; the figure's column is as wide as the widest value, so a step never moves the stepper.
    private func stepRow(_ title: String, value: Int, range: ClosedRange<Int>,
                         stepped: @escaping (Int) -> LaunchpadGridSettings) -> some View {
        HelmSettingRow(title) {
            ZStack(alignment: .trailing) {
                Text("\(range.upperBound)").hidden()
                Text("\(value)")
            }
            .helmFigure()
            .accessibilityHidden(true)
            Stepper(title,
                    onIncrement: value < range.upperBound ? { lvm.setGrid(stepped(1)) } : nil,
                    onDecrement: value > range.lowerBound ? { lvm.setGrid(stepped(-1)) } : nil)
                .labelsHidden()
                .accessibilityValue("\(value)")
        }
    }

    // MARK: - Hidden

    /// Locked, a count and Show, which asks Touch ID or the Mac's password; unlocked, the list, until the page goes.
    @ViewBuilder private var hiddenSection: some View {
        let hidden = lvm.snapshot?.hiddenApps ?? []
        if hiddenGate.phase == .unlocked {
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
        } else {
            Section {
                HelmSettingRow(LpStr.hiddenAppsCount(hidden.count)) {
                    Button(HelmWord.show) { hiddenGate.ask(reason: LpStr.hiddenAuthReason) {} }
                        .disabled(hidden.isEmpty || hiddenGate.phase == .asking)
                        .accessibilityLabel(LpStr.showHiddenNamed)
                }
                if hiddenGate.unavailable { HelmBanner(LpStr.hiddenUnavailable) }
            }
        }
    }
}
