import SwiftUI
import AppKit
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// Settings page for the VPN module. Connections are read live from the view
/// model; per-app automation rules are seeded from the `NamespacedStore` into
/// local `@State` and written through on every change, notifying the engine
/// via `reloadRules`.
public struct VPNSettingsPage: View {
    @ObservedObject private var vm: VPNViewModel
    private let store: NamespacedStore

    @State private var rules: [String: VPNAppRule]
    @State private var notice: VPNNotice
    @State private var spin: Bool
    @State private var spinTintConnected: String
    @State private var spinTintDisconnected: String
    /// Natural height of the two swatch rows, measured so the disclosure
    /// animates between 0 and a concrete value — the same pattern
    /// `UtilitiesSection` in `HelmPanel.swift` uses for its rows.
    @State private var spinRowsHeight: CGFloat = 0

    public init(vm: VPNViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        // From the store rather than from `vm`, which is main-actor isolated
        // while this initializer is not. Nothing here may reach macOS's
        // notification centre: `UNUserNotificationCenter.current()` ends a test
        // run outright, and this page is constructed in one.
        let settings = VPNSettings(store: store)
        _rules = State(initialValue: VPNRules.decode(settings.rulesJSON))
        _notice = State(initialValue: settings.notice)
        _spin = State(initialValue: settings.automationSpin)
        _spinTintConnected = State(initialValue: settings.spinTint(for: .connected))
        _spinTintDisconnected = State(initialValue: settings.spinTint(for: .disconnected))
    }

    public var body: some View {
        vpnForm
    }

    /// Connections that are up. Not on their way up: the strip says "active"
    /// and tints it green, beside a row spinning and saying "Connecting".
    private var activeCount: Int {
        vm.connections.filter(\.status.isConnected).count
    }

