import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// The About page: what this build is, which channel it follows, and what
/// changed. `HelmBezel` and `WhatsNewView` below are its own and stay private.
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
            Spacer(minLength: 12)
            hero
            Spacer(minLength: 22).frame(maxHeight: 30)
            instrumentRow
                .padding(.bottom, 10)
            authorRow
                .padding(.bottom, 20)
            updateCard
            HStack(spacing: 10) {
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
            .padding(.top, 14)
            Spacer(minLength: 18)
            VStack(spacing: 3) {
                Text("© 2026 Helm · GPL-3.0")
                // CC BY 4.0 asks for attribution where the work is used, and
                // the flags are used in the menu bar — this is the page that
                // can carry it.
                Link(AppStr.flagCredit,
                     destination: URL(string: "https://github.com/lipis/flag-icons")!)
                    .foregroundStyle(HelmText.faint)
            }
            .padding(.top, 6)
            .font(.caption2)
            .foregroundStyle(HelmText.faint)
        }
            .frame(width: Self.column)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(onClose: { showWhatsNew = false })
        }
    }

    private static let column: CGFloat = 380

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                // No halo behind the mark: `HelmAppMark` casts its own shadow,
                // and a radial gradient on top of it was a second light source
                // with a visible rim where its ramp ended.
                // The bezel turns only while a check is running: motion here
                // means work, not decoration.
                HelmBezel(active: updater.checking)
                    .frame(width: 172, height: 172)
                HelmAppMark(size: 92)
            }
            .frame(height: 186)
            VStack(spacing: 5) {
                // The badges hang off the wordmark instead of sharing a row
                // with it. In an HStack the pair is centred together, so the
                // name sat left of centre by half the badges' width — under a
                // mark and above a tagline that are both centred on the column,
                // which is where the eye reads the axis from. As an overlay
                // they take no width, so "Helm" is centred on the same line
                // everything else is.
                //
                // Measured on the rendered pixels, not judged
                // (`Scripts/design/measure-wordmark.swift`): in the 380 pt
                // column the row put the word 42.2 pt left of the axis; the
                // overlay puts it at 189.8 against a centre of 190.
                Text("Helm")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.4)
                    .overlay(alignment: .topTrailing) {
                        badge
                            .fixedSize()
                            // The overlay's own leading edge, placed 7 pt past
                            // the end of the word.
                            .alignmentGuide(.trailing) { $0[.leading] - 7 }
                            // The top of the capsule on the top of the H. Not a
                            // guess: at 34 pt semibold the cap starts exactly
                            // 9.00 pt below the line box's top, measured off
                            // the rendered pixels
                            // (Scripts/design/measure-wordmark.swift).
                            .alignmentGuide(.top) { $0[.top] - 9 }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(badgeAccessibilityLabel)
                Text(AppStr.tagline)
                    .font(.subheadline)
                    .foregroundStyle(HelmText.quiet)
            }
        }
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
        HelmBadge(AppBuild.isDev ? AppStr.devBadge : AppStr.betaBadge,
                  tint: AppBuild.isDev ? .blue : .orange,
                  emphasis: .prominent)
            .help(AppBuild.isDev ? AppStr.channelDevNote : AppStr.channelBetaNote)
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
    private var authorRow: some View {
        HStack(spacing: 8) {
            Text(AppStr.author)
                .foregroundStyle(HelmText.quiet)
            Spacer(minLength: 8)
            Text(AppStr.authorName)
            Link(destination: URL(string: "https://t.me/r_strlnkv")!) {
                Label("@r_strlnkv", systemImage: "paperplane.fill")
                    .labelStyle(.titleAndIcon)
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

    private var updateCard: some View {
        VStack(spacing: 0) {
            updateRow
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            // The token, not a divider dimmed by eye: every other hairline in
            // the app is this colour, and 0.6 of a system divider is not a
            // value anybody can match on the next screen over.
            Rectangle()
                .fill(HelmSurface.hairline)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(AppStr.updateChannel)
                        .font(.callout)
                    Spacer()
                    Picker(AppStr.updateChannel, selection: $channel) {
                        Text(AppStr.channelBeta).tag(UpdateCheck.Channel.beta)
                        Text(AppStr.channelDev).tag(UpdateCheck.Channel.dev)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    // Its ideal width, not a reservation: at a fixed 170 the
                    // control drew itself narrower and centred, leaving its
                    // trailing edge short of the Check button directly above.
                    .fixedSize()
                    .onChange(of: channel) { _, newValue in updater.setChannel(newValue) }
                }
                Text(channel == .dev ? AppStr.channelDevNote : AppStr.channelBetaNote)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .helmCard(padding: 0)
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updater.installState {
        case .downloading:
            statusLine(AppStr.downloadingUpdate)
        case .installing:
            statusLine(AppStr.installingUpdate)
        case .digestMismatch:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.danger)
                    Text(AppStr.updateDigestMismatch).lineLimit(3)
                    Spacer()
                }
                // No Retry: downloading the same file again would produce the
                // same answer. The release page is where a person can see what
                // was published and decide.
                if let rel = updater.available {
                    Link(AppStr.download, destination: rel.pageURL)
                        .font(.callout)
                }
            }
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateFailed).lineLimit(2)
                    Spacer()
                }
                if let rel = updater.available {
                    HStack(spacing: 10) {
                        Button(AppStr.retry) { updater.downloadAndInstall() }
                            .frame(maxWidth: .infinity)
                        Link(AppStr.download, destination: rel.downloadURL ?? rel.pageURL)
                            .font(.callout)
                    }
                }
            }
        case .idle:
            if updater.checking {
                statusLine(AppStr.checking)
            } else if let rel = updater.available {
                // The offer is the card's main action, so it gets full width
                // instead of being squeezed next to the label.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        statusIcon("arrow.down.circle.fill", .accentColor)
                        Text(AppStr.updateReady).lineLimit(1)
                        Spacer()
                        Text(rel.version)
                            .font(HelmText.figureFont)
                            .foregroundStyle(HelmText.quiet)
                    }
                    Button(AppStr.updateAndRelaunch) { updater.downloadAndInstall() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            } else if updater.lastMessage == "manual-install" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateManualInstall).lineLimit(3)
                    Spacer()
                }
            } else if updater.lastMessage == "error" {
                HStack(spacing: 10) {
                    statusIcon("exclamationmark.triangle.fill", HelmSignal.warning)
                    Text(AppStr.updateCheckFailed).lineLimit(1)
                    Spacer()
                    Button(AppStr.retry) { updater.checkNow() }
                }
            } else if let newest = updater.aheadOfChannel {
                // Before "up to date", which this state used to be read as: the
                // check reports both, and being ahead is the more specific
                // answer of the two.
                HStack(spacing: 10) {
                    statusIcon("arrow.up.circle.fill", HelmSignal.warning)
                    Text(AppStr.aheadOfChannel(newest))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            } else if updater.lastMessage == "up-to-date" {
                HStack(spacing: 10) {
                    statusIcon("checkmark.circle.fill", HelmSignal.success)
                    Text(AppStr.upToDate).lineLimit(1)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            } else {
                // Nothing has been checked in this session: report when the
                // last check happened rather than claiming to be current.
                HStack(spacing: 10) {
                    statusIcon("arrow.triangle.2.circlepath", .secondary)
                    Text(lastCheckedText).lineLimit(1).foregroundStyle(HelmText.quiet)
                    Spacer()
                    Button(AppStr.checkNow) { updater.checkNow() }
                }
            }
        }
    }

    /// "Checked 2 hours ago" from the stored timestamp, or a never-checked note.
    private var lastCheckedText: String {
        let stamp = AppSettings.store.int("lastUpdateCheck", default: 0)
        // The same reading `checkOnLaunch` makes of the same key, so the line
        // cannot say "checked 2 hours ago" about a number that stopped the
        // check from running.
        guard let when = UpdateCheck.lastChecked(stored: stamp, now: Date()) else {
            return AppStr.neverChecked
        }
        return AppStr.lastChecked(HelmDates.relative(when))
    }

    /// Always spinning: every state that draws this line is work in flight. It
    /// took a `spinning:` flag that all three call sites passed `true` and the
    /// body never read.
    private func statusLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(HelmText.quiet)
            Spacer()
        }
    }

    private func statusIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15))
            .foregroundStyle(color)
    }
}

