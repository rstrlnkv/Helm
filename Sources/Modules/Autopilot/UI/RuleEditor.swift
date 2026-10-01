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
    /// State and not a constant, because a preset's editor can be pointed at
    /// another folder (`chooseFolder`); every other editor never changes it.
    @State private var folder: WatchedFolder
    @State private var rule: Rule
    /// The preset this draft is, or nil for a rule somebody wrote or opened. Only
    /// a preset's folder is a default the person may replace: any other rule is
    /// already in the folder it belongs to.
    private let preset: RulePreset?
    /// A folder was chosen and `WatchScope` refused it. Cleared by the next
    /// choice; nothing else changed, so the sentence is about the choice alone.
    @State private var outOfReach = false
    @Environment(\.dismiss) private var dismiss

    init(rvm: AutopilotViewModel, folder: WatchedFolder, rule: Rule,
         preset: RulePreset? = nil) {
        self.rvm = rvm
        _folder = State(initialValue: folder)
        _rule = State(initialValue: rule)
        self.preset = preset
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    folderLine
                    conditions
                    action
                    dryRun
                }
                .padding(HelmLayout.formInset)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 620)
        // No bare `.task` here: the dry-run section's `.task(id: previewKey)`
        // fires on appearance too, so a second one at the root made every
        // opening read the whole watched folder twice, back to back —
        // `TheEditorAsksForOneDryRunTests` counts.
        .onDisappear { rvm.clearPreview() }
    }

    private var header: some View {
        HStack(spacing: HelmSpace.s5) {
            HelmIconPlate(symbol: "location.north.circle",
                          tint: AutopilotDescriptor.tint.colour, size: 26)
            TextField(ApStr.ruleName, text: $rule.name)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }

    // MARK: - Where

    /// **The folder this rule acts in, named where it is decided.** A preset's
    /// folder arrived because `FileManager` named it, and Done is what starts
    /// watching it — so the sheet says which folder, and, while Done is followed
    /// by a sweep, that it acts straight away. The sentence is gated on the view
    /// model's own `sweepsAfterSaving`, the expression the sweep reads, so the
    /// two cannot disagree.
    private var folderLine: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HStack(spacing: HelmSpace.s3) {
                Image(systemName: "folder").foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
                Text(folderName).font(HelmText.sectionHeading)
                Text(Redact.path(folder.path))
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: HelmSpace.s5)
                if preset != nil {
                    Button(ApStr.chooseDestination) { chooseFolder() }
                        .controlSize(.small)
                }
            }
            .accessibilityElement(children: .contain)
            if outOfReach {
                HelmBanner(ApStr.folderOutOfReach)
            }
            if rvm.sweepsAfterSaving(rule, in: folder) {
                Text(ApStr.savingStartsTheWatch)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .helmAnnounces(outOfReach ? ApStr.folderOutOfReach : nil)
    }

    /// What this folder is called: macOS's own name for it, and the last path
    /// component for one macOS does not name.
    private var folderName: String {
        SystemFolderNames.displayOrOwn(path: folder.path, home: NSHomeDirectory(),
                                       language: AppLanguage.current.rawValue)
    }

    /// The panel is the only way another folder gets in, as everywhere in this
    /// module. A cancelled panel changes nothing and says nothing.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = ApStr.chooseDestination
        panel.directoryURL = URL(fileURLWithPath: folder.path)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let next = Self.pointing(rule, at: url.path, from: folder,
                                       preset: preset, rvm: rvm) else {
            outOfReach = true
            return
        }
        outOfReach = false
        folder = next.folder
        rule = next.rule
    }

    /// The editor's state once a folder was chosen, or nil when the gate refuses
    /// it — in which case nothing is handed back to change, so a refusal cannot
    /// leave a half-pointed editor behind.
    ///
    /// **The preset's name goes with the folder too, unless it was edited** —
    /// over Invoices a rule still called «Downloads sorted by kind» is a name
    /// that lies, and it is what the list then shows under that folder. «Unedited»
    /// is the name the view model builds for the folder being left
    /// (`presetName`), so a name the person typed is never rebuilt, and choosing
    /// the preset's own folder again restores the name it began with.
    ///
    /// **The preset's action goes with the folder, unless it was edited.** A
    /// preset that moves into `Screenshots` names an absolute path inside its own
    /// folder, so leaving it would move files out of one folder into another's
    /// subfolder; one the person changed is theirs and is left alone. «Unedited»
    /// is the preset's action in the old folder, compared as the engine's own
    /// `Equatable` value rather than as text.
    static func pointing(_ rule: Rule, at path: String, from folder: WatchedFolder,
                         preset: RulePreset?, rvm: AutopilotViewModel)
        -> (folder: WatchedFolder, rule: Rule)? {
        guard let chosen = rvm.draftFolder(at: path) else { return nil }
        var pointed = rule
        if let preset, rule.action == preset.action.action(in: folder.path) {
            pointed.action = preset.action.action(in: chosen.path)
        }
        if let preset, rule.name == rvm.presetName(preset, at: folder.path) {
            pointed.name = rvm.presetName(preset, at: chosen.path)
        }
        return (chosen, pointed)
    }

    // MARK: - When

    private var conditions: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            HStack(spacing: 8) {
                Text(ApStr.whenLabel).font(HelmText.sectionHeading)
                    // A heading over the conditions, so the rotor can move
                    // between the sheet's three sections instead of swiping
                    // through every condition row to reach «Then».
                    .accessibilityAddTraits(.isHeader)
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
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
            }
        }
    }

    // MARK: - Then

    private var action: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(ApStr.thenLabel).font(HelmText.sectionHeading)
                .accessibilityAddTraits(.isHeader)
            ActionRow(action: $rule.action)
        }
    }

    // MARK: - What would happen

    private var dryRun: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ApStr.dryRun).font(HelmText.sectionHeading)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // This rule's own count, not the folder's: the list below holds
                // the rows another rule takes as well, and a figure that counted
                // those would be the old promise with a number on it.
                if rvm.previewingRuleID == rule.id, !rvm.previewByThisRule.isEmpty {
                    Text("\(rvm.previewByThisRule.count)")
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                        .contentTransition(.numericText())
                        // A `contentTransition` outside a transaction is a
                        // decoration that cannot fire: measured on a digit
                        // changing, the bare modifier draws one value and the
                        // same view with this line draws twelve. Every other
                        // rolling figure in the app already carries it.
                        .animation(HelmMotion.interface, value: rvm.previewByThisRule.count)
                }
            }
            Text(ApStr.dryRunNote)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
            // **The one thing about this rule that is not on this screen.** How
            // deep a folder is watched belongs to the folder, not to the rule —
            // a preset does not change it, and neither does this editor — and
            // it decides how much of somebody's tree the rule below reaches.
            // Beside the dry run, which is where the consequence is being read.
            if folder.depth > 1 {
                Text(ApStr.folderIncludesSubfolders)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rvm.previewByThisRule.isEmpty {
                Text(ApStr.nothingWouldHappen)
                    .font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
                    .padding(.vertical, 6)
            } else {
                rows(rvm.previewByThisRule, takenByAnother: false)
            }
            // **The files this rule will never get.** They are in the folder and
            // they match — and a rule above takes them first, which is the whole
            // of what the old dry run could not say. Drawn under a line that
            // names them as somebody else's rather than left out: a person
            // writing a narrower rule below a broad one needs to see where their
            // files are actually going, and the rule that takes each one is on
            // the row.
            if !rvm.previewByOtherRules.isEmpty {
                Text(ApStr.takenByAnotherRule)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                    .padding(.top, HelmSpace.s2)
                rows(rvm.previewByOtherRules, takenByAnother: true)
            }
        }
        // Re-asked as the rule is written, so the list answers the rule on
        // screen rather than the one before the last keystroke.
        .task(id: previewKey) { await rvm.runPreview(for: folder, rule: rule) }
    }

    /// One card of dry-run rows. Written once for both lists, so the row another
    /// rule takes is the same row with its rule named beside it rather than a
    /// second shape that can drift from this one.
    private func rows(_ list: [PreviewRow], takenByAnother: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(list) { row in
                HStack(spacing: 8) {
                    Text(row.name).lineLimit(1).truncationMode(.middle)
                        // Recessed, not hidden: these files are in the folder
                        // and something is going to happen to them.
                        .foregroundStyle(takenByAnother ? HelmText.quiet : Color.primary)
                    if takenByAnother {
                        Text(row.ruleName)
                            .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    Spacer()
                    // The action, and where it lands. Naming only the
                    // action left the reader to work out which
                    // subfolder "sort by kind" meant — the one thing
                    // the rule they just wrote does not tell them.
                    if let destination = row.destination {
                        Text(destination)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(HelmText.quiet)
                            .lineLimit(1).truncationMode(.middle)
                        Text("←").font(HelmText.rowDetail).foregroundStyle(HelmText.separator)
                    }
                    Text(RuleSummary.describe(row.action))
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                        .lineLimit(1)
                }
                .padding(.vertical, HelmSpace.s2)
                // One stop per file, not four. This is the list whose
                // whole purpose is making the consequence audible before
                // the switch is reachable, and read as loose fragments —
                // name, destination, arrow, action — it says least to
                // the reader who most depends on it.
                .accessibilityElement(children: .combine)
                if row.id != list.last?.id { Divider() }
            }
        }
        .helmCard()
    }

    private var previewKey: String { Self.previewKey(folder: folder, rule: rule) }

    /// What a change to the rule means for the preview. The name is not in it:
    /// renaming a rule cannot change what it would do; the folder is, since the
    /// list is of what is in it.
    static func previewKey(folder: WatchedFolder, rule: Rule) -> String {
        var key = folder.path + rule.match.rawValue
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
                // The task outlives the sheet on purpose. A preset's folder is
                // written and then swept, and the report belongs on the page
                // this is dismissing back to — not to a window that is waiting
                // for a sweep before it closes.
                Task { await rvm.save(rule, in: folder) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }
}