    private var vpnForm: some View {
        Form {
            Section {
                HelmMetricStrip([
                    .init("\(vm.connections.count)", VPNStr.metricConnections),
                    .init("\(activeCount)", VPNStr.metricActive, tint: activeCount > 0 ? .green : nil),
                    // The rules written down, not the ones firing this second:
                    // the dial sat directly above the list and read 0 over one
                    // visible rule. Which of them is up is the dot's answer.
                    .init("\(VPNRules.automationCount(rules))", VPNStr.metricAutomatic),
                ])
            }

            Section(VPNStr.connections) {
                connectionsList
            }

            Section(VPNStr.perAppAutomation) {
                appRulesEditor
            }

            Section(VPNStr.noticeSection) {
                noticePicker
            }

            Section(VPNStr.spinSection) {
                spinControls
            }
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        // The engine is asked once in `init` and the view model is cached for
        // the app's lifetime, so without these the page showed whatever the
        // system said at launch — this was the only settings page of nine with
        // no `.task` at all.
        .task {
            vm.refresh()
            // The mirror of what macOS said is a memory, and the person can
            // revoke banners in System Settings without Helm hearing a thing.
            // A read, never a request: opening a settings page must not prompt.
            await vm.refreshBannerAuthorization()
        }
        // A VPN connected, disconnected or added while the person was in
        // System Settings. `DynamicStoreNetworkWatch` catches most of that
        // already; coming back to Helm is the moment it costs nothing to be
        // sure, and it is the one route that needs no observer to have fired.
        //
        // Banners are re-read here for a sharper reason: the button below sends
        // the person to the Notifications pane, and coming back is the only
        // moment Helm can learn what they did there. A read, never a request.
        .helmOnAppActive {
            vm.refresh()
            Task { await vm.refreshBannerAuthorization() }
        }
    }

    // MARK: - How a firing is announced

    /// The choice, and the one place in Helm that asks macOS for the
    /// notification permission — `vm.choose` asks only for the mode that needs
    /// one, and never at launch.
    @ViewBuilder
    private var noticePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            // **No second heading inside the card.** The section already says
            // what this decides, and "Notification style" over the cards made
            // the only sub-heading *inside* a card anywhere in Helm — everywhere
            // else a label sits over the card, on the page. The string is still
            // the group's accessibility label, because a screen reader hears no
            // section header at this depth.
            HelmChoiceCards(selection: Binding(
                get: { notice },
                set: { chosen in
                    notice = chosen
                    Task { await vm.choose(chosen) }
                }),
                items: [
                    .init(id: .silent, label: VPNStr.noticeOption(.silent),
                          preview: NoticePreview.strip(name: false, banner: false)),
                    .init(id: .menuBar, label: VPNStr.noticeOption(.menuBar),
                          preview: NoticePreview.strip(name: true, banner: false)),
                    .init(id: .system, label: VPNStr.noticeOption(.system),
                          preview: NoticePreview.strip(name: true, banner: true)),
                ])
                .accessibilityElement(children: .contain)
                .accessibilityLabel(VPNStr.noticeLabel)
        }
        // Where the switch is, not only in the app's permission list: a mode
        // macOS refuses looks exactly like one it allows.
        if notice == .system, vm.bannerAuthorization == .denied {
            HelmPermissionNote(text: VPNStr.noticeDenied,
                               openSettings: PermissionCheck.openNotificationSettings)
        }
        Text(VPNStr.noticeHint)
            .font(.caption)
            .foregroundStyle(HelmText.quiet)
    }

    /// The spin toggle and its two colour rows. The rows are mounted always
    /// and revealed by an animated, measured height rather than an `if` — the
    /// same pattern `UtilitiesSection` in `HelmPanel.swift` uses, because an
    /// `if`-mounted subtree pops instead of growing (ARCHITECTURE.md §
    /// Motion).
    @ViewBuilder
    private var spinControls: some View {
        Toggle(VPNStr.spinLabel, isOn: Binding(
            get: { spin },
            set: { on in
                withAnimation(HelmMotion.disclosure) { spin = on }
                VPNSettings(store: store).setAutomationSpin(on)
            }))

        VStack(spacing: 2) {
            LabeledContent(VPNStr.spinConnected) {
                HelmPaletteSwatches(selection: spinTintConnected, layout: .row) { token in
                    spinTintConnected = token
                    VPNSettings(store: store).setSpinTint(token, for: .connected)
                }
            }
            LabeledContent(VPNStr.spinDisconnected) {
                HelmPaletteSwatches(selection: spinTintDisconnected, layout: .row) { token in
                    spinTintDisconnected = token
                    VPNSettings(store: store).setSpinTint(token, for: .disconnected)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            if height > 0 { spinRowsHeight = height }
        }
        .frame(height: spin ? spinRowsHeight : 0, alignment: .top)
        // Height + clipping only, matching `UtilitiesSection`: fading would
        // isolate the rows in their own layer.
        .clipped()
        .allowsHitTesting(spin)
        // `.clipped()` hides it from the eye, not from the accessibility tree.
        .accessibilityHidden(!spin)

        // Said where the two settings are, not only in a spec file.
        if !spin, notice == .silent {
            Text(VPNStr.spinSilentWarning)
                .font(.caption)
                .foregroundStyle(HelmSignal.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connections

    @ViewBuilder
    private var connectionsList: some View {
        if vm.connections.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "lock.slash")
                Text(VPNStr.noVPNsSystem)
            }
            .font(.callout)
            .foregroundStyle(HelmText.quiet)
            .accessibilityElement(children: .combine)
        } else {
            ForEach(vm.connections) { connection in
                connectionRow(connection)
            }
        }
    }

    private func connectionRow(_ c: VPNConnection) -> some View {
        let active = c.status.isUp
        let transitioning = c.status.isTransitioning
        return HStack(spacing: 12) {
            HelmStatusDot(active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name)
                // The separator belongs to the pair, not to the status.
                // Written as `Text("· \(status)")` it was drawn whether or not
                // there was a kind in front of it, so a connection whose
                // protocol could not be read — `scutil` printing `[]`, which
                // `prettyKind` answers nil for — showed a line opening on a
                // stray middle dot. Latent rather than live: the parser's
                // fallback almost always finds a word. It is also the one
                // piece of punctuation on this row that never went through
                // `L()`, and `·` is not what CJK sets between two words.
                HStack(spacing: 6) {
                    if let kind = prettyKind(c.kind) {
                        Text(kind)
                        Text(VPNStr.separator)
                    }
                    Text(statusText(c.status))
                }
                .font(.caption)
                .foregroundStyle(HelmText.quiet)
            }
            // The name and what it is doing are one thing to read, not two
            // stops. On the text only, the way Disk and Duplicates do it: the
            // switch beside it stays its own control.
            .accessibilityElement(children: .combine)
            Spacer()
            if transitioning { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(
                get: { active },
                set: { on in on ? vm.connect(c.name) : vm.disconnect(c.name) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(c.name)
        }
        .padding(.vertical, 3)
    }

    private func prettyKind(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for k in ["L2TP", "IKEv2", "IPSec", "WireGuard", "PPTP"] where raw.contains(k) { return k }
        return raw.split(separator: ":").first.map(String.init)
    }

    private func statusText(_ status: VPNStatus) -> String { VPNStr.status(status) }

    // MARK: - Per-app automation

    private var sortedBundleIDs: [String] {
        rules.keys.sorted()
    }

    @ViewBuilder
    private var appRulesEditor: some View {
        if rules.isEmpty {
            Text(VPNStr.perAppHint)
                .font(.callout)
                .foregroundStyle(HelmText.quiet)
        }
        // What the tunnel actually covers. Kept out of the `isEmpty` branch on
        // purpose — the person with rules already configured is the one acting
        // on the belief that only that app is routed.
        Text(VPNStr.perAppScopeNote)
            .font(.caption)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(Array(sortedBundleIDs.enumerated()), id: \.element) { index, bundleID in
            if index > 0 { Divider() }
            appRuleRow(bundleID)
        }
        Button {
            pickApp()
        } label: {
            Label(VPNStr.addApp, systemImage: "plus")
        }
        .disabled(vm.connections.isEmpty)
    }

    /// One line per app: which VPN, and when the rule fires. The two switches
    /// this replaces were not independent settings — "neither" is a rule that
    /// does nothing, which the menu can name.
    private func appRuleRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
        // A renamed or deleted VPN silently disables its rules; the row said
        // nothing and the picker simply showed blank.
        // `VPNRules.orphaned` is this question, tested, and was answered here
        // by hand — per row, which is also how the second answer gets written.
        let missing = VPNRules.orphaned(rules, against: vm.connections)[bundleID] != nil
        return HelmAppRuleRow(bundleID: bundleID) {
            // Two nameless pop-ups in one row are indistinguishable to
            // VoiceOver; each carries what it chooses.
            Picker("\(info.name) — \(VPNStr.rulePickerVPN)", selection: vpnNameBinding(bundleID)) {
                ForEach(vm.connections.map(\.name), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("\(info.name) — \(VPNStr.rulePickerWhen)", selection: timingBinding(bundleID)) {
                ForEach(VPNAppRule.Timing.allCases, id: \.self) { timing in
                    Text(VPNStr.ruleTiming(timing)).tag(timing)
                }
            }
            .labelsHidden()
            .fixedSize()
        } note: {
            if missing, let name = rules[bundleID]?.vpnName {
                HStack(spacing: 6) {
                    // The token, not `.orange`: `HelmPermissionNote` draws this
                    // exact glyph two rows away at 4.54:1, and the literal
                    // measured 2.31:1 in light appearance.
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(HelmSignal.warning)
                        .accessibilityHidden(true)   // the text beside it says it
                    Text(VPNStr.ruleVPNMissing(name))
                        .font(.caption)
                        .foregroundStyle(HelmText.quiet)
                }
            }
        } remove: {
            rules.removeValue(forKey: bundleID)
            persist()
        }
    }

    private func timingBinding(_ bundleID: String) -> Binding<VPNAppRule.Timing> {
        Binding(
            get: { rules[bundleID]?.timing ?? .launchAndQuit },
            set: { newValue in
                guard var rule = rules[bundleID] else { return }
                rule.set(newValue)
                rules[bundleID] = rule
                persist()
            })
    }

    private func vpnNameBinding(_ bundleID: String) -> Binding<String> {
        Binding(
            get: { rules[bundleID]?.vpnName ?? vm.connections.first?.name ?? "" },
            set: { newValue in
                var rule = rules[bundleID] ?? VPNAppRule(vpnName: newValue)
                rule.vpnName = newValue
                rules[bundleID] = rule
                persist()
            })
    }

    private func persist() {
        VPNSettings(store: store).setRulesJSON(VPNRules.encode(rules))
        vm.send(VPNCommand.reloadRules)
    }

    private func pickApp() {
        let defaultVPN = vm.connections.first?.name ?? ""
        var added = false
        for bundleID in AppPicker.choose() where rules[bundleID] == nil {
            rules[bundleID] = VPNAppRule(vpnName: defaultVPN)
            added = true
        }
        if added { persist() }
    }
}
