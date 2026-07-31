import Foundation
import HelmRuntime

/// Why a path refused to move, in a sentence.
///
/// These lived inside the Uninstaller, which is the module that had them
/// first — so Disk and Duplicates, which refuse for exactly the same reasons,
/// said nothing but a number. A reason phrased two ways in two modules is two
/// things to the person reading it, so there is one table.
public enum TrashReasonText {
    public static func sentence(_ raw: String) -> String {
        switch raw {
        case "needsFullDiskAccess":
            return L("Helm needs Full Disk Access to move this.")
        case "activeSystemExtension":
            return L("Its system extension is still active — turn it off in Login Items & Extensions.")
        case TrashFailure.Reason.outOfScope.rawValue:
            return L("Outside the folders Helm may clean — Helm did not touch it.")
        case TrashFailure.Reason.readOnlyVolume.rawValue:
            return L("The disk this is on is read-only. Eject it and unlock it, or copy what you need elsewhere.")
        case TrashFailure.Reason.diskFull.rawValue:
            return L("The disk is full. Moving to the Trash needs room, because the Trash is a folder on the same disk — empty it and try again.")
        case "noPermission":
            return L("The file is locked, or you are not its owner. Open Get Info in the Finder to unlock it or change its permissions.")
        default:
            // The one case that cannot name a cause, because `TrashFailure`
            // only classifies the codes it has seen. It can still name a step.
            return L("macOS would not move this. Show it in the Finder and try from there — the Finder says more about why.")
        }
    }
}
