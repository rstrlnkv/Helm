import HelmRuntime
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// Five rules somebody can have without writing one, as a menu.
///
/// **An item is a button that shows, not a switch that does.** A switch here
/// would be the one gesture in this module that starts unattended work on
/// somebody's files without their having seen what it does to them — which is
/// the whole discipline the dry run exists for, one level up. So an item opens
/// the ordinary editor on an unsaved draft: everything is visible and editable,
/// Done is the ordinary save, and Cancel leaves no folder and no rule.
///
/// **Grouped by folder, because the item is where a folder is first named.** A
/// preset's folder is `FileManager`'s answer rather than a panel's, so the menu
/// says which one in a heading and the editor repeats it on its first line.
/// Groups keep the order the folders first appear in, so the order the engine
/// offers them in is kept inside each.
///
/// Where it is drawn is the page's business (`AutopilotSettingsPage.presets`):
/// beside «Add folder…» and nowhere else, and not at all once there is a rule
/// or nothing left to offer.
struct PresetSection: View {
    let presets: [OfferedPreset]
    /// Disabled while macOS is withholding the access. Every one of these
    /// folders reads as empty without it, so a dry run would show nothing and the
    /// rule would look like one that matches nothing; the page's own
    /// `HelmPermissionNote` already says why, and a second sentence beside the
    /// button would read as a second permission.
    let diskAccess: PermissionState
    let open: (OfferedPreset) -> Void
    /// The home directory macOS's own folder names are measured against.
    var home: String = NSHomeDirectory()

    var body: some View {
        Menu(ApStr.welcomeOffer) {
            ForEach(groups, id: \.path) { group in
                Section(group.name) {
                    ForEach(group.offers) { offer in
                        Button(offer.draft.name) { open(offer) }
                    }
                }
            }
        }
        .fixedSize()
        .disabled(diskAccess == .denied)
    }

    /// The offers by folder, in the order each folder first appears.
    private var groups: [(path: String, name: String, offers: [OfferedPreset])] {
        var paths: [String] = []
        for offer in presets where !paths.contains(offer.folder.path) { paths.append(offer.folder.path) }
        return paths.map { path in
            let offers = presets.filter { $0.folder.path == path }
            return (path, offers[0].folderName(home: home), offers)
        }
    }
}

extension OfferedPreset {
    /// The rule this preset is, under the name this language gives it.
    ///
    /// **One place, so the item and the rule cannot say different things.** The
    /// menu draws this name and the editor saves this rule; built separately they
    /// would be two calls to keep in step, and the item is where somebody decides
    /// whether to press.
    var draft: Rule { preset.rule(named: ApStr.presetName(preset.kind), in: folder.path) }

    /// What the menu calls the folder: macOS's own name for it, and the last
    /// path component for a folder macOS does not name — one somebody moved to
    /// another disk.
    func folderName(home: String = NSHomeDirectory()) -> String {
        SystemFolderNames.displayOrOwn(path: folder.path, home: home,
                                       language: AppLanguage.current.rawValue)
    }
}
