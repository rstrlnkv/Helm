import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// What colour each update channel is, decided once.
///
/// The page names each channel twice — the badge on the wordmark says which
/// build this is, the picker says which one to follow — and they used to
/// disagree: the badge drew a dev build blue and a beta build orange. Two
/// controls fifty points apart, saying the same word in different colours,
/// each right on its own.
///
/// Orange is `HelmSignal.warning` because that is what it means: this channel
/// ships rough edges on purpose. Beta is the accent, which is what macOS uses
/// for "the one that is chosen" everywhere else.
private enum ChannelInk {
    static func fill(_ channel: UpdateCheck.Channel) -> Color {
        switch channel {
        case .beta: return .accentColor
        case .dev: return HelmSignal.warning
        }
    }

    /// What the chosen pill is filled with.
    ///
    /// The wash is `HelmSurface.chosenWash`: opaque, blended inside the appearance.
    static func chosenFill(_ channel: UpdateCheck.Channel) -> Color {
        switch channel {
        case .beta: return betaWash
        case .dev: return devWash
        }
    }

    /// Stored, not built per call: the reason is on `HelmSurface.chosenWash`.
    private static let betaWash = HelmSurface.chosenWash(fill(.beta))
    private static let devWash = HelmSurface.chosenWash(fill(.dev))
}

/// The About page: what this build is, which channel it follows, and what
/// changed. `WhatsNewView` below is its own and stays private.
///
/// Internal rather than `private` because the router that chooses it lives in
/// `SettingsWindow.swift`, and nothing outside `HelmApp` names it.
struct AboutHelmView: View {
    @State private var showWhatsNew = false
    @State private var channel = UpdateService.channel
    @ObservedObject private var updater = UpdateService.shared

    private var shortVersion: String {
        AppBuild.shortVersion ?? "0.1.0"
    }
    private var buildNumber: String {
        AppBuild.buildNumber ?? "1"
    }
    private var moduleCount: Int { ModuleRegistry.all.count }

