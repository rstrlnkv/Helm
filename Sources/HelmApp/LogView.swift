// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI

/// The log, while it is being written.
///
/// Not a diagnostics dashboard: it invents no figure and computes nothing. It
/// shows the lines the app already writes — the same `write`, the same format,
/// the same truth — so that watching Helm misbehave does not mean leaving it,
/// finding `~/Library/Logs/Helm` and reading what already happened.
///
/// Shown on every build, because this is also where the log is switched on. It
/// used to be dev-only, and the switch lived in Settings under "Diagnostics" —
/// two places for one subject, and the one a person is told to press when they
/// report a problem was not the one named after it.
struct LogView: View {
    /// Polled rather than subscribed. A log has no interesting event to observe
    /// — it has a tail — and one timer that exists while the page is on screen
    /// is cheaper to reason about than a stream that has to be finished.
    @State private var entries: [LogEntry] = []
    @State private var minimumLevel: LogLevel = .info
    @State private var chosen: Set<String> = []
    @State private var following = true
    @State private var tick: RepeatingTick?
    @State private var loggingOn = LogPolicy.isEnabled(
        version: AppBuild.shortVersion ?? "0",
        override: AppSettings.loggingOverride)

    private var shown: [LogEntry] {
        LogFilter.apply(entries, minimumLevel: minimumLevel, categories: chosen)
    }

    var body: some View {
        VStack(spacing: 0) {
            // `bleeds: true` like every other full-width page: without it the
            // header caps at `HelmLayout.settingsColumn` and centres, which put
            // its icon at x = 53 against the rows' x = 21 on this pane.
            HelmPageHeader(symbol: "text.alignleft", tint: .gray,
                           title: AppStr.logPane, subtitle: AppStr.logPaneSummary,
                           bleeds: true)
            Divider()
            writing
            Divider()
            filters
            Divider()
            lines
            Divider()
            footer
        }
        .onAppear {
            refresh()
            // One second: the log is read, not animated, and a person watching
            // it is reading the line that just arrived rather than counting
            // frames.
            let made = RepeatingTick(interval: 1) { refresh() }
            tick = made
            made.set(active: true)
        }
        .onDisappear {
            tick?.set(active: false)
            tick = nil
        }
    }

