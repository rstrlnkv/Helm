import SwiftUI
import HelmUI

/// The one dispatcher over `InspectorState`, and the only thing either
/// container mounts.
///
/// It decides nothing itself: `InspectorState.of` answers what is being
/// looked at, and `packageDetail` is the one builder. Never mounted on Health.
struct HomebrewInspector: View {
    @ObservedObject var hb: HomebrewViewModel
    @Environment(\.helmTraits) private var traits

    /// **The current tab's own list, after the filter, not the raw answer:**
    /// a query that hid every row leaves nothing to pick.
    private var shownEmpty: Bool {
        switch hb.segment {
        case .installed: return hb.shownInstalled.isEmpty
        case .updates: return hb.shownOutdated.isEmpty
        case .health: return true // no inspector on this tab, so nothing to invite a choice of
        }
    }

    var body: some View {
        Group {
            switch InspectorState.of(segment: hb.segment, selected: hb.selected,
                                     installed: hb.installed, outdated: hb.outdated,
                                     loadedOutdated: hb.loadedOutdated,
                                     hits: hb.shownHits,
                                     descriptions: hb.descriptions,
                                     shownEmpty: shownEmpty) {
            case .nothingSelected:
                HelmEmptyState(message: HbStr.nothingSelected)
            case .nothingToSelect:
                // **Nothing, deliberately:** the list beside this carries the
                // page's one sentence for the fact.
                Color.clear
            case let .package(subject):
                packageDetail(subject)
            }
        }
    }

    /// **The one builder for what a package draws — there is no second one.**
    ///
    /// Scrolled, because the second tier is as long as the package makes it.
    private func packageDetail(_ subject: InspectorSubject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                // **The action stands next to the name it acts on, not at the
                // pane's far edge.** The `Spacer` after it keeps the row
                // left-packed.
                HStack(spacing: HelmSpace.s3) {
                    Text(subject.name).font(HelmText.sectionHeading)
                    if subject.isCask { HelmBadge(HbStr.cask, tint: HomebrewPackageRow.caskTint) }
                    if !subject.version.isEmpty {
                        Text(subject.version).helmQuietDetail()
                    }
                    inspectorAction(subject)
                    Spacer(minLength: 0)
                }
                // The row's update marker in words, with the same symbol, and
                // the Upgrade it announces beside it.
                //
                // **The two actions are a row apart,** so a press meant for one
                // cannot land on the other; `destructive` ink marks the one
                // that cannot be taken back.
                if case let .available(_, pinned) = subject.updates {
                    HStack(spacing: HelmSpace.s3) {
                        Label(HbStr.updateAvailable, systemImage: HomebrewPackageRow.updateMarkSymbol)
                            .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                            .font(HelmText.rowDetail)
                        // `brew upgrade` refuses a pinned formula.
                        if pinned {
                            HelmBadge(HbStr.pinned)
                        } else {
                            upgradeAction(subject)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let desc = subject.desc {
                    Text(desc).helmQuietDetail()
                }
                // **The second tier, and only when there is an answer**
                // (`HomebrewViewModel.info`): no spinner, no empty row.
                if let info = hb.info { PackageSecondTier(info: info, size: hb.size) }
            }
            .helmInspectorColumn()
        }
    }

    /// Looked up by `BrewKey` id and never by name — `docker` is both a
    /// formula and a cask.
    @ViewBuilder
    private func inspectorAction(_ subject: InspectorSubject) -> some View {
        switch subject.action {
        case .uninstall:
            Button(HbStr.uninstallAsking, role: .destructive) {
                guard let pkg = hb.installed.first(where: { $0.id == subject.id }) else { return }
                // Removing a cask removes an application: the question comes first.
                Task { await hb.askToUninstall(pkg) }
            }
            .disabled(hb.running)
        case .upgrade:
            upgradeAction(subject)
        case .install:
            Button(HbStr.install) {
                guard let hit = hb.shownHits.first(where: { $0.id == subject.id }) else { return }
                hb.install(hit)
            }
            .disabled(hb.running)
        case .pinned:
            // Listed, not offered: `brew upgrade` refuses a pinned formula.
            HelmBadge(HbStr.pinned)
        }
    }

    /// **The one Upgrade button: the Updates segment's action and the one
    /// beside «Update available» on Installed are the same builder.**
    ///
    /// Looked up by `BrewKey` id and never by name.
    private func upgradeAction(_ subject: InspectorSubject) -> some View {
        Button(HbStr.upgrade) {
            guard let pkg = hb.outdated.first(where: { $0.id == subject.id }) else { return }
            hb.upgrade(pkg)
        }
        .disabled(hb.running)
    }
}

/// **The inspector's one bound.** `packageDetail` ends on this and on no padding
/// or `.infinity` frame of its own. `HelmLayout.readingColumn` carries the
/// number and the measurement behind it.
///
/// Read outwards: the content is capped at the reading column, the padding is
/// paid around that, and the outermost frame takes the pane's whole width.
/// That frame is not decoration: SwiftUI hit-tests a scroll view's *content*,
/// so a narrower block would leave the rest of the pane dead to the wheel
/// (`helmSettingsColumn`).
///
/// **`.top`, not `.topLeading`:** centred across, so the slack does not all
/// fall down one side; at the top, because a detail pane fills from the top.
///
/// Private to this file: a thing moves to `HelmUI` when two modules draw it.
private extension View {
    func helmInspectorColumn() -> some View {
        frame(maxWidth: HelmLayout.readingColumn, alignment: .topLeading)
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
