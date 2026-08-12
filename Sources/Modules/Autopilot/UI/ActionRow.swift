import AppKit
import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// The one thing the rule does, editable.
///
/// Same shape as `ConditionRow` and for the same reason: picking a different
/// action rebuilds it rather than editing a shared value, because a destination
/// path means nothing to a rename and a pattern means nothing to a move.
struct ActionRow: View {
    @Binding var action: RuleAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(ApStr.a11yAction, selection: kindBinding) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: HelmPickerWidth.fitting(Kind.allCases.map(\.label), minimum: 200))
                detail
                Spacer(minLength: 4)
            }
            if case .rename = action {
                Text(ApStr.patternHint)
                    .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    enum Kind: String, CaseIterable {
        case move, sort, rename, tag, trash

        var label: String {
            switch self {
            case .move: ApStr.actionMove
            case .sort: ApStr.actionSort
            case .rename: ApStr.actionRename
            case .tag: ApStr.actionTag
            case .trash: ApStr.actionTrash
            }
        }

        /// An action of this kind that does nothing yet.
        ///
        /// A move starts with nowhere to go because the destination only ever
        /// arrives through the panel — guessing one would be the module
        /// choosing where somebody's files go. What made that safe was said to
        /// be the runner's refusal, and a refusal repeated hourly is not safety:
        /// it is a log line and a history row per matching file, forever, for a
        /// rule that looks switched on. `Rule.canBeEnabled` is what makes it
        /// safe — the switch is unreachable until the panel has been used.
        var blank: RuleAction {
            switch self {
            case .move: .move(to: "")
            case .sort: .sortIntoSubfolder(.kind)
            case .rename: .rename(pattern: "{name}")
            case .tag: .addTag("")
            case .trash: .trash
            }
        }
    }

    private var kind: Kind {
        switch action {
        case .move: .move
        case .sortIntoSubfolder: .sort
        case .rename: .rename
        case .addTag: .tag
        case .trash: .trash
        }
    }

    private var kindBinding: Binding<Kind> {
        Binding(get: { kind }, set: { action = $0.blank })
    }

    @ViewBuilder private var detail: some View {
        switch action {
        case let .move(to: path):
            Text(path.isEmpty ? "—" : Redact.path(path))
                .font(HelmText.rowTitle).foregroundStyle(path.isEmpty ? HelmText.faint : .primary)
                .lineLimit(1).truncationMode(.middle)
            // The panel is the only way a destination gets in, so a rule cannot
            // name a folder nobody looked at.
            Button(ApStr.chooseDestination) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = ApStr.chooseDestination
                guard panel.runModal() == .OK, let url = panel.url else { return }
                action = .move(to: url.path)
            }
            .controlSize(.small)

        case let .sortIntoSubfolder(scheme):
            Picker(ApStr.a11yScheme, selection: Binding(get: { scheme },
                                                        set: { action = .sortIntoSubfolder($0) })) {
                Text(ApStr.schemeKind).tag(SortScheme.kind)
                Text(ApStr.schemeMonth).tag(SortScheme.month)
            }
            .labelsHidden()
            .frame(width: HelmPickerWidth.fitting([ApStr.schemeKind, ApStr.schemeMonth], minimum: 140))

        case let .rename(pattern):
            TextField("{name}", text: Binding(get: { pattern },
                                              set: { action = .rename(pattern: $0) }))
                .accessibilityLabel(ApStr.a11yPattern)

        case let .addTag(tag):
            TextField("", text: Binding(get: { tag }, set: { action = .addTag($0) }))
                .accessibilityLabel(ApStr.a11yTagValue)

        case .trash:
            EmptyView()
        }
    }
}
