import SwiftUI
import AppKit
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// Settings page for the VPN module. Connections are read live from the view
/// model; per-app automation rules are seeded from the `NamespacedStore` into
/// local `@State` and written through on every change, notifying the engine
/// via `reloadRules`.
struct VPNSettingsPage: View {
    /// The three the per-app rules half reads, which lives in `VPNAppRules.swift`
    /// — `private` is per file, and one `@State` of the rules seeded and written
    /// back in one place is the point of keeping them here.
    @ObservedObject var vm: VPNViewModel
    let store: NamespacedStore
    @State var rules: [String: VPNAppRule]

    @State private var notice: VPNNotice
    @State private var dropNotice: VPNNotice
    @State private var spin: Bool
    @State private var spinTintConnected: String
    @State private var spinTintDisconnected: String
    /// Natural height of the two swatch rows, measured so the disclosure
    /// animates between 0 and a concrete value — the same pattern
    /// `UtilitiesSection` in `HelmPanel.swift` uses for its rows.

    init(vm: VPNViewModel, store: NamespacedStore) {
        self.vm = vm
        self.store = store
        // From the store rather than from `vm`, which is main-actor isolated
        // while this initializer is not. Nothing here may reach macOS's
        // notification centre: `UNUserNotificationCenter.current()` ends a test
        // run outright, and this page is constructed in one.
        let settings = VPNSettings(store: store)
        _rules = State(initialValue: VPNRules.decode(settings.rulesJSON))
        _notice = State(initialValue: settings.notice)
        _dropNotice = State(initialValue: settings.dropNotice)
        _spin = State(initialValue: settings.automationSpin)
        _spinTintConnected = State(initialValue: settings.spinTint(for: .connected))
        _spinTintDisconnected = State(initialValue: settings.spinTint(for: .disconnected))
    }

    var body: some View {
        vpnForm
    }

    /// **Is there anything on this Mac for the rest of the page to be about.**
    ///
    /// Asked in four places — the heading over the rules, the rules themselves,
    /// their footer and the two cards below — because a `Form` builds a header,
    /// a body and a footer in three separate closures. One name, so those four
    /// cannot come to mean four slightly different things.
    private var hasConnections: Bool { !vm.connections.isEmpty }

