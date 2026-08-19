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
    /// Whether the grid is showing everything or only its first six. Not
    /// stored: it is a state of this visit to the page, and a person who left
    /// it expanded three weeks ago is not asking for a screenful of cards now.
    @State private var showAllConnections = false
    /// Which tunnel the strip is about, by name. **Not stored**, for the reason
    /// the flag above is not: it is a state of this visit, and somebody who left
    /// it on a tunnel three weeks ago is not asking for that tunnel now. Nil
    /// means «the first», which is the one carrying the traffic — and a name
    /// whose tunnel has dropped means the same, because the list is rewritten
    /// under this whenever the network moves (`VPNTunnelChoice.chosen`).
    @State private var selectedTunnel: String?
    /// The per-connection overrides, seeded from the store and written through
    /// on every change — the same shape the rules have, for the same reason.
    @State private var noticeBook: VPNNoticeBook
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
        _noticeBook = State(initialValue: settings.noticeBook)
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

    /// **The hero, then the heading, then the connections.**
    ///
    /// All three ride on one section's header, which is what puts the hero
    /// above the page's first card rather than inside it — the same
    /// construction `KeepAwakeSettingsPage.heroAndTitle` uses, and for the same
    /// reason: a grouped `Form` draws a section's header outside its card, and
    /// a hero is not a row.
    private var heroAndTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            VPNTunnelHero(vm.tunnels, selected: $selectedTunnel,
                          measuring: vm.measuring) { vm.measureSpeed($0) }
                // **Out to the cards' own column.** A grouped `Form` insets a
                // section header ten points further than the section's card, and
                // the hero draws a surface — its readings ran 80…764 against the
                // connection cards' 70…774, which is two card systems on one page.
                // The same line `connectionsList` carries below, for the same
                // reason; the hero puts its *words* back in by the same amount.
                .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
                // The gap under the hero, paid here for the reason the old
                // «This tunnel» heading paid its own: a grouped `Form` spaces
                // its sections by their footers, and a block riding on a header
                // has no footer of its own to be spaced by.
                .padding(.bottom, HelmSpace.s7)
            HelmSectionTitle(VPNStr.connections())
            connectionsList
                // The gap the form itself puts under a heading. Every other
                // section on this page gets it for free, because the form draws
                // their cards; this block draws its own, so it pays for it.
                .padding(.top, HelmLayout.groupedHeaderGap)
        }
    }

    /// **The two sentences that close the page, and they close it.**
    ///
    /// They used to sit between the connections grid and the tunnel strip —
    /// 80 pt of grey text cutting apart the two things on this page that belong
    /// together, one of them as a header's tail and the other as that section's
    /// footer. macOS puts a sentence of this kind *under* the group it
    /// qualifies, so both go under the last group there is.
    ///
    /// Which group that is used to be a question — the strip had a section of
    /// its own and it was absent with nothing to be about. There is one section
    /// now, so the answer is unconditional.
    private var closingNotes: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Text(VPNStr.connectionsHint)
            Text(VPNStr.perAppScopeNote)
        }
        .font(HelmText.rowDetail)
        .foregroundStyle(HelmText.quiet)
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
        // `VPNRules.unspokenFor` used to remove the ones a rule covered, because
        // that rule's own row said the same sentence 230 pt lower and named the
        // application whose automation was dead. The rules are behind a door on
        // their card now: that row is invisible until somebody opens the popover,
        // so removing the banner left a configuration that cannot connect saying
        // so nowhere. One sentence per configuration, on the page.
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
            // **One section now.** The rules and the notices used to be two more
            // sections and 800 pt of page; they are two popovers on the card
            // that owns them, so what is left is the configurations, the one
            // thing that cannot be said anywhere else, and the two sentences
            // that qualify them.
            // **The news is rows.** A refusal, a configuration whose secret
            // nobody has pressed for, a rule pointing at a tunnel that is gone —
            // each is a filled field, and a row is where a grouped `Form` gives
            // it the same geometry as everything else on the page. They used to
            // ride the header with `-groupedHeaderOutset` backing the inset out
            // by hand; that hack is what a row is for.
            Section {
                news
            } header: {
                heroAndTitle
            } footer: {
                // The two sentences that qualify the connections, under the
                // group they qualify — which is now the only group there is.
                if hasConnections { closingNotes }
            }
        }
        .formStyle(.grouped)
        .helmSettingsColumn()
        // The engine is asked once in `init` and the view model is cached for
        // the app's lifetime, so without these the page showed whatever the
        // system said at launch.
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
    /// Both halves are somebody else's question — `VPNConnectionOrder` is the
    /// engine's, `VPNGridLayout.shown` is the grid's — so this is the two of
    /// them applied in the one order they can be applied in: cap the list after
    /// it is sorted, never before.
    /// Not `private`: `TheGridShowsWhatMattersFirstTests` asks the page itself
    /// rather than re-deriving the two rules beside it, which is the shape of
    /// test that agrees with the page by construction and with the screen by
    /// coincidence.
    var shownConnections: [VPNConnection] {
        let ordered = VPNConnectionOrder.upFirst(vm.connections)
        return Array(ordered.prefix(VPNGridLayout.shown(ordered.count,
                                                        expanded: showAllConnections)))
    }

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
            // **The columns are `VPNGridLayout`'s, and the ceiling is ours.**
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
            // `min(count, 3)` was the answer to both, and it was right for one
            // and two and wrong from four: photographed, four connections drew
            // 3+1 with 477 pt of empty row beside the last card. The rule and
            // the reason it has a threshold now live in `VPNGridLayout`, with
            // `TheGridLeavesNoHoleTests` behind it; the ceiling stays here,
            // because it is what keeps a card card-shaped.
            let total = vm.connections.count
            let columns = VPNGridLayout.columns(for: total)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 190,
                                                                   maximum: Self.cardCeiling),
                                                         spacing: 12),
                                     count: columns),
                      alignment: .leading,
                      spacing: 12) {
                // What is up first (`VPNConnectionOrder`), because from here on
                // the page hides the tail: in `scutil`'s own order the connected
                // tunnel can be the ninth, and a cap without an order would put
                // the one card this page is for behind a button.
                ForEach(shownConnections) { connection in
                    connectionCard(connection)
                }
            }
            // Back out to the section cards' own edge. These are cards, and the
            // headings and captions around them are text: the text belongs at
            // the header inset, level with what the rows below say, and the
            // cards belong level with the cards below.
            .padding(.horizontal, -HelmLayout.groupedHeaderOutset)
            if total > VPNGridLayout.collapsedLimit {
                // A row of the list it lengthens, in the accent — the same
                // shape «Add app…» draws one card below, for the same reason:
                // a bordered chip in a column of cards reads as a control that
                // belongs to something else.
                // `interface`, not `disclosure`. The disclosure token belongs to
                // a height that is measured and clipped — the panel's accordion,
                // Keep Awake's ⋯ block — and nothing here is measured: the cards
                // are mounted and unmounted, so this is the token's other case,
                // «toggling a filter», which is what the button does.
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
    /// Everything it needs is handed to it: the page owns the rules table and
    /// the notice book, the card owns only what is open. `VPNConnectionCard`
    /// carries the reasoning for the doors themselves.
    private func connectionCard(_ c: VPNConnection) -> some View {
        let book = noticeBook
        let shown = book.shown(for: c.id, rules: notice, drop: dropNotice)
        let mine = VPNTenants.of(c.name, rules: rules, sorted: { AppInfo.sortedByName($0) })
        return VPNConnectionCard(
            connection: c,
            strip: mine,
            timings: rules.mapValues(\.timing),
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
                write(book.setting(c.id, notice: chosen))
                Task { await vm.choose(chosen) }
            },
            setDropNotice: { chosen in
                write(book.setting(c.id, drop: chosen))
                Task { await vm.choose(chosen, for: .dropped) }
            },
            setSpin: { on in write(book.setting(c.id, spin: on)) },
            setTint: { kind, token in write(book.setting(c.id, tint: token, for: kind)) })
    }

    /// The book, and the one place it is written.
    private func write(_ book: VPNNoticeBook) {
        noticeBook = book
        VPNSettings(store: store).setNoticeBook(book)
    }

}