    var body: some View {
        // A ScrollView because the page grows by ~50 pt when an update is
        // available — a full-width prominent button — and it already measured
        // 617 pt against the 540 pt minimum window. It overflowed at the
        // default size precisely in the state that matters, dropping the
        // Update button off the bottom.
        ScrollView {
            VStack(spacing: 0) {
            Spacer(minLength: HelmSpace.s5)
            hero
            Spacer(minLength: HelmSpace.s6).frame(maxHeight: HelmSpace.s7)
            instrumentRow
                .padding(.bottom, HelmSpace.s5)
            // 10, the same gap the strip above it takes. Down the page the
            // gaps were 22, 10, 20, 14, 24 — the author card glued to the
            // strip above and adrift from the update card below, which is one
            // card reading as two different distances from its neighbours.
            authorRow
                .padding(.bottom, HelmSpace.s5)
            updateCard
            HStack(spacing: HelmSpace.s5) {
                Button {
                    showWhatsNew = true
                } label: {
                    Label(AppStr.whatsNew, systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    if let url = URL(string: "https://github.com/rstrlnkv/Helm") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "arrow.up.forward.square")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            .padding(.top, HelmSpace.s5)
            Spacer(minLength: HelmSpace.s6)
            // The flag credit was the second line here, and the comment above
            // it named CC BY 4.0 — the licence of the EmojiOne set that was
            // dropped, not of the flag-icons artwork that replaced it. MIT
            // asks for its notice to *accompany* the copy, and `NOTICE.md`
            // ships inside the bundle carrying the copyright and the full
            // permission text. `NoticeShipsWithTheAppTests` is what keeps it
            // there now that nothing on screen would show its absence.
            Text("© 2026 Helm · GPL-3.0")
                .padding(.top, HelmSpace.s3)
                .font(HelmText.smallPrint)
                .foregroundStyle(HelmText.faint)
        }
            .frame(width: Self.column)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpace.s7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The name of the page this one is a tab of, for the window's title.
        // Without it nothing publishes a title, and
        // `SettingsWindow.applyTitle(_:)` falls back to the window's own name
        // («Настройки Helm» for the Window menu). A no-op where the card does not
        // draw the header (`helmHeaderInCard` false).
        .helmPageBar(title: AppStr.settingsPane)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    private static let column: CGFloat = 380

    // MARK: - Hero

    private var hero: some View {
        HelmAppHero(active: updater.checking, tagline: AppStr.tagline,
                    spoken: badgeAccessibilityLabel) { badge }
    }

    /// One badge: what this copy *is*.
    ///
    /// It was two — BETA for the program and DEV for the channel — on the
    /// reasoning that both facts were true. They are, but they are not two
    /// things to the person reading: pre-1.0 and "on the early channel" both
    /// answer "how finished is what I am running", and a pair reading BETA DEV
    /// makes the reader work out which one wins.
    ///
    /// It then answered from the wrong fact. The badge read the *channel
    /// preference*, so switching the segmented control to Beta on a
    /// `0.7.2-dev.34` build relabelled the running build BETA — while the row
    /// above it went on offering dev releases, because a preference is not a
    /// binary. The badge describes the build; the picker below it describes
    /// what will be offered next, and those are allowed to differ.
    /// `AppBuild.isDev`, which is where that argument now lives — it was written
    /// out here and twice more, and both other copies had stopped being read.
    private var badge: some View {
        // The tint comes from `ChannelInk`, the same place the pills below read
        // it. It used to be spelled here — dev blue, beta orange — which is the
        // opposite of what the picker says, so a dev build showed a blue DEV
        // over an orange Dev pill fifty points apart.
        HelmBadge(AppBuild.isDev ? AppStr.devBadge : AppStr.betaBadge,
                  tint: ChannelInk.fill(AppBuild.isDev ? .dev : .beta),
                  emphasis: .prominent)
            .help(AppStr.channelNote(AppBuild.isDev ? .dev : .beta))
    }

    private var badgeAccessibilityLabel: String {
        "Helm, \(AppBuild.isDev ? AppStr.devBadge : AppStr.betaBadge)"
    }

    // MARK: - Instrument row

    /// Who wrote it, and where to say something about it.
    ///
    /// Under the version and the build rather than in the small print at the
    /// foot: the licence and the flag credit down there are obligations, and
    /// this is not one — it is the answer to «who made this», which is a
    /// question people actually ask of a menu-bar app they were handed.
    /// The glyph belongs to the handle, not between the two items.
    ///
    /// As a `Label` the paperplane sat 10.5 pt from the name and 10.5 pt from
    /// the handle — measured ink, both gaps equal — so it read as a separator
    /// between three things rather than as the mark on a Telegram link. An
    /// `HStack` at 3 inside the `Link` and 12 between the row's own items puts
    /// it at 13.5 and 6.0: the glyph is now nearer the thing it belongs to by
    /// more than twice.
    ///
    /// `.firstTextBaseline` for the row, which is the same change: a `Label`'s
    /// box is 14.12 pt against the text's 16.00, so centring the two hung the
    /// link 1.50 pt above the name's baseline. Measured after: 0.00. It is
    /// worth applying only with the glyph change — on its own it grew the card
    /// from 40 to 41.
    private var authorRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s5) {
            Text(AppStr.author)
                .foregroundStyle(HelmText.quiet)
            Spacer(minLength: HelmSpace.s4)
            Text(AppStr.authorName)
            Link(destination: URL(string: "https://t.me/r_strlnkv")!) {
                HStack(spacing: HelmSpace.s1) {
                    Image(systemName: "paperplane.fill")
                    Text("@r_strlnkv")
                }
                .font(HelmText.rowDetail)
            }
        }
        .font(HelmText.rowTitle)
        .helmCard(padding: 12)
    }

    private var instrumentRow: some View {
        HelmMetricStrip([
            .init(VersionLabel.split(shortVersion).figure,
                  VersionLabel.caption(AppStr.metricVersion, for: shortVersion)),
            .init(buildNumber, AppStr.metricBuild),
            .init("\(moduleCount)", AppStr.metricModules),
        ])
        .helmCard(padding: 12)
    }

    // MARK: - Update card

    /// 12 horizontally, which is what `helmCard(padding: 12)` gives the two
    /// cards above. At 14 the left text edge stepped 227 → 229 between the
    /// author card and this one — two cards in one column starting their text
    /// in two places, which is visible as a wobble long before anybody can say
    /// what it is.
    private var updateCard: some View {
        VStack(spacing: 0) {
            updateRow
                .padding(.horizontal, HelmSpace.s5)
                .padding(.vertical, HelmSpace.s5)
            // The token, not a divider dimmed by eye: every other hairline in
            // the app is this colour, and 0.6 of a system divider is not a
            // value anybody can match on the next screen over.
            Rectangle()
                .fill(HelmSurface.hairline)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                HStack {
                    Text(AppStr.updateChannel)
                        // A row's own name, at the size every other row name on
                        // the page is set in. `.callout` is 12, and it was the
                        // fifth size on a page the type scale gives four.
                        .font(HelmText.rowTitle)
                    Spacer()
                    channelPills
                        .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
                }
                Text(AppStr.channelNote(channel))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, HelmSpace.s5)
            .padding(.vertical, HelmSpace.s5)
        }
        .helmCard(padding: 0)
    }

    /// The two channels, as pills (`HelmPillChoice`): Dev is the warning orange it means and Beta is the accent,
    /// from `ChannelInk`, which is also what the badge on the wordmark reads.
    private var channelPills: some View {
        HelmPillChoice(AppStr.updateChannel, selection: $channel,
                       items: UpdateCheck.Channel.allCases.map { option in
            .init(option, label: AppStr.channelName(option),
                  chosenFill: ChannelInk.chosenFill(option),
                  help: AppStr.channelNote(option))
        })
    }

    /// What this card is drawing, decided in one place that can be asked.
    ///
    /// It was a chain of `else if`s inside the builder, and the order of that
    /// chain is what made the manual-install sentence unreachable — see
    /// `UpdateCard`.
    private var card: UpdateCard {
        UpdateCard.drawn(installState: updater.installState, checking: updater.checking,
                         hasRelease: updater.available != nil,
                         hasAhead: updater.aheadOfChannel != nil, note: updater.note)
    }

    @ViewBuilder
    private var updateRow: some View {
        // Exhaustive, no `default`: a state the updater learns to write is a
        // build error here rather than a card quietly drawing the wrong thing.
        switch card {
        case .downloading:
            statusLine(AppStr.downloadingUpdate)
        case .installing:
            statusLine(AppStr.installingUpdate)
        case .checking:
            statusLine(AppStr.checking)
        case .digestMismatch:
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                HStack(spacing: HelmSpace.s5) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.danger)
                    Text(AppStr.updateDigestMismatch).lineLimit(3)
                    Spacer()
                }
                // No Retry: downloading the same file again would produce the
                // same answer. The release page is where a person can see what
                // was published and decide.
                if let rel = updater.available {
                    Link(AppStr.download, destination: rel.pageURL)
                        .font(HelmText.rowTitle)
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                HStack(spacing: HelmSpace.s5) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateFailed).lineLimit(2)
                    Spacer()
                }
                if let rel = updater.available {
                    HStack(spacing: HelmSpace.s5) {
                        Button(AppStr.retry) { updater.downloadAndInstall() }
                            .frame(maxWidth: .infinity)
                        Link(AppStr.download, destination: rel.downloadURL ?? rel.pageURL)
                            .font(HelmText.rowTitle)
                    }
                }
            }
        case .ready:
            // The offer is the card's main action, so it gets full width
            // instead of being squeezed next to the label.
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                HStack(spacing: HelmSpace.s5) {
                    statusIcon("arrow.down.circle.fill", .accentColor)
                    Text(AppStr.updateReady).lineLimit(1)
                    Spacer()
                    Text(updater.available?.version ?? "")
                        .font(HelmText.figureFont)
                        .foregroundStyle(HelmText.quiet)
                }
                Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        case .manualInstall:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                Text(AppStr.updateManualInstall).lineLimit(3)
                Spacer()
            }
        case .cannotReplaceItself:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                Text(AppStr.updateCannotReplaceItself).lineLimit(3)
                Spacer()
            }
        case .checkFailed:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                // Two lines, like the `ahead` arm below. At one this sentence
                // was cut in five of the eight languages: a German whose update
                // check failed read «Update-Prüfung fehl…», where the string
                // wants 198 pt of the roughly 240 the row leaves it. French
                // wants 253, Portuguese 234, Russian 225, Spanish 215. Only en,
                // ja and zh ever fitted.
                Text(AppStr.updateCheckFailed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(AppStr.retry) { updater.checkNow() }
            }
        case .ahead:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("arrow.up.circle.fill", HelmSignal.warning)
                Text(AppStr.aheadOfChannel(updater.aheadOfChannel ?? ""))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(AppStr.checkNow) { updater.checkNow() }
            }
        case .upToDate:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("checkmark.circle.fill", HelmSignal.success)
                // **The same repair as the two arms above, applied to the two
                // that were left.** «Установлена последняя версия.» wants 203 pt
                // and this row leaves it about 197 beside «Проверить» — six
                // short, so the state somebody sees most often was the one that
                // read «Установлена последняя верс…». Portuguese is 197 and
                // French 180, so Russian is the first to fall and not the last.
                //
                // The comment on `.checkFailed` measured against «roughly 240 pt
                // of the row», which is not this row: the column is 380 and the
                // card takes 12 a side. A number carried in prose about a
                // neighbour is a number about nothing.
                Text(AppStr.upToDate)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(AppStr.checkNow) { updater.checkNow() }
            }
        case .lastChecked:
            // Nothing has been decided this session: report when the last
            // check happened rather than claiming to be current.
            HStack(spacing: HelmSpace.s5) {
                statusIcon("arrow.triangle.2.circlepath", HelmText.quiet)
                // «Проверено 2 часа назад» is longer than the line above it in
                // every language, so if that one did not fit, this one never did.
                Text(lastCheckedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(HelmText.quiet)
                Spacer()
                Button(AppStr.checkNow) { updater.checkNow() }
            }
        }
    }

    /// "Checked 2 hours ago" from the stored timestamp, or a never-checked note.
    private var lastCheckedText: String {
        let stamp = AppSettings.store.int(UpdateService.lastCheckKey, default: 0)
        // The same reading `checkOnLaunch` makes of the same key, so the line
        // cannot say "checked 2 hours ago" about a number that stopped the
        // check from running.
        // Two refusals, one door: a stamp ahead of the clock is one the check
        // itself will not have, and a stamp with no age to word is one this
        // line cannot finish. Both fall to the note that also carries the
        // button — «Проверялось » with nothing after it would not.
        guard let when = UpdateCheck.lastChecked(stored: stamp, now: Date()),
              let age = HelmDates.age(when) else {
            return AppStr.neverChecked
        }
        return AppStr.lastChecked(age)
    }

    /// Always spinning: every state that draws this line is work in flight. It
    /// took a `spinning:` flag that all three call sites passed `true` and the
    /// body never read.
    private func statusLine(_ text: String) -> some View {
        HStack(spacing: HelmSpace.s5) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(HelmText.quiet)
            Spacer()
        }
    }

    private func statusIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(HelmText.statusGlyph)
            .foregroundStyle(color)
    }
}