/// A compass/helm bezel: fine tick marks ringing the app icon, every fifth one
/// longer. It rotates only while an update check is in flight.
private struct HelmBezel: View {
    var active: Bool
    /// Where the dial stands when nothing is driving it.
    @State private var resting: Double = 0
    /// When the current turn began — the angle is a **function of time**, not a
    /// value being animated towards.
    ///
    /// It was the latter, and that is why stopping rewound the wheel: with
    /// `repeatForever` the model sits at 360 while the dial is somewhere inside
    /// the turn, so retargeting to 0 runs backwards from wherever it happens to
    /// be. Driven from a clock there is no target to retarget — the stop reads
    /// the angle actually reached and coasts forward from there.
    @State private var since: Date?

    private static let secondsPerTurn: Double = 6

    private func angle(_ now: Date) -> Double {
        guard let since else { return resting }
        return resting + now.timeIntervalSince(since) / Self.secondsPerTurn * 360
    }

    var body: some View {
        // Paused rather than switched away from: an `if` here would swap the
        // view's identity at the moment of stopping, and a newly inserted view
        // has no previous angle to interpolate from — the coast would not play.
        TimelineView(.animation(paused: since == nil)) { timeline in
            dial.rotationEffect(.degrees(angle(timeline.date)))
        }
        .onChange(of: active) { _, running in
            if running {
                // Reduce Motion: no spin at all, rather than a fast one.
                guard !HelmMotion.reduceMotion else { return }
                since = .now
            } else if since != nil {
                let reached = angle(.now)
                since = nil
                resting = reached
                withAnimation(HelmMotion.spinDown) { resting = reached + 24 }
            }
        }
        .accessibilityHidden(true)
    }

