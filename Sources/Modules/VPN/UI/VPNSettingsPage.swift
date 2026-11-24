import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// Settings page for the VPN module. Connections are read live from the view
/// model; per-app automation rules are seeded from the `NamespacedStore` into
/// local `@State` and written through the model (`saveRules`) on every change.
struct VPNSettingsPage: View {
    /// The three the per-app rules half reads, which lives in
    /// `VPNAppRules.swift`; kept here so the rules are seeded and written back
    /// in one place.
    @ObservedObject var vm: VPNViewModel
    @State var rules: [String: VPNAppRule]

    private let notice: VPNNotice
    private let dropNotice: VPNNotice
    private let spin: Bool
    private let spinTintConnected: String
    private let spinTintDisconnected: String
    /// Whether the grid is showing everything or only its first six. Not
    /// stored: it is a state of this visit to the page.
    @State private var showAllConnections = false
    /// Which tunnel the strip is about, by name. **Not stored**, like the flag
    /// above. Nil means «the first», the one carrying the traffic, and so does
    /// a name whose tunnel has dropped (`VPNTunnelChoice.chosen`).
    @State private var selectedTunnel: String?
    /// The per-connection overrides, seeded from the store and written through
    /// the model on every change, like the rules.
    @State private var noticeBook: VPNNoticeBook

    init(vm: VPNViewModel, store: NamespacedStore) {
        self.vm = vm
        // From the store rather than from `vm`, which is main-actor isolated
        // while this initializer is not. Nothing here may reach
        // `UNUserNotificationCenter.current()`: it ends a test run, and tests
        // build this page.
        let settings = VPNSettings(store: store)
        _rules = State(initialValue: VPNRules.decode(settings.rulesJSON))
        self.notice = settings.notice
        self.dropNotice = settings.dropNotice
        self.spin = settings.automationSpin
        self.spinTintConnected = settings.spinTint(for: .connected)
        self.spinTintDisconnected = settings.spinTint(for: .disconnected)
        _noticeBook = State(initialValue: settings.noticeBook)
    }

    var body: some View {
        vpnForm
    }

    /// Whether there is anything for the closing notes to qualify.
    private var hasConnections: Bool { !vm.connections.isEmpty }

