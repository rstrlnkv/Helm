import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// The module's page: the folders being watched, and each one's rules in the
/// order they will be tried.
struct AutopilotSettingsPage: View {
    @StateObject private var rvm: AutopilotViewModel
    @State private var editing: EditingRule?
    @State private var diskAccess: PermissionState = .granted

    /// A rule and the folder it belongs to, which the editor needs both of.
    struct EditingRule: Identifiable {
        let folder: WatchedFolder
        var rule: Rule
        var id: String { rule.id }
    }

    init(vm: ModuleViewModel) {
        _rvm = StateObject(wrappedValue: AutopilotViewModel(vm: vm))
    }

    var body: some View {
        VStack(spacing: 0) {
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: ApStr.needsAccess)
                    .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
                Divider()
            }
            // Nothing to say about the order of rules unless the rules are what
            // is on screen: the empty state's own call to action is the whole
            // page, and a refusal is a statement about rules that are not
            // running. One value decides both halves — `folders.isEmpty` was a
            // second answer to the same question, and it read a refused rule set
            // as a Mac with nothing on it.
            if rvm.screen == .folders {
                toolbar
                Divider()
            }
            content
            if let banner = rvm.banner {
                Divider()
                HStack(alignment: .top) {
                    // A return's report is several lines — one per file that
                    // did not go back, with its reason — and a single-line
                    // banner would truncate exactly the part that explains
                    // itself.
                    Text(banner).font(HelmText.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    // The pass this run just made, offered where the sentence
                    // about it is.
                    if let pass = rvm.bannerRun {
                        Button(ApStr.putBackFiles(pass.undoable.count)) {
                            Task { await rvm.undoRun(pass) }
                        }
                        .controlSize(.small)
                    }
                    Button(ApStr.done) { rvm.dismissBanner() }.controlSize(.small)
                }
                .padding(.horizontal, HelmLayout.formInset).padding(.vertical, 12)
            }
        }
        .helmTracksFullDiskAccess($diskAccess)
        .animation(HelmMotion.interface, value: rvm.folders.count)
        .sheet(item: $editing) { context in
            RuleEditor(rvm: rvm, folder: context.folder, rule: context.rule)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(ApStr.firstMatchNote)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(ApStr.addFolder) { rvm.addFolder() }
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    @ViewBuilder private var content: some View {
        switch rvm.screen {
        case let .rulesRefused(reason):
            refused(reason)
        case .noFolders:
            HelmEmptyState(symbol: "location.north.circle", tint: ModuleCategory.files.tint,
                           message: ApStr.startHint) {
                Button(ApStr.addFolder) { rvm.addFolder() }
                    .buttonStyle(.borderedProminent)
            }
        case .folders:
            List {
                ForEach(rvm.folders) { folder in
                    Section {
                        folderRows(folder)
                    } header: {
                        folderHeader(folder)
                    }
                }
                Section {
                    HistorySection(history: rvm.history, runs: rvm.runs,
                                   clear: { rvm.clearHistory() },
                                   refused: rvm.historyRefused,
                                   canPutBack: rvm.canPutBack,
                                   canPutBackRun: rvm.canPutBack,
                                   putBack: { record in Task { await rvm.undo(record) } },
                                   putBackRun: { pass in Task { await rvm.undoRun(pass) } })
                }
            }
            .listStyle(.inset)
            // The engine acts on a timer and on files arriving, so what the
            // page holds is whatever was true when it opened.
            .task { await rvm.loadHistory() }
        }
    }

    /// The screen a person gets instead of «you have no folders» when the rules
    /// on disk are not Helm's to run.
    ///
    /// Not dismissible, and not a `banner`: the banner is a report of a sweep
    /// that has finished, and this is a standing statement about work that is not
    /// happening. The only control is on the branch where there is something to
    /// do — a keychain that would not answer is answered by waiting, and offering
    /// to delete somebody's rules over it would be the worst button in the app.
    @ViewBuilder private func refused(_ reason: RuleRefusal) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            switch reason {
            case .tampered:
                HelmBanner(ApStr.rulesTampered) {
                    Button(ApStr.discardRules, role: .destructive) {
                        Task { await rvm.discardRefusedRules() }
                    }
                    .controlSize(.small)
                }
            case .noKey:
                HelmBanner(ApStr.rulesUnreadable)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmLayout.formInset)
        .padding(.vertical, HelmSpace.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func folderHeader(_ folder: WatchedFolder) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            folderRow(folder)
            // **A switch that says «on» over a folder that is gone.** The reading
            // and the stream are facts about the world, not about the rules, and
            // both stop being true with nobody touching Helm. Beside the path
            // rather than in a banner at the foot of the page: the page can watch
            // several folders and only one of them is the one this is about.
            if let notice = rvm.notice(for: folder) {
                HelmBanner(notice)
            }
        }
    }

    private func folderRow(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { folder.enabled },
                                     set: { rvm.setEnabled($0, folder: folder) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Redact.path(folder.path))
            Text(Redact.path(folder.path))
                .font(HelmText.sectionHeading)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button(ApStr.runNow) { Task { await rvm.runNow(folder) } }
                .controlSize(.small)
                .disabled(folder.rules.allSatisfy { !$0.enabled })
            Menu {
                Toggle(ApStr.depth, isOn: Binding(get: { folder.depth > 1 },
                                                  set: { rvm.setDepth($0, folder: folder) }))
                Button(ApStr.removeFolder, role: .destructive) { rvm.removeFolder(folder) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(HelmA11y.moreActions)
            .fixedSize()
        }
    }

    @ViewBuilder private func folderRows(_ folder: WatchedFolder) -> some View {
        if folder.rules.isEmpty {
            Text(ApStr.noRules)
                .font(HelmText.rowTitle).foregroundStyle(HelmText.faint)
        }
        ForEach(folder.rules) { rule in
            ruleRow(rule, in: folder)
        }
        Button(ApStr.newRule) {
            editing = EditingRule(folder: folder, rule: rvm.addRule(to: folder))
        }
        .controlSize(.small)
    }

    private func ruleRow(_ rule: Rule, in folder: WatchedFolder) -> some View {
        HStack(spacing: HelmSpace.s5) {
            // A rule is on or off; it is never half-on, so the switch is the
            // whole story and the row does not need a badge as well.
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { on in
                var copy = rule
                copy.enabled = on
                Task { await rvm.save(copy, in: folder) }
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel(rule.name)

            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(rule.name).lineLimit(1)
                Text(RuleSummary.describe(rule))
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)

            Spacer()
            // A tap on the row does not open anything: inside a `List` a tap is
            // the list's, for selection, and a gesture that competes with it
            // works about half the time. The button is unambiguous and it is
            // where the eye already is.
            Button { editing = EditingRule(folder: folder, rule: rule) } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(ApStr.edit), \(rule.name)")
            // The order is the rule: the arrows are how it is set, and they are
            // reachable from the keyboard, which a drag is not.
            Button { rvm.move(rule, in: folder, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(HelmA11y.moveUp), \(rule.name)")
            .disabled(folder.rules.first?.id == rule.id)
            Button { rvm.move(rule, in: folder, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(HelmA11y.moveDown), \(rule.name)")
            .disabled(folder.rules.last?.id == rule.id)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(ApStr.edit) { editing = EditingRule(folder: folder, rule: rule) }
            Button(ApStr.delete, role: .destructive) { rvm.remove(rule, from: folder) }
        }
    }
}
