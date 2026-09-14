import SwiftUI
import HelmUI
import Module_Homebrew_Engine

// The three `Identifiable` conformances that used to sit here are on the models
// themselves now, spelled once through `BrewKey` — the same key the description
// cache is read by, which is the half that has to agree with the row.

struct HomebrewSettingsPage: View {
    @ObservedObject private var hb: HomebrewViewModel
    @State private var query = ""
    /// The search a press of Return started, held so the next press can drop it.
    ///
    /// **Every press used to be its own `Task` and nothing held any of them.**
    /// One search is two `brew search` runs — measured at about nine seconds —
    /// and a `brew desc` per kind after them, so ten presses were ten of those
    /// chains at once. What stops the *work* is `HelmProcess.launchCeiling` and
    /// the `LatestRequest` in the view model; this is the third of the three and
    /// the smallest: it keeps the tasks themselves from piling up, one per
    /// keystroke, each holding its own await for the life of a `brew` run.
    ///
    /// Cancelling does not stop the tool, and nothing here pretends it does —
    /// the child is the engine's and runs to its end.
    @State private var searching: Task<Void, Never>?

    init(vm: ModuleViewModel) { hb = HomebrewViewModel.shared(vm: vm) }

    var body: some View {
        VStack(spacing: 0) {
            if hb.status.installed {
                managerBody
            } else {
                installScreen
            }
            if !hb.consoleLines.isEmpty || hb.running {
                Divider()
                console
            }
        }
        // The view model outlives this page, so a return visit shows what is
        // already loaded instead of paying for `brew list` and a `brew desc`
        // batch again.
        .task { await hb.loadIfNeeded() }
        // The other side of that: the view model outliving the page is exactly
        // why the page has to say it has gone. An uninstall ask is asked over
        // the transport and can be out for the whole query deadline, and the
        // `Task` the press launches is not tied to this subtree — so switching
        // modules or closing Settings leaves a query whose answer would set
        // `pendingUninstall` on a view model with nothing mounted, and the next
        // visit to Homebrew opens a confirmation for the app's only
        // irreversible deletion that nobody asked for. `LatestRequest` retires
        // work on a later press and on a cancel; leaving is neither, and this
        // is the one place that knows it happened
        // (`LeavingThePageRetiresAnUninstallAskTests`). This page also carries
        // `.helmIdlesOffScreen()`, so hiding the app or occluding the Settings
        // window unmounts this subtree and fires this too — dismissing a
        // confirmation dialog the person had left standing on screen rather
        // than leaving it to act later on a reading taken before the
        // interruption, which is the right call for the app's only
        // irreversible deletion.
        .onDisappear { hb.cancelUninstall() }
        // Removing a cask removes an application. Every other destructive
        // action in Helm asks first; this one used to go on a single click.
        .confirmationDialog(hb.pendingUninstall.map { HbStr.confirmUninstall($0.name) } ?? "",
                            isPresented: Binding(get: { hb.pendingUninstall != nil },
                                                 set: { if !$0 { hb.cancelUninstall() } }),
                            titleVisibility: .visible) {
            Button(HbStr.uninstall, role: .destructive) { hb.confirmUninstall() }
            Button(HbStr.cancel, role: .cancel) { hb.cancelUninstall() }
        } message: {
            // Two sentences, and the second only when there is something to say:
            // a heading over an empty list reads as a reassurance that nothing
            // depends on this, which a refused query has not earned.
            if hb.dependentsOfPending.isEmpty {
                Text(HbStr.uninstallIsPermanent)
            } else {
                Text(HbStr.uninstallIsPermanent + "\n\n"
                     + HbStr.stillNeededBy + "\n"
                     + hb.dependentsOfPending.joined(separator: ", "))
            }
        }
    }

    // MARK: - Not installed

