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
/// **Dev builds only, gated on the build and not on the update channel.** The
/// channel picker is an ordinary control on the General page: gating on it would
/// put this in front of anyone impatient for updates, on a shipped beta build.
/// `SettingsWindow` already learned this distinction for the version badge.
struct LogView: View {
    /// Polled rather than subscribed. A log has no interesting event to observe
    /// — it has a tail — and one timer that exists while the page is on screen
    /// is cheaper to reason about than a stream that has to be finished.
    @State private var entries: [LogEntry] = []
    @State private var minimumLevel: LogLevel = .info
    @State private var chosen: Set<String> = []
    @State private var following = true
    @State private var tick: RepeatingTick?

    private var shown: [LogEntry] {
        LogFilter.apply(entries, minimumLevel: minimumLevel, categories: chosen)
    }

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "text.alignleft", tint: .gray,
                           title: AppStr.logPane, subtitle: AppStr.logPaneSummary)
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

    private var filters: some View {
        HStack(spacing: 12) {
            Picker(AppStr.logLevel, selection: $minimumLevel) {
                Text(AppStr.logLevelAll).tag(LogLevel.info)
                Text(AppStr.logLevelWarnings).tag(LogLevel.warn)
                Text(AppStr.logLevelErrors).tag(LogLevel.error)
            }
            .pickerStyle(.segmented).labelsHidden()
            .frame(width: 260)

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
            .frame(width: 200)

            Spacer(minLength: 0)
            Toggle(AppStr.logFollow, isOn: $following)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    @ViewBuilder private var lines: some View {
        if shown.isEmpty {
            HelmEmptyState(symbol: "text.alignleft", tint: .gray,
                           message: entries.isEmpty ? AppStr.logEmpty : AppStr.logNothingMatches) {}
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { entry in
                            row(entry).id(entry.id)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: shown.count) { _, _ in
                    guard following, let last = shown.last else { return }
                    withAnimation(HelmMotion.interface) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(HelmDates.logTime(entry.date))
                .helmFigure().foregroundStyle(HelmText.faint)
            Text(entry.category)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint(for: entry.level))
                .frame(width: 92, alignment: .leading)
            Text(entry.message)
                .font(.caption)
                .foregroundStyle(entry.level == .info ? HelmText.quiet : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func tint(for level: LogLevel) -> Color {
        switch level {
        case .info: return HelmText.faint
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
            Button(AppStr.clearLog) {
                HelmLog.shared.clearTail()
                entries = []
            }
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
