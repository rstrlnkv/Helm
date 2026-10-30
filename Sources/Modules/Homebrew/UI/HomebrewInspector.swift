import SwiftUI
import HelmUI

struct HomebrewInspector: View {
    @ObservedObject var hb: HomebrewViewModel

    /// The one dispatcher over `InspectorState`, and the only thing either
    /// container mounts.
    ///
    /// Above `HomebrewSplit`'s threshold this sits beside the list, in
    /// `HomebrewManager`'s `HStack`; below it, `HomebrewManager` puts the same builder
    /// full width behind `backBar`, in place of the list. Neither call site
    /// passes it anything beyond what it already reads off `hb` — the width
    /// only decides which container it sits in, never what it draws, which is
    /// what keeps a wide reading and a narrow one from disagreeing about what
    /// one subject offers.
    ///
    /// It decides nothing itself: `InspectorState.of` answers what is being
    /// looked at, and each kind of subject has exactly one builder below.
    ///
    /// **Only the two package tabs have one.** Состояние is a page whose rows
    /// open in place (`HomebrewHealthPage`), so this is never mounted there and
    /// `InspectorState.of` answers `.nothingToSelect` if it is ever asked.
    ///
    /// **The current tab's own list, after the filter, not the raw answer.**
    /// `InspectorState.of`'s own emptiness check answers off
    /// `hb.installed`/`hb.outdated`, which is the
    /// *unfiltered* Cellar — so a query that hid every row still saw a
    /// non-empty list and invited a choice beside a master saying «Nothing in
    /// this list matches.», a sentence with nothing left to pick. Read once
    /// here rather than inline in the `switch` below, because `body` is
    /// where the invitation is drawn and the emptiness it is about belongs one
    /// property up from that, beside the other reader of `hb.segment`.
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
                // **Nothing, deliberately.** The list next to this already
                // carries the sentence for whichever of the three readings it
                // is in, and that sentence is the page's one account of the
                // fact; a second one here in the inspector's own words is the
                // defect this page has just been repaired of twice. What is
                // wrong with the invitation is not its wording — there is no
                // wording that makes «choose one» true of a list with nothing
                // in it — so the column describes nothing, which is what there
                // is to describe. It comes back the moment a row does.
                Color.clear
            case let .package(subject):
                packageDetail(subject)
            }
        }
    }

    /// **The one builder for what a package draws — there is no second one.**
    ///
    /// Scrolled, because the second tier is as long as the package makes it:
    /// openssl@3 answers with three tiles, a homepage, a tap, two notes, a
    /// dependency chip and four lines of caveats, and below `HomebrewSplit`'s
    /// threshold this has the console under it as well. A fixed column simply
    /// clipped the caveats.
    private func packageDetail(_ subject: InspectorSubject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                // **The action stands next to the name it acts on, not at the
                // pane's far edge.** It used to sit behind the `Spacer`, which
                // is the drawing's own arrangement and was right at the width
                // the drawing was made for — but nothing bounded this column,
                // so at the pane the app draws (measured 2026-09-15: 984 pt,
                // a 649 pt inspector) «Uninstall» was 549 pt from the package
                // name and read as belonging to the pane rather than to the
                // package. The `Spacer` stays, after the button: it is what
                // keeps the row left-packed once the column is bounded.
                HStack(spacing: HelmSpace.s3) {
                    Text(subject.name).font(HelmText.sectionHeading)
                    if subject.isCask { HelmBadge(HbStr.cask, tint: HomebrewPackageRow.caskTint) }
                    if !subject.version.isEmpty {
                        Text(subject.version).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    }
                    inspectorAction(subject)
                    Spacer(minLength: 0)
                }
                // The same fact the row's marker carries, said in words
                // here and with the same symbol — the one place
                // `InspectorSubject.updates` is read, since `.installed`'s
                // own action stays Uninstall either way.
                //
                // **And the thing it announces, offered where it is
                // announced.** Measured 2026-09-16 on the 984 pt pane: this
                // line sat 12 pt under a 75.5 × 24 Uninstall button and
                // nothing on the screen acted on it — the upgrade was a
                // segment away, reachable only by leaving the package. The
                // module has had the path all along, gated and tested; what
                // it did not have was the button beside the sentence.
                //
                // **The two actions are a row apart and that is the whole of
                // the ordering.** The destructive one keeps the title row,
                // where it belongs to the name; the constructive one sits with
                // the sentence it answers, `HelmSpace.s5` below. A press meant
                // for one cannot land on the other, and the uninstall question
                // is untouched. Weight is carried by ink rather than by
                // position: `destructive` marks Uninstall, and Upgrade is a
                // plain button, so the louder of the two is the one that
                // cannot be taken back.
                if case let .available(_, pinned) = subject.updates {
                    HStack(spacing: HelmSpace.s3) {
                        Label(HbStr.updateAvailable, systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(HelmSignal.warning)
                            .font(HelmText.rowDetail)
                        // A pinned formula is listed and not offered, here for
                        // the same reason `inspectorAction` gives one segment
                        // over: `brew upgrade` answers it with "…is pinned",
                        // so the button could only ever fail.
                        if pinned {
                            HelmBadge(HbStr.pinned)
                        } else {
                            upgradeAction(subject)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let desc = subject.desc {
                    Text(desc).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                }
                // **The second tier, and only when there is an answer.**
                // Everything above this line is a function of the lists the
                // page already holds, so it is on screen the moment a row
                // is clicked. `hb.info` is nil while `brew info` is out and
                // stays nil when it refused — and a refusal, a missing brew
                // and a document this build cannot read are one nil
                // (`HomebrewEngine.info`), none of which has measured
                // anything. So there is no spinner in place of the package
                // and no tile with nothing in it: the tier is absent.
                if let info = hb.info { PackageSecondTier(info: info, size: hb.size) }
            }
            .helmInspectorColumn()
        }
    }

    /// Looked up by `BrewKey` id and never by name — `docker` is both a
    /// formula and a cask, which is the defect `BrewKey` was written against.
    @ViewBuilder
    private func inspectorAction(_ subject: InspectorSubject) -> some View {
        switch subject.action {
        case .uninstall:
            Button {
                guard let pkg = hb.installed.first(where: { $0.id == subject.id }) else { return }
                // Every other destructive action in Helm asks first; this one
                // removed a cask — an app — on a single click.
                Task { await hb.askToUninstall(pkg) }
            } label: {
                Text(HbStr.uninstallAsking).helmDestructive()
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
            // Still listed — somebody who pinned a formula still wants to know
            // a newer one exists — but not offered. `brew upgrade` answers a
            // pinned formula with "…is pinned", so the button could only ever
            // fail.
            HelmBadge(HbStr.pinned)
        }
    }

    /// **The one Upgrade button — the Обновления segment's action and the one
    /// beside «Update available» on Установленные are the same builder.**
    ///
    /// Two call sites, one body, for the reason `HomebrewInspector` gives at the top of
    /// this file: a package that offers an upgrade from one screen and a
    /// different upgrade from another is a defect with nothing to catch it.
    /// Looked up by `BrewKey` id and never by name — `docker` is both a formula
    /// and a cask.
    private func upgradeAction(_ subject: InspectorSubject) -> some View {
        Button(HbStr.upgrade) {
            guard let pkg = hb.outdated.first(where: { $0.id == subject.id }) else { return }
            hb.upgrade(pkg)
        }
        .disabled(hb.running)
    }
}

/// **The inspector's one bound, and the whole of what keeps it from stretching.**
///
/// Every builder the inspector mounts ends on this instead of on a padding and
/// an `.infinity` frame of its own — which is what the three of them used to
/// end on, and the reason the pane the app actually draws handed a tile holding
/// `2.11.4` 308 pt and a sentence 625. `HelmLayout.readingColumn` carries the
/// number and the measurement behind it.
///
/// Read outwards: the content is capped at the reading column, the padding is
/// paid around that, and the outermost frame takes the pane's whole width so
/// the block is **centred** in it. The last of the three is not decoration —
/// SwiftUI hit-tests a scroll view's *content*, so a block that stopped at
/// 468 pt would leave the rest of the inspector dead to the wheel, which is the
/// half of this shape `helmSettingsColumn`'s own doc comment was written about.
///
/// **`.top`, not `.topLeading`, and the two halves of that are separate
/// decisions.** Horizontally the block is centred, because once it is capped the
/// pane is wider than it: measured 2026-09-16 at the pane the app draws, the
/// bounded column sat at 347…791 of a 335…984 inspector, which is 193 pt of
/// nothing down one side and none down the other — a column shoved into a
/// corner rather than a column. Vertically it stays at the top, because a detail
/// pane fills from the top and centring would float a two-line finding in the
/// middle of the pane.
///
/// Centring costs nothing where there is nothing to centre: below
/// `HomebrewSplit`'s threshold the inspector is narrower than the cap, so the
/// block already fills it and both readings are the same number — measured at
/// the threshold's own 268 pt pane, 304…548 before and after. It is not a
/// margin: the width of the content never changes, only where the slack falls.
///
/// Private to this file: one module draws it, and the house's rule is that a
/// thing two modules draw moves to `HelmUI` rather than that everything starts
/// there.
private extension View {
    func helmInspectorColumn() -> some View {
        frame(maxWidth: HelmLayout.readingColumn, alignment: .topLeading)
            .padding(HelmSpace.s5)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}
/// **The mark a control that destroys something carries, spelled once.**
///
/// `role: .destructive` is not it, and this page is where that was measured
/// rather than assumed. On a 984 pt pane in light appearance, 2026-09-16: the
/// darkest pixel of «Скопировать»'s label was `#303030` on the button's own
/// `#EFEFEF` fill, 11.49:1 — and of «Выполнить», a `role: .destructive`
/// bordered button 12 pt away, exactly `#303030` at exactly 11.49:1. On this
/// macOS the role changes what a button *does* in a menu and nothing at all
/// about what it draws, so the only marked thing about it was the source.
/// `GeneralSettingsPage` met the same thing on its Reset row — "the role alone drew as an
/// ordinary link in a grouped Form" — and this is that sentence about a bordered button.
///
/// **On the label, and deliberately not on the button.** The same token handed
/// to the *button* is SwiftUI's tint channel and macOS fills the whole control
/// with it — a pale red button, which is the louder mark and was measured too.
/// It fails where it matters least often and worst: `disabled` while a `brew`
/// runs, the tinted control dimmed to `#F1CBCA` on `#F9EEEE`, **1.31:1**, a
/// word gone rather than a word greyed. On the label the fill lightens to
/// `#F7F7F7` and the word stays legible at 3.60:1.
///
/// Nor `.borderedProminent` with a danger tint: in a window that is not key —
/// a settings pane behind a sheet, and every still this house verifies by
/// photograph — it drew a `#EFEFEF` fill under a `#FFFFFF` label, 1.1:1.
///
/// **What it measures on the surface it is actually on**, which is the button's
/// own fill and not the white pane behind it. Light: `#D9584D` on `#EFEFEF`,
/// 3.35:1 where its neighbour reads 11.49:1. Dark: `#F16B60` on `#3F3F3F`,
/// 3.52:1 where its neighbour reads 8.40:1. The two labels are no longer one
/// ink in either appearance.
///
/// **And the shortfall is named rather than hidden.** `HelmSignal.danger` is
/// specified at 4.52:1 and that is against white; a bordered button's fill is
/// six per cent darker, which puts the pure token at 3.94:1 there and the
/// antialiased rendering at the 3.35:1 above — under the 4.5:1 the token was
/// chosen for. Every styling that clears it needs either a control that is not
/// a button (a borderless label on the white pane measures the token's own
/// 4.52:1) or a second, darker danger for text in `HelmSignal`. Neither is
/// this page's to decide.
extension View {
    func helmDestructive() -> some View { foregroundStyle(HelmSignal.danger) }
}