    /// The same pane draws `HelmEmptyState` with the module switched off; this
    /// used to replace it in place with a hand-rolled second one — 16 pt stack
    /// spacing against 14, a 20 pt title against 17, a 12 pt body against 13,
    /// and a button pinned to 260 pt. One flick of the switch showed both.
    ///
    /// **The tint is the module's, not the category's.** This comment used to
    /// say the colour was «read off the descriptor rather than written as
    /// `.pink`» — and it was reading `category.tint`, which is `.pink` reached
    /// the long way round and shared with two other modules. The plate in the
    /// page header above it was already green.
    private var installScreen: some View {
        HelmEmptyState(symbol: "shippingbox",
                       tint: HomebrewDescriptor.tint.colour,
                       title: HbStr.notInstalledTitle,
                       message: HbStr.notInstalledBody) {
            Button {
                hb.installBrew()
            } label: {
                Label(HbStr.installBrew, systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(hb.running)
        }
    }

    // MARK: - Manager

    /// Counts as a quiet status line rather than a panel of dials.
    ///
    /// Internal rather than private, for the reason the Uninstaller's
    /// `statusLine` gives: which sentence stands over which loading state is
    /// the whole of a fix, and a `body` is not somewhere a test can reach.
    var statusLine: String {
        // A count that has not arrived is not a count of zero. The list reloads
        // after every operation, and for that second the line read
        // "0 packages · 0 updates · 0 casks" over a machine with 53 of them.
        guard hb.loadedInstalled else { return HbStr.packagesLoading }
        // The same rule for updates, which this guard fixed only half of the
        // first time: `loadIfNeeded` deliberately never asks `brew outdated`,
        // so on first open the line said «Updates: 0» about a question with no
        // answer — for as long as nobody visited the Updates tab.
        guard hb.loadedOutdated else {
            return HbStr.packagesStatusNoUpdates(hb.installed.count,
                                                 hb.installed.filter(\.isCask).count)
        }
        return HbStr.packagesStatus(hb.installed.count,
                             hb.outdated.count,
                             hb.installed.filter(\.isCask).count)
    }

    private var managerBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: HelmSpace.s5) {
                Picker(HelmA11y.whatToShow, selection: $hb.segment) {
                    Text(HbStr.segInstalled).tag(HomebrewViewModel.Segment.installed)
                    Text(HbStr.segUpdates).tag(HomebrewViewModel.Segment.updates)
                    Text(HbStr.segSearch).tag(HomebrewViewModel.Segment.search)
                }
                .pickerStyle(.segmented).labelsHidden()
                // Its own width, not 300: the control asks 226.5 pt in English
                // and 370.5 in Japanese, so a fixed number clipped four
                // languages and centred the rest — which walked the row's left
                // edge from 20 pt to 75.5 while every row below it starts at 20.
                .fixedSize()
                .onChange(of: hb.segment) { _, seg in
                    Task { await refresh(seg) }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await refresh(hb.segment) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .helmSteadySpin(hb.running)
                }
                .buttonStyle(.borderless)
                .disabled(hb.running)
                .help(HbStr.refreshList)
                .accessibilityLabel(HbStr.refreshList)
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
            Divider()
            // The split is asked of the pane, not of the window: `HomebrewSplit`
            // carries the measured threshold, and a `private var` inside `body`
            // would be out of a test's reach (`SearchDisplay.swift`'s own reason).
            GeometryReader { proxy in
                if HomebrewSplit(availableWidth: proxy.size.width).showsInspector {
                    HStack(spacing: HelmSpace.s5) {
                        listArea(showsDesc: false)
                            .frame(minWidth: 240, idealWidth: 310, maxWidth: 310)
                        Divider()
                        inspector
                            .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity,
                                  alignment: .topLeading)
                    }
                } else {
                    // No inspector at this width, so the description — the one
                    // thing the inspector was carrying — comes back to the row.
                    listArea(showsDesc: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Counts belong in a quiet bottom bar, like the other list screens;
            // the toolbar is for what you can do, not for what there is.
            Divider()
            HStack {
                Text(statusLine)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                Spacer()
            }
            // A caption is shorter than a button: without this the bar was
            // 38 pt where the other two list screens are 49, and the content
            // jumped when switching between them.
            .frame(minHeight: 25)
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private func listArea(showsDesc: Bool) -> some View {
        switch hb.segment {
        case .installed: installedList(showsDesc: showsDesc)
        case .updates: updatesList(showsDesc: showsDesc)
        case .search: searchView(showsDesc: showsDesc)
        }
    }

    private func installedList(showsDesc: Bool) -> some View {
        listOrEmpty(hb.installed, empty: hb.loadedInstalled ? HbStr.noneInstalled : nil,
                    busy: HbStr.packagesLoading) { pkg in
            pkgRow(name: pkg.name, detail: pkg.version, isCask: pkg.isCask,
                   hasUpdate: hasUpdate(pkg.id),
                   desc: showsDesc ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
        }
    }

    private func updatesList(showsDesc: Bool) -> some View {
        VStack(spacing: 0) {
            if !hb.outdated.isEmpty {
                HStack {
                    Spacer()
                    Button(HbStr.upgradeAll) { hb.upgradeAll() }.disabled(hb.running)
                }.padding(8)
                Divider()
            }
            listOrEmpty(hb.outdated, empty: hb.loadedOutdated ? HbStr.upToDate : nil,
                        busy: HbStr.checkingForUpdates) { pkg in
                // Pinned and cask never overlap — `brew pin` is formulae only —
                // so both badges may be drawn without choosing between them.
                pkgRow(name: pkg.name, detail: "\(pkg.installed) → \(pkg.latest)", isCask: pkg.isCask,
                       pinned: pkg.pinned,
                       desc: showsDesc ? hb.description(name: pkg.name, isCask: pkg.isCask) ?? " " : nil)
            }
        }
    }

    private func searchView(showsDesc: Bool) -> some View {
        VStack(spacing: 0) {
            HelmSearchField(text: $query, placeholder: HbStr.searchPlaceholder,
                            onSubmit: {
                                searching?.cancel()
                                searching = Task { await hb.search(query) }
                            })
                .frame(height: 22)
                .padding(.horizontal, HelmLayout.formInset)
                .padding(.top, 12)
                .padding(.bottom, HelmSpace.s5)
            Divider()
            if SearchDisplay.state(query: query, hasHits: !hb.searchHits.isEmpty) == .prompt {
                HelmEmptyState(message: HbStr.typeToSearch)
            } else {
                listOrEmpty(hb.searchHits, empty: HbStr.noResults, busy: HbStr.searching) { hit in
                    pkgRow(name: hit.name, detail: nil, isCask: hit.isCask,
                           alreadyInstalled: PackageStanding.installedVersion(of: hit.id,
                                                                              installed: hb.installed) != nil,
                           desc: showsDesc ? hb.description(name: hit.name, isCask: hit.isCask) ?? " " : nil)
                }
            }
        }
    }

    // MARK: - Inspector

    /// The right column: what `InspectorState.of` decides about the current
    /// selection, and nothing this page has not already read from `hb`.
    private var inspector: some View {
        Group {
            switch InspectorState.of(segment: hb.segment, selected: hb.selected,
                                     installed: hb.installed, outdated: hb.outdated,
                                     loadedOutdated: hb.loadedOutdated,
                                     hits: hb.searchHits, descriptions: hb.descriptions) {
            case .nothingSelected:
                HelmEmptyState(message: HbStr.nothingSelected)
            case let .package(subject):
                VStack(alignment: .leading, spacing: HelmSpace.s5) {
                    HStack(spacing: HelmSpace.s3) {
                        Text(subject.name).font(HelmText.sectionHeading)
                        if subject.isCask { HelmBadge(HbStr.cask, tint: .purple) }
                        if !subject.version.isEmpty {
                            Text(subject.version).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        }
                        Spacer(minLength: 0)
                        inspectorAction(subject)
                    }
                    // The same fact the row's dot carries, said in words here —
                    // the one place `InspectorSubject.updates` is read, since
                    // `.installed`'s own action stays Uninstall either way.
                    if case .available = subject.updates {
                        Label(HbStr.updateAvailable, systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(HelmSignal.warning)
                            .font(HelmText.rowDetail)
                    }
                    if let desc = subject.desc {
                        Text(desc).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    }
                    Spacer(minLength: 0)
                }
                .padding(HelmSpace.s5)
            }
        }
    }

    /// Looked up by `BrewKey` id and never by name — `docker` is both a
    /// formula and a cask, which is the defect `BrewKey` was written against.
    @ViewBuilder
    private func inspectorAction(_ subject: InspectorSubject) -> some View {
        switch subject.action {
        case .uninstall:
            Button(HbStr.uninstall) {
                guard let pkg = hb.installed.first(where: { $0.id == subject.id }) else { return }
                // Every other destructive action in Helm asks first; this one
                // removed a cask — an app — on a single click.
                Task { await hb.askToUninstall(pkg) }
            }
            .disabled(hb.running)
        case .upgrade:
            Button(HbStr.upgrade) {
                guard let pkg = hb.outdated.first(where: { $0.id == subject.id }) else { return }
                hb.upgrade(pkg)
            }
            .disabled(hb.running)
        case .install:
            Button(HbStr.install) {
                guard let hit = hb.searchHits.first(where: { $0.id == subject.id }) else { return }
                hb.install(hit)
            }
            .disabled(hb.running)
        case .pinned:
            // Still listed — somebody who pinned a formula still wants to know
            // a newer one exists — but not offered. `brew upgrade` answers a
            // pinned formula with "…is pinned", so the button could only ever
            // fail.
            HelmBadge(HbStr.pinned)
        }
    }

    /// Whether an installed package has an update waiting, for the row's dot.
    /// The same reading `InspectorState.of` takes for the same package, so the
    /// row and the inspector cannot disagree about one fact.
    private func hasUpdate(_ id: String) -> Bool {
        if case .available = PackageStanding.updates(for: id, outdated: hb.outdated,
                                                      loadedOutdated: hb.loadedOutdated) {
            return true
        }
        return false
    }

    // MARK: - Console

    private var console: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusPill
                Spacer()
                if hb.running {
                    // The only way out of a brew that will not finish — the
                    // module used to be dead until an app restart.
                    Button(HbStr.stop) { hb.stop() }.controlSize(.small)
                }
                Button(HbStr.clear) { hb.clearConsole() }.controlSize(.small).disabled(hb.running)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HelmSpace.s1) {
                        ForEach(Array(hb.consoleLines.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).id(i)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: hb.consoleLines.count) { _, _ in
                    withAnimation(HelmMotion.interface) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .frame(height: 160)
            // The token's own doc comment names console output as its call site.
            .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .fill(HelmSurface.wellFill))
        }
        .padding(12)
    }

    @ViewBuilder private var statusPill: some View {
        switch hb.op.phase {
        case .running:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(hb.op.label).font(HelmText.rowDetail) }
        case .done:
            Label(HbStr.done, systemImage: "checkmark.circle.fill").foregroundStyle(HelmSignal.success).font(HelmText.rowDetail)
        case .failed where hb.op.reason == .stopped:
            // The person asked for this end; a red octagon would call their own
            // press a defect.
            Label(HbStr.stopped, systemImage: "stop.circle.fill").foregroundStyle(HelmText.quiet).font(HelmText.rowDetail)
        case .failed:
            HStack(spacing: 6) {
                Label(HbStr.failed, systemImage: "xmark.octagon.fill").foregroundStyle(HelmSignal.danger).font(HelmText.rowDetail)
                if hb.op.reason == .brewMissing {
                    Text(HbStr.brewGone).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
            }
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Row helpers

    /// A row of the master list — no button, per the approved prototype
    /// (`design/Main.dc.html:86-98`): `dot · name(ellipsis) · badge · trailing`.
    /// Every action lives in the inspector now, which is the only way a
    /// selectable `List` row and a button do not fight the same click.
    ///
    /// `desc` is passed only from the single-column branch, where there is no
    /// inspector to carry it — `nil` omits the second line entirely rather
    /// than reserving an empty one, since the split layout never re-flows a
    /// row that never draws a description at all.
    private func pkgRow(name: String, detail: String?, isCask: Bool,
                        pinned: Bool = false, alreadyInstalled: Bool = false,
                        hasUpdate: Bool = false, desc: String? = nil) -> some View {
        HStack(spacing: HelmSpace.s3) {
            if hasUpdate {
                // The only carrier of "an update exists" for this row — named,
                // so a colourblind or VoiceOver reading still has the fact.
                Circle().fill(HelmSignal.warning).frame(width: 6, height: 6)
                    .accessibilityLabel(HbStr.updateAvailable)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    // Only when it says something: 46 of 47 rows were
                    // "formula", and a label with one value is an ornament.
                    // Pinned and cask never overlap — `brew pin` is formulae
                    // only — so both may be drawn without choosing one.
                    if isCask { HelmBadge(HbStr.cask, tint: .purple) }
                    if pinned { HelmBadge(HbStr.pinned) }
                    if alreadyInstalled { HelmBadge(HbStr.alreadyInstalled) }
                    if let detail { Text(detail).font(.caption2).foregroundStyle(HelmText.quiet) }
                }
                if let desc {
                    Text(desc).font(.caption2).foregroundStyle(HelmText.quiet).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }

    /// `empty` is nil while the first query is still out: "nothing installed"
    /// must not be shown to someone who is simply waiting for the list.
    /// Which list a segment is showing, and therefore which one Refresh
    /// reloads. There were two answers: switching to Search reloaded nothing,
    /// while pressing Refresh on Search reloaded the installed list behind it.
    /// The switcher's answer is the right one — Search has nothing cached to
    /// refresh, and a button that quietly reloads a list you are not looking at
    /// is a button that did nothing.
    private func refresh(_ segment: HomebrewViewModel.Segment) async {
        switch segment {
        case .installed: await hb.refreshInstalled()
        case .updates: await hb.refreshOutdated()
        // Nothing cached to reload: the hits belong to a query, and reloading
        // the installed list behind a search is a button that did nothing.
        case .search: break
        }
    }

    /// `T.ID == String`: every list here is keyed by a `BrewKey` id, which is
    /// also what `hb.selection` holds — no `String(describing:)` conversion
    /// needed at the boundary.
    private func listOrEmpty<T: Identifiable, Row: View>(_ items: [T], empty: String?, busy: String,
                                                         @ViewBuilder row: @escaping (T) -> Row) -> some View
        where T.ID == String {
        Group {
            if items.isEmpty, let empty {
                HelmEmptyState(message: empty)
            } else if items.isEmpty {
                // `HelmBusyState()` is the bare spinner its own doc comment
                // names as one of the three shapes it exists to end; the caller
                // still has to say what is being waited on.
                HelmBusyState(busy)
            } else {
                // A `List` with no selection has no focusable rows at all —
                // arrow keys did nothing. Selecting is also how the inspector
                // is reached, so this is the row's only door into the app now.
                // No `.onTapGesture`, no `.listRowBackground`: macOS draws the
                // system selection itself.
                List(items, selection: Binding(get: { hb.selected }, set: { hb.select($0) })) { item in
                    row(item)
                }
                .listStyle(.inset)
                .padding(.horizontal, 12)
            }
        }
    }

}
