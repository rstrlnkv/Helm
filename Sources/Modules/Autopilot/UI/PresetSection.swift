import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// Five rules somebody can have without writing one.
///
/// **A row is a button that shows, not a switch that does.** A switch here would
/// be the one gesture in this module that starts unattended work on somebody's
/// files without their having seen what it does to them — which is the whole
/// discipline the dry run exists for, one level up. So the row opens the
/// ordinary editor on an unsaved draft: everything is visible and editable, Done
/// is the ordinary save, and Cancel leaves no folder and no rule.
///
/// It appears in two places and disappears from both when there is nothing left
/// to offer: under the empty state, where it is the second answer to «what do I
/// do with this page», and above the history on a page that already has rules,
/// where it is a quiet list rather than a call to action.
struct PresetSection: View {
    let presets: [OfferedPreset]
    /// Drawn instead of the buttons when macOS is withholding the access. Every
    /// one of these folders reads as empty without it, so a dry run would show
    /// nothing and the rule would look like one that matches nothing.
    let diskAccess: PermissionState
    let open: (OfferedPreset) -> Void
    /// The home directory macOS's own folder names are measured against.
    var home: String = NSHomeDirectory()

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            Text(ApStr.presetsTitle).font(.headline)
            if diskAccess == .denied {
                // The sentence, and not a second `HelmPermissionNote`: the page
                // already draws one with the button in it, and two grants side
                // by side read as two different permissions.
                Text(ApStr.needsAccess)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: HelmSpace.s4) {
                    ForEach(presets) { row($0) }
                }
            }
        }
        .helmCard()
    }

    private func row(_ offer: OfferedPreset) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                Text(offer.draft.name).font(HelmText.rowTitle)
                // The rule saying itself. Nothing here describes a preset in
                // prose: a sentence written beside a rule is a second place the
                // rule lives, and the one that goes stale is always the prose.
                Text(RuleSummary.describe(offer.draft))
                    .font(.caption2).foregroundStyle(HelmText.faint)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button(ApStr.seePreset(in: offer.folderName(home: home))) { open(offer) }
                .controlSize(.small)
                .fixedSize()
        }
    }
}

extension OfferedPreset {
    /// The rule this preset is, under the name this language gives it.
    ///
    /// **One place, so the row and the rule cannot say different things.** The
    /// row draws this name and the editor saves this rule; built separately they
    /// would be two calls to keep in step, and the row is where somebody decides
    /// whether to press.
    var draft: Rule { preset.rule(named: ApStr.presetName(preset.kind), in: folder.path) }

    /// What the button calls the folder: macOS's own name for it, and the last
    /// path component for a folder macOS does not name — one somebody moved to
    /// another disk.
    func folderName(home: String = NSHomeDirectory()) -> String {
        SystemFolderNames.display(path: folder.path, home: home,
                                  language: AppLanguage.current.rawValue)
            ?? (folder.path as NSString).lastPathComponent
    }
}
