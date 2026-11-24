import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// What colour each update channel is, decided once.
///
/// The page names each channel twice (the badge on the wordmark says which
/// build this is, the picker says which one to follow), and the two must say
/// the same word in the same colour.
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
    @State private var channel = UpdateService.shared.channel
    @ObservedObject private var updater = UpdateService.shared

    private var shortVersion: String {
        AppBuild.shortVersion ?? "0.1.0"
    }
    private var buildNumber: String {
        AppBuild.buildNumber ?? "1"
    }
    private var moduleCount: Int { ModuleRegistry.all.count }

    var body: some View {
        // A ScrollView because the page grows when an update is available (a
        // full-width prominent button) and is taller than the minimum window:
        // without it the Update button would drop off the bottom.
        ScrollView {
            VStack(spacing: 0) {
            Spacer(minLength: HelmSpace.s5)
            hero
            Spacer(minLength: HelmSpace.s6).frame(maxHeight: HelmSpace.s7)
            instrumentRow
                .padding(.bottom, HelmSpace.s5)
            // The same gap the strip above it takes, so the author card sits
            // at one distance from both neighbours.
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
            // The flag-icons artwork is MIT, which asks for its notice to
            // accompany the copy: `NOTICE.md` ships inside the bundle, and
            // `NoticeShipsWithTheAppTests` keeps it there, since nothing on
            // screen would show its absence.
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
        // The name of the page this one is a tab of, for the window's title;
        // without it `SettingsWindow.applyTitle(_:)` falls back to the
        // window's own name. A no-op where the card does not draw the header
        // (`helmHeaderInCard` false).
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

    /// One badge: what this copy *is*. Pre-1.0 and "on the early channel" both
    /// answer "how finished is what I am running", so two badges would make the
    /// reader work out which one wins.
    ///
    /// It describes the build (`AppBuild.isDev`), never the channel
    /// preference: the picker below describes what will be offered next, and
    /// the two are allowed to differ.
    private var badge: some View {
        // The tint comes from `ChannelInk`, the same place the pills below read it.
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
    /// foot: the small print is obligations, and this answers «who made this».
    ///
    /// The glyph belongs to the handle, not between the two items: an `HStack`
    /// with a tight gap inside the `Link` and a wider one between the row's
    /// items, so it reads as the mark on a Telegram link rather than a
    /// separator. `.firstTextBaseline`, because the glyph's box is shorter
    /// than the text's and centring would hang the link above the name's
    /// baseline.
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
    /// cards above, so the column's text starts in one place.
    private var updateCard: some View {
        VStack(spacing: 0) {
            updateRow
                .padding(.horizontal, HelmSpace.s5)
                .padding(.vertical, HelmSpace.s5)
            // The token, not a divider dimmed by eye: every other hairline in
            // the app is this colour.
            Rectangle()
                .fill(HelmSurface.hairline)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                HStack {
                    Text(AppStr.updateChannel)
                        // A row's own name, at the size every other row name on
                        // the page is set in.
                        .font(HelmText.rowTitle)
                    Spacer()
                    channelPills
                        .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
                }
                HelmSettingsNote(AppStr.channelNote(channel))
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

    /// What this card is drawing, decided in one place that can be asked
    /// (`UpdateCard`): an order of `else if`s inside a builder cannot be tested.
    private var card: UpdateCard {
        UpdateCard.drawn(installState: updater.installState, checking: updater.checking,
                         hasRelease: updater.available != nil,
                         hasAhead: updater.aheadOfChannel != nil, note: updater.note,
                         hasUnfinishedUpdate: updater.unfinishedUpdate != nil)
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
                noticeRow("exclamationmark.triangle.fill", HelmSignal.danger,
                          AppStr.updateDigestMismatch, lines: 3, wraps: false)
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
                noticeRow("exclamationmark.triangle.fill", HelmSignal.warning,
                          AppStr.updateFailed, lines: 2, wraps: false)
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
            noticeRow("exclamationmark.triangle.fill", HelmSignal.warning, AppStr.updateManualInstall, lines: 3, wraps: false)
        case .cannotReplaceItself:
            noticeRow("exclamationmark.triangle.fill", HelmSignal.warning, AppStr.updateCannotReplaceItself, lines: 3, wraps: false)
        case .checkFailed:
            // Two lines, like every notice arm here: at one, the longer
            // languages are cut beside the button.
            noticeRow("exclamationmark.triangle.fill", HelmSignal.warning, AppStr.updateCheckFailed, lines: 2,
                      button: (AppStr.retry, { updater.checkNow() }))
        case .ahead:
            noticeRow("arrow.up.circle.fill", HelmSignal.warning,
                      AppStr.aheadOfChannel(updater.aheadOfChannel ?? ""), lines: 2,
                      button: (AppStr.checkNow, { updater.checkNow() }))
        case .upToDate:
            // Two lines: beside «Check Now», Russian, Portuguese and French
            // need more than one.
            noticeRow("checkmark.circle.fill", HelmSignal.success, AppStr.upToDate, lines: 2,
                      button: (AppStr.checkNow, { updater.checkNow() }))
        case .unfinishedUpdate:
            HStack(spacing: HelmSpace.s5) {
                statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                Text(AppStr.updateNotInstalled(AppBuild.shortVersion ?? ""))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(AppStr.checkNow) { updater.checkNow() }
            }
        case .lastChecked:
            // Nothing has been decided this session: report when the last
            // check happened rather than claiming to be current. Two lines,
            // for the reason the arm above has them.
            noticeRow("arrow.triangle.2.circlepath", HelmText.quiet, lastCheckedText, lines: 2,
                      quiet: true, button: (AppStr.checkNow, { updater.checkNow() }))
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

    /// Always spinning: every state that draws this line is work in flight.
    private func statusLine(_ text: String) -> some View {
        HStack(spacing: HelmSpace.s5) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(HelmText.quiet)
            Spacer()
        }
    }

    /// One notice line: icon, sentence, and the button that answers it. Each
    /// modifier is applied only where its arm had it, so a limit or a style
    /// the arm never set is not forced on it.
    @ViewBuilder
    private func noticeRow(_ symbol: String, _ tint: Color, _ text: String, lines: Int,
                           wraps: Bool = true, quiet: Bool = false,
                           button: (title: String, action: () -> Void)? = nil) -> some View {
        HStack(spacing: HelmSpace.s5) {
            statusIcon(symbol, tint)
            let words = Text(text).lineLimit(lines)
            if wraps {
                if quiet {
                    words.fixedSize(horizontal: false, vertical: true).foregroundStyle(HelmText.quiet)
                } else {
                    words.fixedSize(horizontal: false, vertical: true)
                }
            } else {
                words
            }
            Spacer()
            if let button { Button(button.title, action: button.action) }
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
                Button(HelmWord.close, action: onClose)
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
                            ForEach(Array(entry.items.enumerated()), id: \.offset) { _, item in
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
        // The kit's badge, which keeps its text legible on its tint.
        HelmBadge(kind.label, tint: kind.color)
            // Fixed width wrapped half the languages onto a second line.
            .fixedSize()
            .frame(minWidth: 44, alignment: .leading)
    }

}