    /// **The hero, then the heading, then the connections.**
    ///
    /// All three ride on one section's header, which puts the hero above the
    /// page's first card rather than inside it: a grouped `Form` draws a
    /// header outside its card, and a hero is not a row. Built like
    /// `LayoutSettingsPage.heroAndTitle`.
    private var heroAndTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            VPNTunnelHero(vm.tunnels, selected: $selectedTunnel,
                          measuring: vm.measuring) { vm.measureSpeed($0) }
                // **Out to the cards' own column.** A grouped `Form` insets a
                // header further than its card; left in, the hero and the
                // connection cards would be two card systems. The hero puts its
                // *words* back in by the same amount.
                .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
                // The gap under the hero: a block riding on a header has no
                // footer to be spaced by.
                .padding(.bottom, HelmSpace.s7)
            HelmSectionTitle(VPNStr.connections())
            connectionsList
                // The gap the form puts under a heading; this block draws its
                // own cards, so it pays for it.
                .padding(.top, HelmLayout.groupedHeaderGap)
        }
    }

    /// **The two sentences that close the page, and they close it.**
    ///
    /// Between the grid and the hero they would cut apart two things that
    /// belong together; macOS puts such a sentence *under* the group it
    /// qualifies.
    private var closingNotes: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Text(VPNStr.connectionsHint)
            Text(VPNStr.perAppScopeNote)
        }
        .helmQuietDetail()
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Everything the page has to say that is not about one configuration.
    ///
    /// Order is by how much it costs to ignore: a refusal answers something just
    /// pressed, a locked secret is a standing state that stops every rule on that
    /// tunnel, and an orphaned rule is a rule that will never fire.
    @ViewBuilder
    private var news: some View {
        if let failure = vm.lastFailure {
            HelmBanner(VPNStr.failure(failure), symbol: "exclamationmark.triangle.fill")
        }
        // **Every locked configuration, not only the ones no rule speaks for.**
        // A rule's own row is hidden behind its card's popover, so this banner
        // is the only place the page says the configuration cannot connect.
        ForEach(vm.secretsBehindAPrompt, id: \.self) { name in
            HelmBanner(VPNStr.secretNeedsAPress(name), symbol: "key.slash.fill")
        }
        // `VPNTenants.orphaned` refuses to answer on an empty list, so a refused
        // `scutil` read cannot produce this sentence.
        let orphans = VPNTenants.orphaned(rules, connections: vm.connections.map(\.name))
        if !orphans.isEmpty {
            HelmBanner(VPNStr.orphanedRules(orphans.count),
                       symbol: "exclamationmark.circle.fill")
        }
    }

    private var vpnForm: some View {
        Form {
            // **One section.** The rules and the notices are popovers on their
            // card, so what is left is the configurations and the sentences
            // that qualify them. **The news is rows**: a grouped `Form` gives
            // a row the same geometry as everything else on the page.
            Section {
                news
            } header: {
                heroAndTitle
            } footer: {
                // Under the group they qualify.
                if hasConnections { closingNotes }
            }
        }
        .formStyle(.grouped)
        .helmIdlesOffScreen()
        // The model asks the engine nothing in `init`, so without these the
        // page would show what the system said when the module came on.
        .task {
            vm.refresh()
            await vm.refreshBannerAuthorization()
        }
        .helmOnAppActive {
            vm.refresh()
            Task { await vm.refreshBannerAuthorization() }
        }
    }

    // MARK: - Connections

    /// The cards on screen: what is up first, and only as many as the grid
    /// draws before somebody asks for the rest.
    ///
    /// `VPNConnectionOrder` and `VPNGridLayout.shown` applied in the one order
    /// they can be: cap the list after it is sorted, never before.
    /// Not `private`: `TheGridShowsWhatMattersFirstTests` asks the page itself
    /// rather than re-deriving the two rules beside it.
    var shownConnections: [VPNConnection] {
        let ordered = VPNConnectionOrder.upFirst(vm.connections)
        return Array(ordered.prefix(VPNGridLayout.shown(ordered.count,
                                                        expanded: showAllConnections)))
    }

    @ViewBuilder
    private var connectionsList: some View {
        if vm.connections.isEmpty {
            // A destination: the module cannot create a configuration (no
            // `scutil --nc create`), so it takes the person where they are made.
            HelmEmptyState(symbol: "lock.shield",
                           tint: VPNDescriptor.tint.colour,
                           title: VPNStr.noVPNsSystem,
                           message: VPNStr.noVPNsExplain,
                           note: VPNStr.noVPNsNote) {
                Button(VPNStr.openNetworkSettings) { PermissionCheck.openNetworkSettings() }
                .buttonStyle(.borderedProminent)
            }
        } else {
            // **The columns, their least and their ceiling are `VPNGridLayout`'s.**
            let total = vm.connections.count
            let columns = VPNGridLayout.columns(for: total)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: VPNGridLayout.cardMinimum,
                                                                   maximum: VPNGridLayout.cardCeiling),
                                                         spacing: HelmSpace.s5),
                                     count: columns),
                      alignment: .leading,
                      spacing: HelmSpace.s5) {
                // Up first (`VPNConnectionOrder`): in `scutil`'s order the
                // connected tunnel can be the ninth, and the cap would hide it.
                ForEach(shownConnections) { connection in
                    connectionCard(connection)
                }
            }
            // Back out to the section cards' own edge: cards sit level with
            // cards, text at the header inset.
            .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
            if total > VPNGridLayout.collapsedLimit {
                // A row of the list it lengthens, in the accent: a bordered chip
                // in a column of cards reads as belonging to something else.
                // `interface`, not `disclosure`: nothing here is measured and
                // clipped, the cards are mounted and unmounted.
                Button {
                    withAnimation(HelmMotion.interface) { showAllConnections.toggle() }
                } label: {
                    Text(showAllConnections ? VPNStr.showFewerConnections
                                            : VPNStr.showAllConnections(total))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, HelmSpace.s4)
            }
        }
    }

    /// One configuration, as a card with two doors.
    ///
    /// The page owns the rules table and the notice book; the card owns only
    /// what is open (`VPNConnectionCard`).
    private func connectionCard(_ c: VPNConnection) -> some View {
        let book = noticeBook
        let shown = book.shown(for: c.id, rules: notice, drop: dropNotice)
        let mine = VPNTenants.of(c.name, rules: rules, sorted: { AppInfo.sortedByName($0) })
        return VPNConnectionCard(
            connection: c,
            strip: mine,
            timings: rules.mapValues(\.timing),
            refusals: vm.ruleRefusals,
            heldByHelm: c.status.isConnected && vm.autoConnected.contains(c.name),
            notice: shown.rules,
            dropNotice: shown.drop,
            spin: book.spin(for: c.id, fallback: spin),
            tintUp: book.tint(for: c.id, kind: .connected, fallback: spinTintConnected),
            tintDown: book.tint(for: c.id, kind: .disconnected, fallback: spinTintDisconnected),
            bannerAuthorization: vm.bannerAuthorization,
            elsewhere: VPNTenants.elsewhere(than: c.name, connections: vm.connections),
            connect: { vm.connect(c.name) },
            disconnect: { vm.disconnect(c.name) },
            addApp: { pickApp(into: c.name) },
            setTiming: { bundleID, timing in
                guard var rule = rules[bundleID] else { return }
                rule.set(timing)
                rules[bundleID] = rule
                persist()
            },
            move: { bundleID, name in
                guard var rule = rules[bundleID] else { return }
                rule.vpnName = name
                rules[bundleID] = rule
                persist()
            },
            remove: { bundleID in
                rules.removeValue(forKey: bundleID)
                persist()
            },
            setNotice: { chosen in
                noticeBook = vm.chooseNotice(chosen, for: .connected, on: c.id)
            },
            setDropNotice: { chosen in
                noticeBook = vm.chooseNotice(chosen, for: .dropped, on: c.id)
            },
            setSpin: { on in
                noticeBook = vm.updateNoticeBook { $0.setting(c.id, spin: on) }
            },
            setTint: { kind, token in
                noticeBook = vm.updateNoticeBook { $0.setting(c.id, tint: token, for: kind) }
            })
    }

}
