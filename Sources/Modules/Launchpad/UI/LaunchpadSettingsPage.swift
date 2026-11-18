import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// The grid of apps, in the person's arrangement; a search turns it into a flat grid of what matches.
///
/// States, in the order they are decided: not answered yet (busy), no apps installed, a search that
/// matches nothing, the grid. A notice about the last thing that did not go through sits above any of
/// the last three. What leaves the page — the search, the open folder, the Hidden section — is state
/// of the page and is gone with it; the arrangement is the engine's.
struct LaunchpadSettingsPage: View {
    @ObservedObject private var lvm: LaunchpadViewModel
    @State private var search = ""
    @State private var hiddenOpen = false
    @State private var hiddenHeight: CGFloat?
    @State private var openFolder: UUID?

    init(lvm: LaunchpadViewModel) {
        self.lvm = lvm
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = lvm.notice {
                HelmBanner(text(of: notice))
                    .helmPageStrip()
                    .helmPageStandsOnStillContent()
            }
            content
        }
        // Declared whatever the state, so the search never moves: a field that came and went with the
        // list shifted everything beside it in the row.
        .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(prompt: HelmControlName.searchApps, text: $search)))
        .task { await lvm.whileShown() }
        .onChange(of: lvm.snapshot) { _, _ in closeFolderIfGone() }
    }

    private func text(of notice: LaunchNotice) -> String {
        switch notice {
        case .gone(let name): LpStr.appIsGone(name)
        case .couldNotOpen(let name): LpStr.couldNotOpen(name)
        case .notSaved: LpStr.notSaved
        }
    }

    @ViewBuilder private var content: some View {
        if let snapshot = lvm.snapshot {
            if snapshot.apps.isEmpty {
                HelmEmptyState(message: LpStr.noApps).helmPageStandsOnStillContent()
            } else if let found = snapshot.search(search) {
                if found.isEmpty {
                    HelmEmptyState(message: LpStr.noMatch).helmPageStandsOnStillContent()
                } else {
                    scroller { grid { ForEach(found, id: \.self) { id in appTile(id, in: snapshot) } } }
                }
            } else {
                scroller {
                    VStack(alignment: .leading, spacing: HelmSpace.s7) {
                        grid {
                            ForEach(snapshot.layout.items, id: \.itemID) { item in itemTile(item, in: snapshot) }
                        }
                        hiddenSection(snapshot)
                    }
                }
            }
        } else {
            HelmBusyState().helmPageStandsOnStillContent()
        }
    }

    private func scroller<Body: View>(@ViewBuilder _ body: () -> Body) -> some View {
        ScrollView {
            body()
                .padding(.horizontal, HelmLayout.formInset)
                .padding(.vertical, HelmSpace.s6)
                .helmSettingsColumn()
        }
    }

    private func grid<Tiles: View>(@ViewBuilder _ tiles: () -> Tiles) -> some View {
        LazyVGrid(columns: LaunchpadMetrics.columns, spacing: HelmSpace.s6) { tiles() }
    }

    // MARK: - Tiles

    @ViewBuilder private func itemTile(_ item: LaunchpadLayout.Item, in snapshot: LaunchpadSnapshot) -> some View {
        switch item {
        case .app(let id): appTile(id, in: snapshot)
        case .folder(let folder): folderTile(folder, in: snapshot)
        }
    }

    @ViewBuilder private func appTile(_ id: AppID, in snapshot: LaunchpadSnapshot) -> some View {
        if let app = snapshot.apps[id] {
            LaunchpadTile(app: app,
                          open: { openFolder = nil; Task { await lvm.launch(id, name: app.name) } },
                          hide: { Task { await lvm.hide(id) } })
        }
    }

    @ViewBuilder private func folderTile(_ folder: LaunchpadLayout.Folder, in snapshot: LaunchpadSnapshot) -> some View {
        let apps = folder.apps.compactMap { snapshot.apps[$0] }
        if !apps.isEmpty {
            LaunchpadTile(name: folder.name, accessibleName: LpStr.folder(folder.name),
                          open: { openFolder = folder.id }, hide: nil) {
                LaunchpadFolderMark(apps: apps)
            }
            .popover(isPresented: Binding(get: { openFolder == folder.id },
                                          set: { if !$0, openFolder == folder.id { openFolder = nil } }),
                     arrowEdge: .bottom) {
                folderContents(folder, apps: apps, in: snapshot)
            }
        }
    }

    private func folderContents(_ folder: LaunchpadLayout.Folder, apps: [CatalogApp], in snapshot: LaunchpadSnapshot) -> some View {
        let rows = Int((Double(apps.count) / 3).rounded(.up))
        let tileHeight = LaunchpadMetrics.icon + HelmSpace.s7 * 2
        return VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(folder.name).font(HelmText.sectionHeading)
            ScrollView {
                grid { ForEach(folder.apps, id: \.self) { id in appTile(id, in: snapshot) } }
            }
            .frame(height: min(LaunchpadMetrics.popoverMaxHeight, CGFloat(rows) * tileHeight))
        }
        .padding(HelmSpace.s5)
        .frame(width: LaunchpadMetrics.popoverWidth)
    }

    /// A folder that has gone (dissolved, or its apps left) takes its popover with it.
    private func closeFolderIfGone() {
        guard let open = openFolder else { return }
        let stillThere = lvm.snapshot?.layout.items.contains { $0.itemID == open.uuidString } ?? false
        if !stillThere { openFolder = nil }
    }

    // MARK: - Hidden

    @ViewBuilder private func hiddenSection(_ snapshot: LaunchpadSnapshot) -> some View {
        let hidden = snapshot.order.filter { snapshot.layout.hidden.contains($0) }.compactMap { snapshot.apps[$0] }
        if !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(HelmMotion.disclosure) { hiddenOpen.toggle() }
                } label: {
                    HStack(spacing: HelmSpace.s3) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(hiddenOpen ? 90 : 0))
                            .foregroundStyle(HelmText.quiet)
                            .accessibilityHidden(true)
                        Text(LpStr.hiddenApps).font(HelmText.sectionHeading)
                        HelmBadge("\(hidden.count)")
                        Spacer()
                    }
                    // The height the kit's other disclosure rows give theirs (Homebrew's health issues pad their header by s5).
                    .padding(.vertical, HelmSpace.s5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(HelmA11y.expanded(hiddenOpen))

                VStack(spacing: HelmSpace.s4) {
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
                .helmCard()
                .helmAccordion(open: hiddenOpen, height: $hiddenHeight)
            }
            .onChange(of: hidden.isEmpty) { _, none in
                if none { hiddenOpen = false; hiddenHeight = nil }
            }
        }
    }
}