    private var dial: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for tick in 0..<60 {
                let long = tick % 5 == 0
                let length: CGFloat = long ? 7 : 4
                let a = Double(tick) / 60 * 2 * .pi
                let outer = CGPoint(x: center.x + cos(a) * radius,
                                    y: center.y + sin(a) * radius)
                let inner = CGPoint(x: center.x + cos(a) * (radius - length),
                                    y: center.y + sin(a) * (radius - length))
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path,
                               with: .color(.primary.opacity(long ? 0.20 : 0.10)),
                               lineWidth: long ? 1.4 : 1)
            }
        }
    }
}

/// Localized, structured changelog with New/Upd/Fix badges.
private struct WhatsNewView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "sparkles", tint: .indigo,
                           title: AppStr.whatsNew, subtitle: AppStr.whatsNewSummary) {
                // Escape closes it, like every sheet on the machine.
                // `HelmHotkeyRecorder` special-cases Escape during capture and
                // explains why; that care never reached the sheets.
                Button(AppStr.close, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Changelog.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.version).font(.title3.bold())
                                // The entry stores "2026-07-28" because that is
                                // what sorts; no language writes it that way.
                                Text(HelmDates.day(entry.date))
                                    .font(.caption).foregroundStyle(HelmText.faint)
                            }
                            ForEach(entry.items) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    badge(item.kind)
                                    Text(item.text).font(.callout).foregroundStyle(HelmText.quiet)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Matches the header plate above it, which sits at 20.
                .padding(.horizontal, 20).padding(.vertical, 16)
            }
        }
        .frame(width: 520, height: 460)
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