/// Localized, structured changelog with New/Upd/Fix badges.
private struct WhatsNewView: View {
    let onClose: () -> Void

    private static let sheetSize = CGSize(width: 520, height: 460)

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "sparkles", tint: ModuleTint.whatsNewColour,
                           title: AppStr.whatsNew) {
                // Escape closes it, like every sheet on the machine.
                // `HelmHotkeyRecorder` special-cases Escape during capture and
                // explains why; that care never reached the sheets.
                Button(AppStr.close, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpace.s6) {
                    ForEach(Changelog.entries) { entry in
                        VStack(alignment: .leading, spacing: HelmSpace.s4) {
                            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
                                Text(entry.version).font(HelmText.entryHeading)
                                // The entry stores "2026-07-28" because that is
                                // what sorts; no language writes it that way.
                                Text(HelmDates.day(entry.date))
                                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                            }
                            ForEach(entry.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
                                    badge(item.kind)
                                    Text(item.text).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Matches the header plate above it, which sits at 20.
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s6)
            }
        }
        .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
    }

    private func badge(_ kind: ChangeKind) -> some View {
        // The one pill. This was the last hand-rolled one, and the worst:
        // orange text on orange fill at 11 pt is about 1.6:1, on the screen
        // every user sees right after an update.
        HelmBadge(kind.label, tint: kind.color)
            // Fixed width wrapped half the languages onto a second line.
            .fixedSize()
            .frame(minWidth: 44, alignment: .leading)
    }

}
