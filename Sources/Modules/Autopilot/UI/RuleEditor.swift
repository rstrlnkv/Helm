import AppKit
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// Writing one rule: when, then, and what that would do to the folder as it
/// stands.
///
/// The dry run is not a convenience here. A rule is a decision made once and
/// carried out from then on, so the editor's job is to make the consequence
/// visible before the switch is reachable — the same discipline as the
/// duplicate basket, one level earlier.
struct RuleEditor: View {
    @ObservedObject var rvm: AutopilotViewModel
    let folder: WatchedFolder
    @State private var rule: Rule
    @Environment(\.dismiss) private var dismiss

    init(rvm: AutopilotViewModel, folder: WatchedFolder, rule: Rule) {
        self.rvm = rvm
        self.folder = folder
        _rule = State(initialValue: rule)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    conditions
                    action
                    dryRun
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 620)
        .task { await rvm.runPreview(for: folder, rule: rule) }
        .onDisappear { rvm.clearPreview() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HelmIconPlate(symbol: "location.north.circle",
                          tint: ModuleCategory.files.tint, size: 26)
            TextField(ApStr.ruleName, text: $rule.name)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - When

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(ApStr.whenLabel).font(.headline)
                // "When" is a heading beside it, not this control's name:
                // headings are not read as labels, so the segmented control
                // announced only "all"/"any" with nothing to attach them to.
                Picker(ApStr.a11yMatch, selection: $rule.match) {
                    Text(ApStr.matchAll).tag(RuleMatch.all)
                    Text(ApStr.matchAny).tag(RuleMatch.any)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Button(ApStr.addCondition) {
                    rule.conditions.append(.name(.contains, ""))
                }
                .controlSize(.small)
            }
            ForEach(Array(rule.conditions.enumerated()), id: \.offset) { index, _ in
                ConditionRow(condition: Binding(
                    get: { rule.conditions[index] },
                    set: { rule.conditions[index] = $0 })) {
                        rule.conditions.remove(at: index)
                    }
            }
            if rule.conditions.isEmpty {
                // Stated rather than left to be discovered: an empty rule
                // matching nothing is a deliberate choice, and the screen that
                // lets someone make one has to say so.
                Text(ApStr.nothingWouldHappen)
                    .font(.caption).foregroundStyle(HelmText.faint)
            }
        }
    }

    // MARK: - Then

    private var action: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ApStr.thenLabel).font(.headline)
            ActionRow(action: $rule.action)
        }
    }

    // MARK: - What would happen

    private var dryRun: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ApStr.dryRun).font(.headline)
                Spacer()
                if rvm.previewingRuleID == rule.id, !rvm.preview.isEmpty {
                    Text("\(rvm.preview.count)")
                        .font(.caption).foregroundStyle(HelmText.faint)
                        .contentTransition(.numericText())
                }
            }
            Text(ApStr.dryRunNote)
                .font(.caption).foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
            if rvm.preview.isEmpty {
                Text(ApStr.nothingWouldHappen)
                    .font(.callout).foregroundStyle(HelmText.quiet)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(rvm.preview) { row in
                        HStack(spacing: 8) {
                            Text(row.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            // The action, and where it lands. Naming only the
                            // action left the reader to work out which
                            // subfolder "sort by kind" meant — the one thing
                            // the rule they just wrote does not tell them.
                            if let destination = row.destination {
                                Text(destination)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(HelmText.quiet)
                                    .lineLimit(1).truncationMode(.middle)
                                Text("←").font(.caption).foregroundStyle(HelmText.separator)
                            }
                            Text(RuleSummary.describe(row.action))
                                .font(.caption).foregroundStyle(HelmText.faint)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 5)
                        // One stop per file, not four. This is the list whose
                        // whole purpose is making the consequence audible before
                        // the switch is reachable, and read as loose fragments —
                        // name, destination, arrow, action — it says least to
                        // the reader who most depends on it.
                        .accessibilityElement(children: .combine)
                        if row.id != rvm.preview.last?.id { Divider() }
                    }
                }
                .helmCard()
            }
        }
        // Re-asked as the rule is written, so the list answers the rule on
        // screen rather than the one before the last keystroke.
        .task(id: previewKey) { await rvm.runPreview(for: folder, rule: rule) }
    }

    /// What a change to the rule means for the preview. The name is not in it:
    /// renaming a rule cannot change what it would do.
    private var previewKey: String {
        var key = rule.match.rawValue
        for condition in rule.conditions { key += RuleSummary.describe(condition) }
        return key + RuleSummary.describe(rule.action)
    }

    private var footer: some View {
        HStack {
            Toggle(ApStr.enableRule, isOn: $rule.enabled)
                .toggleStyle(.switch)
                // A rule with no conditions matches nothing, and one whose
                // action names nothing — a move with no destination, which is
                // where "Move to" starts — refuses everything. Switching either
                // on would be switching on a rule that cannot work. The
                // predicate is the engine's, so this and `storable` cannot
                // drift apart.
                .disabled(!rule.canBeEnabled)
            Spacer()
            // The two keys every sheet on this system answers to, and this is
            // the sheet a keyboard has furthest to travel across: conditions,
            // pickers, fields, the dry run. Escape did not close it at all.
            // Nothing here claims Return — none of `ConditionRow`'s fields calls
            // `.onSubmit` — so the default button is free to take it.
            Button(ApStr.cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(ApStr.done) {
                rvm.save(rule, in: folder)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }
}
