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
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        override: AppSettings.loggingOverride)

    private var isDevBuild: Bool {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "").contains("-dev")
    }

    private var shown: [LogEntry] {
        LogFilter.apply(entries, minimumLevel: minimumLevel, categories: chosen)
    }

    var body: some View {
        VStack(spacing: 0) {
            HelmPageHeader(symbol: "text.alignleft", tint: .gray,
                           title: AppStr.logPane, subtitle: AppStr.logPaneSummary)
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
                Text(isDevBuild ? AppStr.logNoteDev : AppStr.logNoteStable)
                    .font(.callout)
                Text(AppStr.logRedactionNote)
                    .font(.caption).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([HelmLog.fileURL])
            } label: {
                Label(AppStr.revealLog, systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.small)
            Toggle("", isOn: $loggingOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(AppStr.writeLog)
                .disabled(isDevBuild)
                .onChange(of: loggingOn) { _, value in
                    AppSettings.loggingOverride = value
                    HelmLog.shared.setEnabled(value)
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
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
                // Both, because there is one Clear now and a person pressing it
                // means the log, not the window onto it.
                HelmLog.shared.clear()
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
