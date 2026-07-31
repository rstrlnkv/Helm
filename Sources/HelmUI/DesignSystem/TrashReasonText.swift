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
        case "noPermission":
            return L("The file is locked, or you are not its owner. Open Get Info in the Finder to unlock it or change its permissions.")
        default:
            return L("macOS refused to move this item.")
        }
    }
}
