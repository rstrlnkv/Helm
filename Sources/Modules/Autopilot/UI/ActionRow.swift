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
    /// The hint is always mounted and measured, so it grows and shrinks instead of popping.
    @State private var hintHeight: CGFloat?

    private var isRename: Bool {
        if case .rename = action { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: HelmSpace.s4) {
                Picker(ApStr.a11yAction, selection: kindBinding) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: HelmPickerWidth.fitting(Kind.allCases.map(\.label), minimum: AutopilotLayout.actionPicker),
                       alignment: .leading)
                detail
                Spacer(minLength: HelmSpace.s2)
            }
            // A cut: the swap of the details is not what moves; only the hint
            // below grows, on its own accordion.
            .transaction { $0.animation = nil }
            Text(ApStr.patternHint)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HelmSpace.s4)
                .helmAccordion(open: isRename, height: $hintHeight)
        }
    }

    enum Kind: String, CaseIterable {
        case move, sort, rename, tag, trash

        var label: String {
            switch self {
            case .move: ApStr.actionMove
            case .sort: ApStr.actionSort
            case .rename: HelmWord.rename
            case .tag: ApStr.actionTag
            case .trash: HelmWord.moveToTrash
            }
        }

        /// An action of this kind that does nothing yet.
        ///
        /// A move starts with nowhere to go: the destination arrives only through
        /// the panel, since a guess would be the module choosing where somebody's
        /// files go. `Rule.canBeEnabled` keeps the switch unreachable until then;
        /// the runner's refusal alone would be a log line and a history row per
        /// matching file, every hour.
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
        Binding(get: { kind }, set: { kind in withAnimation(HelmMotion.disclosure) { action = kind.blank } })
    }

    @ViewBuilder private var detail: some View {
        switch action {
        case let .move(to: path):
            Text(path.isEmpty ? "—" : Redact.path(path))
                .font(HelmText.rowTitle).foregroundStyle(path.isEmpty ? HelmText.faint : .primary)
                .lineLimit(1).truncationMode(.middle)
            // The panel is the only way a destination gets in, so a rule cannot
            // name a folder nobody looked at.
            Button(HelmWord.choose) {
                guard let url = FolderPicker.choose(prompt: HelmWord.choose, startingAt: nil,
                                                    canCreate: false, activate: false) else { return }
                action = .move(to: url.path)
            }
            .controlSize(.small)

        case let .sortIntoSubfolder(scheme):
            ShortPicker(name: ApStr.a11yScheme, selected: scheme,
                        options: [(.kind, ApStr.schemeKind), (.month, ApStr.schemeMonth)]) {
                action = .sortIntoSubfolder($0)
            }

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