    /// The connections block, and the heading of the section it rides on.
    private var connectionsAndTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HelmSectionTitle(VPNStr.connections)
            connectionsList
            if hasConnections {
                Text(VPNStr.connectionsHint)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            if let failure = vm.lastFailure {
                HelmBanner(VPNStr.failure(failure), symbol: "exclamationmark.triangle.fill")
                    .padding(.top, HelmSpace.s4)
                    // **It has a fill, so it is a card.** A section header is
                    // inset 10 pt further than the section's own card, which is
                    // right for text and wrong for a filled field: measured, the
                    // banner ran 30…713 against 20…723 for every card on the
                    // page. Back out the same way the connections grid does.
                    .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
            }
            if hasConnections {
                // The gap the grouped form puts between a card and the next
                // heading, which this block is now standing in for.
                HelmSectionTitle(VPNStr.perAppAutomation)
                    .padding(.top, HelmSpace.s7)
            }
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
            // **Nothing below the empty state, at zero connections.** The three
            // sections under this one configure what happens when a rule fires
            // and how a firing is announced — events that cannot happen on a Mac
            // with no VPN configured — and they were 800 pt of them, ending in a
            // second empty state inside the rules card. The one thing this page
            // can do for that person is the button in the empty state, and it
            // was below the fold behind settings for a feature they have not
            // got.
            Section {
                if hasConnections { appRulesEditor }
            } header: {
                connectionsAndTitle
            } footer: {
                // What the tunnel actually covers: a **footer**, which is where
                // macOS puts the sentence that qualifies a group and where this
                // same page already puts the hint under its connections. It was
                // the card's last row — the one row of that card that is not a
                // rule, drawn at a row's inset with a separator over it.
                if hasConnections {
                    Text(VPNStr.perAppScopeNote)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if hasConnections {
                Section(header: HelmSectionTitle(VPNStr.noticeSection)) {
                    noticePicker
                }

                Section(header: HelmSectionTitle(VPNStr.spinSection)) {
                    spinControls
                }
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
        // **The shape General settings asks its picture question in**: a
        // labelled row, with the pictures on the trailing side —
        // `AppearancePicker` and this are the same control now, so they are the
        // same size, radius, ring and label weight without anybody keeping them
        // in step.
        //
        // The label came back, and it is not the sub-heading that was taken out
        // of this card. That was a second *title* over one control saying what
        // the section header already said. There are two controls here, each
        // deciding a different event, and a row label is how every other row in
        // this form names what it sets.
        LabeledContent(VPNStr.noticeRuleLabel) {
            noticeCards(selection: Binding(
                get: { notice },
                set: { chosen in
                    notice = chosen
                    Task { await vm.choose(chosen) }
                }), label: VPNStr.noticeRuleLabel)
        }
        Text(VPNStr.noticeHint)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)

        // The second event, and the reason this section is a pair. Everything
        // else here is Helm doing what it was asked; this is the arrangement
        // failing, and from that moment the Mac is sending in clear while the
        // last thing the person was told is that it was not.
        LabeledContent(VPNStr.noticeDropLabel) {
            noticeCards(selection: Binding(
                get: { dropNotice },
                set: { chosen in
                    dropNotice = chosen
                    Task { await vm.choose(chosen, for: .dropped) }
                }), label: VPNStr.noticeDropLabel)
        }
        Text(VPNStr.noticeDropHint)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)

        // Where the switch is, not only in the app's permission list: a mode
        // macOS refuses looks exactly like one it allows.
        //
        // **Once for the card, and both rows are in the question.** Each row
        // used to ask it for itself, so choosing the banner for both events and
        // then revoking the permission drew the same sentence twice, 20 pt
        // apart, and took the card from 285 to 423 pt. `permissionMissing` is
        // that question with a test under it.
        if VPNNotice.permissionMissing(among: [notice, dropNotice],
                                       authorization: vm.bannerAuthorization) {
            HelmPermissionNote(text: VPNStr.noticeDenied,
                               openSettings: PermissionCheck.openNotificationSettings)
        }
    }

    /// **The card the three labels have to fit.** Wider than the appearance
    /// picker's 74 pt, and capped near 140 by the row label beside it — «Wenn ein
    /// Tunnel von selbst abbricht» is 219.1 pt of the 680 the row has. Named
    /// rather than typed at the call site because
    /// `TheNoticeLabelsFitTheCardTests` measures the labels against it: a number
    /// spelled twice is a number one side can change alone.
    static let noticeThumbnail = CGSize(width: 104, height: 66)

    /// The three pictures. Written once: the two rows choose between the same
    /// three outcomes, and a second copy is a second place for them to drift.
    private func noticeCards(selection: Binding<VPNNotice>, label: String) -> some View {
        HelmChoiceCards(selection: selection,
                        items: [
                            .init(id: .silent, label: VPNStr.noticeOption(.silent),
                                  preview: NoticePreview.of(.silent)),
                            .init(id: .menuBar, label: VPNStr.noticeOption(.menuBar),
                                  preview: NoticePreview.of(.menuBar)),
                            .init(id: .system, label: VPNStr.noticeOption(.system),
                                  preview: NoticePreview.of(.system)),
                        ],
                        thumbnail: Self.noticeThumbnail)
            // Two unnamed groups of three identical-sounding buttons in one
            // card is what a screen reader would otherwise be handed.
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
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
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmSignal.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Connections

    /// The widest a connection card may grow: **half the row**, less the gap
    /// beside it. Derived rather than typed, so it stays true if the settings
    /// column moves — and it is a rule rather than a number. One connection
    /// gets a half-row card instead of a 704 pt banner; two fill the row
    /// exactly and finish level with the card below.
    private static var cardCeiling: CGFloat { (HelmLayout.cardWidth - 12) / 2 }

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
            // **Columns from the count, capped at three, each free to grow to
            // 340.** Both halves are measured rather than chosen.
            //
            // `.adaptive(minimum: 190, maximum: 280)` fixes the column count
            // from the *width*, so a Mac with two VPNs got three columns and
            // used two: photographed at the settings column, two 221 pt cards
            // ending at x=532 with 233 pt of nothing to their right and a
            // full-width line of explanation underneath drawing a line right
            // across it. Columns from the count alone was the opposite fault —
            // one connection became a 704 pt card with a 680 pt button across
            // it, which is a card the size of a paragraph.
            //
            // The ceiling is what keeps a card card-shaped; the count is what
            // stops the row ending in a hole. Two connections now measure 346
            // each and finish flush with the card below. One still leaves
            // space beside it, and a single half-row card under a heading
            // reads as one VPN rather than as a grid that failed to fill.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 190,
                                                                   maximum: Self.cardCeiling),
                                                         spacing: 12),
                                     count: min(max(vm.connections.count, 1), 3)),
                      alignment: .leading,
                      spacing: 12) {
                ForEach(vm.connections) { connection in
                    connectionCard(connection)
                }
            }
            // Back out to the section cards' own edge. These are cards, and the
            // headings and captions around them are text: the text belongs at
            // the header inset, level with what the rows below say, and the
            // cards belong level with the cards below.
            .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
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
        // not. The verb answers a third question, `VPNCardAction`, and it is
        // the engine's rather than this view's: what you can ask for while a
        // tunnel is coming up is to stop.
        let connected = c.status.isConnected
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
            // **No spinner beside the verb.** It shared the button's `HStack`,
            // so a card that started connecting moved its own button: measured,
            // 202.5 pt wide to 181.0 with the left edge travelling 22 pt, on the
            // one control the person was reaching for. The state is already said
            // in words on the line above — «Подключение…», in the readout face —
            // and v3 draws no spinner here. A gutter reserved for one would be a
            // 22 pt hole in every card that is not moving.
            connectionVerb(c)
        }
        .padding(12)
        // No `minHeight`. Measured: every card in a row comes out 116 pt —
        // including one with no protocol line — so the floor never applied to
        // anything and a number that never applies is a claim nobody can check.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
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
            RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .strokeBorder(connected ? HelmSignal.success : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func connectionVerb(_ c: VPNConnection) -> some View {
        // Which verb, and whether it can be pressed, is the engine's question —
        // `VPNCardAction`, beside `isUp`. Answered here it was answered wrongly:
        // the button was disabled for *every* transition, so a tunnel stuck on
        // «connecting» left a card with nothing on it to press, under the
        // comment above promising the opposite.
        let action = VPNCardAction.of(c.status)
        // Which word, from the same table: three of them, where the tool has two
        // directions. A handshake being abandoned is «Cancel» — 接続解除 is
        // *release the connection* and there is none yet — and a tunnel on its
        // way down keeps the word that was pressed while it is dimmed.
        let word = VPNStr.cardWord(action.word)
        // **The frame goes on the label, not on the button.**
        // `.frame(maxWidth: .infinity)` applied to a macOS bordered control
        // does not stretch it — the control hugs its title and centres itself
        // in the space instead. Measured in an offscreen window at a 171 pt
        // content width: on the button the control starts at x=60; on the label
        // it starts at x=12 and fills. Left as it was, three cards in a row had
        // three different button widths and two different left edges — 74 pt
        // for «Connect», 100 for «Подключить» — with up to 122 pt of empty card
        // beside each. v3 spells it `.btn.wide { width: 100% }`.
        switch action.verb {
        case .disconnect:
            Button { vm.disconnect(c.name) } label: {
                Text(word).frame(maxWidth: .infinity)
            }
            .disabled(!action.enabled)
            .accessibilityLabel("\(word), \(c.name)")
        case .connect:
            // Prominent, because on a page of cards the one thing to press is
            // «connect» and there is no other candidate for the accent.
            Button { vm.connect(c.name) } label: {
                Text(word).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!action.enabled)
            .accessibilityLabel("\(word), \(c.name)")
        }
    }

    private func prettyKind(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for k in ["L2TP", "IKEv2", "IPSec", "WireGuard", "PPTP"] where raw.contains(k) { return k }
        return raw.split(separator: ":").first.map(String.init)
    }

    private func statusText(_ status: VPNStatus) -> String { VPNStr.status(status) }
}
