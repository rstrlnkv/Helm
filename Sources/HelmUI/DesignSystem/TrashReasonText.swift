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
            return L("The app has an active system extension. Turn it off first.")
        case TrashFailure.Reason.outOfScope.rawValue:
            return L("Outside the folders Helm may clean — nothing was attempted.")
        case "noPermission":
            return L("No permission to move this item — it may be locked or in use.")
        default:
            return L("macOS refused to move this item.")
        }
    }
}
