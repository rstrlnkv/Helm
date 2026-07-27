import HelmContract
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// The module's page: the folders being watched, and each one's rules in the
/// order they will be tried.
public struct AutopilotSettingsPage: View {
    @StateObject private var rvm: AutopilotViewModel
    @State private var editing: EditingRule?
    @State private var diskAccess: PermissionState = .granted

    /// A rule and the folder it belongs to, which the editor needs both of.
    struct EditingRule: Identifiable {
        let folder: WatchedFolder
        var rule: Rule
        var id: String { rule.id }
    }

    public init(vm: ModuleViewModel) {
        _rvm = StateObject(wrappedValue: AutopilotViewModel(vm: vm))
    }

    public var body: some View {
        VStack(spacing: 0) {
            if diskAccess == .denied {
                HelmPermissionNote(need: .fullDiskAccess, text: ApStr.needsAccess)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }
            // Nothing to say about the order of rules when there are no
            // folders: the page's own call to action is the whole screen.
            if !rvm.folders.isEmpty {
                toolbar
                Divider()
            }
            content
            if let banner = rvm.banner {
                Divider()
                HStack {
                    Text(banner).font(.callout)
                    Spacer()
                    Button(ApStr.done) { rvm.dismissBanner() }.controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .helmOnAppActive { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .task { diskAccess = PermissionCheck.currentFullDiskAccess() }
        .animation(HelmMotion.interface, value: rvm.folders.count)
        .sheet(item: $editing) { context in
            RuleEditor(rvm: rvm, folder: context.folder, rule: context.rule)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text(ApStr.firstMatchNote)
                .font(.caption).foregroundStyle(HelmText.faint)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(ApStr.addFolder) { rvm.addFolder() }
                .controlSize(.small)
                .fixedSize()
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
    }

    @ViewBuilder private var content: some View {
        if rvm.folders.isEmpty {
            HelmCenteredContent(spacing: 14) {
                HelmIconPlate(symbol: "location.north.circle",
                              tint: ModuleCategory.files.tint, size: 56)
                Text(ApStr.startHint)
                    .foregroundStyle(HelmText.quiet)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button(ApStr.addFolder) { rvm.addFolder() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        } else {
            List {
                ForEach(rvm.folders) { folder in
                    Section {
                        folderRows(folder)
                    } header: {
                        folderHeader(folder)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func folderHeader(_ folder: WatchedFolder) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { folder.enabled },
                                     set: { rvm.setEnabled($0, folder: folder) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Redact.path(folder.path))
            Text(Redact.path(folder.path))
                .font(.callout.weight(.semibold))
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
            .fixedSize()
        }
    }

    @ViewBuilder private func folderRows(_ folder: WatchedFolder) -> some View {
        if folder.rules.isEmpty {
            Text(ApStr.noRules)
                .font(.callout).foregroundStyle(HelmText.faint)
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
        HStack(spacing: 10) {
            // A rule is on or off; it is never half-on, so the switch is the
            // whole story and the row does not need a badge as well.
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { on in
                var copy = rule
                copy.enabled = on
                rvm.save(copy, in: folder)
            }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel(rule.name)

            VStack(alignment: .leading, spacing: 1) {
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
            .accessibilityLabel(ApStr.edit)
            // The order is the rule: the arrows are how it is set, and they are
            // reachable from the keyboard, which a drag is not.
            Button { rvm.move(rule, in: folder, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(HelmA11y.moveUp)
            .disabled(folder.rules.first?.id == rule.id)
            Button { rvm.move(rule, in: folder, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(HelmA11y.moveDown)
            .disabled(folder.rules.last?.id == rule.id)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(ApStr.edit) { editing = EditingRule(folder: folder, rule: rule) }
            Button(ApStr.delete, role: .destructive) { rvm.remove(rule, from: folder) }
        }
    }
}