    /// Whether anything is written to the file at all, and what ends up in it.
    /// Dev builds always log — the file is the evidence a build is triaged on —
    /// so the switch is theirs to read, not to change.
    private var writing: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppBuild.isDev ? AppStr.logNoteDev : AppStr.logNoteStable)
                    .font(.callout)
                Text(AppStr.logRedactionNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                HelmReveal.inFinder(HelmLog.fileURL.path)
            } label: {
                Label(AppStr.revealLog, systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.small)
            Toggle("", isOn: $loggingOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(AppStr.writeLog)
                .disabled(AppBuild.isDev)
                .onChange(of: loggingOn) { _, value in
                    AppSettings.loggingOverride = value
                    HelmLog.shared.setEnabled(value)
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private var levelLabels: [String] {
        [AppStr.logLevelAll, AppStr.logLevelWarnings, AppStr.logLevelErrors]
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker(AppStr.logLevel, selection: $minimumLevel) {
                Text(levelLabels[0]).tag(LogLevel.info)
                Text(levelLabels[1]).tag(LogLevel.warn)
                Text(levelLabels[2]).tag(LogLevel.error)
            }
            .pickerStyle(.segmented).labelsHidden()
            // Measured, not 260: that was 3 pt from clipping in Russian and
            // 110 pt too wide in Chinese.
            .frame(width: HelmPickerWidth.segmented(levelLabels))

            // Built from what has arrived, so it names the modules that spoke
            // rather than the nine that exist.
            Menu {
                Button(AppStr.logAllModules) { chosen = [] }
                Divider()
                ForEach(LogFilter.categories(in: entries), id: \.self) { category in
                    Toggle(category, isOn: Binding(
                        get: { chosen.contains(category) },
                        set: { on in
                            if on { chosen.insert(category) } else { chosen.remove(category) }
                        }))
                }
            } label: {
                Text(chosen.isEmpty ? AppStr.logAllModules
                                    : AppStr.logSomeModules(chosen.count))
            }
            .menuStyle(.borderlessButton)
            // 200 was never needed — the widest label wants 133 — and a
            // borderless menu centres its label in whatever frame it is given,
            // leaving 57 pt of gap and 59 pt of invisible clickable area.
            .fixedSize()

            Spacer(minLength: 12)
            // A button rather than a checkbox: three bezelled controls read as
            // one row, and the Portuguese label wrapped to two lines inside a
            // checkbox at the minimum window.
            Toggle(isOn: $following) {
                Label(AppStr.logFollow, systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .fixedSize()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder private var lines: some View {
        if shown.isEmpty {
            // No symbol: the header already draws this exact mark 610 pt above,
            // and `HelmEmptyState`'s own rule is that a statement is a sentence
            // and nothing else.
            HelmEmptyState(message: entries.isEmpty ? AppStr.logEmpty
                                                    : AppStr.logNothingMatches) {
                if !entries.isEmpty {
                    Button(AppStr.logAllModules) {
                        chosen = []
                        minimumLevel = .info
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Spacing on the row, not between rows, so a level's wash
                    // is one block behind a wrapped line instead of a stripe.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { entry in
                            row(entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The identity of the newest line, not the count. `LogTail`
                // caps at 1000, so once the buffer is full the count is 1000
                // forever, `onChange` never fires again, and the pane stops
                // following while the control still says it is — about a day of
                // dev-build use.
                .onChange(of: shown.last?.id) { _, _ in
                    guard following, let last = shown.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// One line. The level is a leading rule and a wash behind the whole row —
    /// measured at 4.5:1 and better in both appearances for the rule, while the
    /// category word it used to tint carried 3.8% of the row's ink and answered
    /// the wrong question: the tint says "bad", the word says "who".
    ///
    /// The wash is 0.06 rather than 0.09 because `HelmText.faint` measured 3.47:1
    /// on the heavier one — under what that token was solved for.
    @ViewBuilder private func row(_ entry: LogEntry) -> some View {
        let signal = tint(for: entry.level)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // One literal with two interpolations. Built as `"\(a)" + "\(b)"`
            // first, which is String concatenation — so each `Text` was rendered
            // through its own `description` and the row printed
            // `Text(storage: SwiftUI.Text.Storage.verbatim("16:29:07")…)`.
            Text("\(Text(HelmDates.logTime(entry.date)).foregroundStyle(HelmText.quiet))\(Text(HelmDates.logMillis(entry.date)).foregroundStyle(HelmText.faint))")
                .helmFigure()
            Text(entry.category)
                .font(.caption.weight(.medium))
                .foregroundStyle(HelmText.faint)
                // 116, and a limit: three categories in the source are longer
                // than the old 92 — `homebrew.listInstalled` wrapped and made
                // the row twice as tall with a blank half beside it.
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 116, alignment: .leading)
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(entry.level == .info ? HelmText.quiet : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 20)
        // The wash fills the row; the rule sits at its left edge. Written as
        // two views inside `background(alignment:)` first, which stacks them
        // with the *default* centre alignment — so the 3 pt rule landed in the
        // middle of the line instead of beside it.
        .background {
            if let signal {
                ZStack(alignment: .leading) {
                    signal.opacity(0.06)
                    Rectangle().fill(signal).frame(width: 3)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Nil for an ordinary line, so an info row gains no layers at all: only
    /// realised rows exist in a `LazyVStack`, and at the real 4.4% warning rate
    /// that is one or two shapes on screen.
    private func tint(for level: LogLevel) -> Color? {
        switch level {
        case .info: return nil
        case .warn: return HelmSignal.warning
        case .error: return HelmSignal.danger
        }
    }

    private var footer: some View {
        HStack {
            Button(AppStr.copyLog) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    shown.map { "\(HelmDates.logTime($0.date)) [\($0.category)] \($0.message)" }
                        .joined(separator: "\n"), forType: .string)
            }
            .disabled(shown.isEmpty)
            Button(AppStr.clearLog) {
                // Both, because there is one Clear now and a person pressing it
                // means the log, not the window onto it.
                HelmLog.shared.clear()
                HelmLog.shared.clearTail()
                entries = []
            }
            .disabled(entries.isEmpty)
            Spacer()
            Text(AppStr.logCount(shown.count, entries.count))
                .font(.caption).foregroundStyle(HelmText.quiet)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func refresh() {
        entries = HelmLog.shared.recentEntries()
    }
}
