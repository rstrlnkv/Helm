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

    /// The connections block, and the heading of the section it rides on.
    private var connectionsAndTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HelmSectionTitle(VPNStr.connections)
            connectionsList
            if !vm.connections.isEmpty {
                Text(VPNStr.connectionsHint)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let failure = vm.lastFailure {
                HelmBanner(failureText(failure), symbol: "exclamationmark.triangle.fill")
                    .padding(.top, 10)
            }
            // The gap the grouped form puts between a card and the next
            // heading, which this block is now standing in for.
            HelmSectionTitle(VPNStr.perAppAutomation)
                .padding(.top, 20)
        }
    }

    private var vpnForm: some View {
        Form {
            // No `HelmMetricStrip`. Two of its three figures — how many
            // connections, how many are up — are what the list underneath says
            // a row at a time, and the third is a number nobody acts on. The
            // one thing a person wants from the top of this page is whether
            // anything is up, and the window's own header draws that from
            // `VPNDescriptor.activity`.
            // **The connections ride on the next section's header.**
            //
            // v3 draws these cards straight on the pane. A grouped `Form` puts
            // every *row* in a card of its own — measured, the section fill is
            // 247 in light and 37 in dark — so a grid of cards inside one is a
            // card inside a card, and the leftover space of a row that does not
            // fill its width becomes a visible hole. `listRowBackground(.clear)`
            // does not take that fill away on macOS; Keep Awake measured it and
            // the block came back in a card either way.
            //
            // A section **header** is the one part of a grouped form that is
            // drawn on the bare pane and still scrolls, which is exactly the
            // two things this block needs. Same shape as Keep Awake's hero,
            // and for the same reason.
            Section(header: connectionsAndTitle) {
                appRulesEditor
            }

            Section(header: HelmSectionTitle(VPNStr.noticeSection)) {
                noticePicker
            }

            Section(header: HelmSectionTitle(VPNStr.spinSection)) {
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
                spin = on
                VPNSettings(store: store).setAutomationSpin(on)
            }))

        // **Disabled, never revealed.** These were a measured-height
        // disclosure under the switch, and it cost two things. The collapsed
        // block still occupied a `Form` row with a row's padding, so the
        // section ended in 36 pt of empty card under a separator that promised
        // a row — in the default state, since the spin ships off, which is what
        // a fresh install shows. And inside one row the two of them got no
        // hairline between them and none of the form's own rhythm.
        //
        // Keep Awake draws the same two palettes as plain rows and disables the
        // control rather than taking it away, with the reason in its own
        // comment: a row that loses its tallest control becomes visibly shorter
        // than its neighbours and the card twitches on a setting that has
        // nothing to do with its height. Same answer here, and the empty row
        // goes with the machinery.
        HelmSettingRow(VPNStr.spinConnected) {
            HelmPaletteSwatches(VPNStr.spinConnected, selection: spinTintConnected) { token in
                spinTintConnected = token
                VPNSettings(store: store).setSpinTint(token, for: .connected)
            }
            .disabled(!spin)
        }
        HelmSettingRow(VPNStr.spinDisconnected) {
            HelmPaletteSwatches(VPNStr.spinDisconnected, selection: spinTintDisconnected) { token in
                spinTintDisconnected = token
                VPNSettings(store: store).setSpinTint(token, for: .disconnected)
            }
            .disabled(!spin)
        }

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
            // A destination, not a shrug. The module cannot create a
            // configuration — `scutil --nc` has no `create` — so the one thing
            // this screen can do for somebody with no VPN is take them where
            // they are made. It was a single quiet line with nothing to press.
            HelmEmptyState(symbol: "lock.shield",
                           tint: VPNDescriptor.tint.colour,
                           title: VPNStr.noVPNsSystem,
                           message: VPNStr.noVPNsExplain,
                           note: VPNStr.noVPNsNote) {
                Button(VPNStr.openNetworkSettings) {
                    // The pane's own identifier, the way `PermissionNeed` opens
                    // the privacy panes.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        } else {
            // Adaptive rather than a fixed three: v3 draws three because it
            // had three to draw. A Mac with two would leave a third of the row
            // empty, and one with five would need a second row anyway.
            // **Adaptive with a ceiling**, and the ceiling is the point.
            //
            // It was `.adaptive(minimum: 190)`, which fixed three columns and
            // left 68 % of the row empty with one connection. Columns from the
            // *count* filled the row and produced the opposite fault: two
            // connections became two 660 pt cards with 660 pt buttons across
            // them, which is a card the size of a paragraph.
            //
            // The hole was only ever conspicuous because this grid sat inside
            // a grouped-`Form` section that drew a fill around it. On the bare
            // pane, which is where it lives now, leftover space is invisible —
            // so the card can go back to being card-sized. 280 is v3's own
            // width plus the room German needs for «Verbinden».
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)],
                      alignment: .leading,
                      spacing: 12) {
                ForEach(vm.connections) { connection in
                    connectionCard(connection)
                }
            }
        }
    }

    /// One connection, as a card with one verb.
    ///
    /// **A switch was the wrong control for this.** A `Toggle` says «this is on
    /// or off» and sets it directly; a tunnel takes seconds to come up, can
    /// refuse, and is put back down by the network without anybody asking — so
    /// the switch spent those seconds showing the state somebody *wanted*
    /// rather than the one that was true, and there was no honest position for
    /// «connecting». A button is a request, which is what pressing this is, and
    /// the dot and the words beside it report what happened.
    ///
    /// v3 draws these as a grid of cards, and the grid is what makes the verb
    /// affordable: a row has to fit its control in a column and a card does
    /// not.
    private func connectionCard(_ c: VPNConnection) -> some View {
        // **Two different questions, and they used to share one answer.**
        // `isUp` is «something is happening here» and includes `.connecting`;
        // `isConnected` is «traffic is on the tunnel». The dot and the ring
        // report the second — a green dot on a tunnel that is three seconds
        // into coming up is the page saying the Mac is protected when it is
        // not. The verb reads the first, because what you can ask for while it
        // is connecting is to stop.
        let connected = c.status.isConnected
        let transitioning = c.status.isTransitioning
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HelmStatusDot(active: connected)
                // Truncating is the price of the grid and worth paying — but
                // not silently: measured, «Mullvad WireGuard Amsterdam» becomes
                // «Mullvad WireGuard Amste…», and two configurations that
                // differ after 24 characters become the same row.
                Text(c.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .help(c.name)
            }
            // Monospaced, because these two lines are a readout — the kind is
            // a protocol name and the status is one of five words, and they sit
            // in a column of cards a person compares down.
            VStack(alignment: .leading, spacing: 0) {
                if let kind = prettyKind(c.kind) { Text(kind) }
                Text(statusText(c.status))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(HelmText.quiet)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 6)
            HStack(spacing: 6) {
                if transitioning { ProgressView().controlSize(.small) }
                connectionVerb(c, up: c.status.isUp, transitioning: transitioning)
            }
        }
        .padding(12)
        // No `minHeight`. Measured: every card in a row comes out 116 pt —
        // including one with no protocol line — so the floor never applied to
        // anything and a number that never applies is a claim nobody can check.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                // The token, not the number. This was the only place in the
                // tree spelling `Color.primary.opacity(0.05)` out; measured,
                // it is `HelmSurface.wellFill` to the byte — 236 in light and
                // 46 in dark, both ways.
                .fill(HelmSurface.wellFill)
        )
        .overlay(
            // The connected one is ringed rather than filled: a filled card in
            // a row of cards reads as «selected», and there is nothing to
            // select here — it is the one that is up.
            //
            // **`HelmSignal.success`, not the accent.** The accent already
            // means «the option you chose» 900 pt down this same page, where
            // `HelmChoiceCards` rings the notice preview in it — same ink, same
            // idiom, two meanings on one screen. Meanwhile the mark that does
            // mean «up», the dot 4 pt away, is the signal colour. Measured on
            // the card fill: ring 3.40:1 against the 3:1 floor for a non-text
            // mark, so this was never about legibility. It is also the person's
            // own setting: under Graphite the «which one is up» mark went grey.
            RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
                .strokeBorder(connected ? HelmSignal.success : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func connectionVerb(_ c: VPNConnection, up: Bool, transitioning: Bool) -> some View {
        // **The frame goes on the label, not on the button.**
        // `.frame(maxWidth: .infinity)` applied to a macOS bordered control
        // does not stretch it — the control hugs its title and centres itself
        // in the space instead. Measured in an offscreen window at a 171 pt
        // content width: on the button the control starts at x=60; on the label
        // it starts at x=12 and fills. Left as it was, three cards in a row had
        // three different button widths and two different left edges — 74 pt
        // for «Connect», 100 for «Подключить» — with up to 122 pt of empty card
        // beside each. v3 spells it `.btn.wide { width: 100% }`.
        if up {
            Button { vm.disconnect(c.name) } label: {
                Text(VPNStr.disconnect).frame(maxWidth: .infinity)
            }
            .disabled(transitioning)
            .accessibilityLabel("\(VPNStr.disconnect), \(c.name)")
        } else {
            // Prominent, because on a page of cards the one thing to press is
            // «connect» and there is no other candidate for the accent.
            Button { vm.connect(c.name) } label: {
                Text(VPNStr.connect).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(transitioning)
            .accessibilityLabel("\(VPNStr.connect), \(c.name)")
        }
    }

    private func failureText(_ f: VPNFailure) -> String {
        switch f.reason {
        case .noSuchService: return VPNStr.failureNoSuchService(f.name)
        case .refused: return VPNStr.failureRefused(f.name)
        }
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
            // One block, not two grey paragraphs at two sizes stacked in a
            // card — `.callout` over `.caption`, which read as a paragraph that
            // had lost its heading. The scope note below stays where it is: it
            // is for the person who *has* rules, and that is the one this
            // branch is not about.
            HelmEmptyState(symbol: "app.badge.checkmark",
                           tint: VPNDescriptor.tint.colour,
                           message: VPNStr.perAppHint) { EmptyView() }
        }
        // What the tunnel actually covers. Kept out of the `isEmpty` branch on
        // purpose — the person with rules already configured is the one acting
        // on the belief that only that app is routed.
        Text(VPNStr.perAppScopeNote)
            .font(.caption)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
        // No `Divider()` between them. A grouped `Form` draws its own
        // separators, and each direct child of a `Section` is a **row** — so an
        // explicit divider became a row of its own, with a row's padding, and
        // the list came out with a 40 pt empty band between every pair of
        // apps. Keep Awake's list of the same shape has never had one.
        ForEach(sortedBundleIDs, id: \.self) { bundleID in
            appRuleRow(bundleID)
        }
        Button {
            pickApp()
        } label: {
            // A row of the list it adds to, in the accent — the shape Keep
            // Awake settled on and the one v3 draws. As a bordered `Label` it
            // was a chip sitting in a column of plain rows, its fill starting
            // 1 pt left of the copy above it and its title 36 pt right of it.
            // The 22 pt box is the app icon's column, so the two agree by
            // construction rather than by coincidence.
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                Text(VPNStr.addApp)
            }
            .foregroundStyle(Color.accentColor)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
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
                // The name the rule actually holds, even when the system no
                // longer has it. A `Picker` whose selection matches no tag
                // draws **blank**, so an orphaned rule showed an empty control
                // beside a note explaining that «Old office» is gone — the one
                // row where the page had something to say showed nothing at
                // all. v3 answers this with a «Choose another» button; the
                // picker *is* that button, and it only had to be able to
                // display where it currently points.
                if let held = rules[bundleID]?.vpnName,
                   !vm.connections.contains(where: { $0.name == held }) {
                    Text(VPNStr.missingConnection(held)).tag(held)
                    Divider()
                }
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
