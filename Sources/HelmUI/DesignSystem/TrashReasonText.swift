import Foundation
import HelmRuntime

/// Why a path refused to move, in a sentence.
///
/// These lived inside the Uninstaller, which is the module that had them
/// first — so Disk and Duplicates, which refuse for exactly the same reasons,
/// said nothing but a number. A reason phrased two ways in two modules is two
/// things to the person reading it, so there is one table.
public enum TrashReasonText {
    /// The verb of the caller's own refresh control, where a sentence ends by
    /// naming one.
    ///
    /// «Scan again to see where it is now» was said on four screens, and one of
    /// them has no such button: Duplicates' control says «Search again». A
    /// record that names a control is checked against the app's real string, so
    /// the caller says which word its page carries — and each variant is a full
    /// key with its own eight translations, because a verb interpolated into
    /// eight grammars would be right in one of them.
    public enum Refresh {
        case scan, search
    }

    public static func sentence(_ raw: String, refresh: Refresh = .scan) -> String {
        switch raw {
        case "needsFullDiskAccess":
            return L("Helm needs Full Disk Access to move this.")
        case "activeSystemExtension":
            return L("Its system extension is still active — turn it off in Login Items & Extensions.")
        case TrashFailure.Reason.outOfScope.rawValue:
            return L("Outside the folders Helm may clean — Helm did not touch it.")
        case TrashFailure.Reason.changedSinceScan.rawValue:
            return changed(refresh)
        case TrashFailure.Reason.missing.rawValue:
            return gone(refresh)
        case TrashFailure.Reason.unreadable.rawValue:
            // Not `changedSinceScan`'s sentence: that one says «it is not where
            // Helm found it» about a file that may be exactly there. Only the
            // duplicate verification raises this — it reads both sides of the
            // pair, and one failure on either lands here — so the sentence may
            // name the copy that stays. No refresh verb: the step is the
            // access, not the list.
            return L("Helm could not read it, or the copy that stays, so nothing was moved. Check that both can be opened and try again.")
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

    /// Names what changed rather than apologising for the refusal: the person
    /// chose this file on the strength of a scan, and the scan is what stopped
    /// being true.
    ///
    /// **Module-neutral, because the refusal is.** `HelmTrash` raises this for
    /// every module — an ancestor of the path changed since the gate — and the
    /// sentence said "it is no longer a duplicate", which is Duplicates' claim
    /// and was untrue even there: nothing re-checks duplication. Drawn over a
    /// launch agent it was simply false.
    ///
    /// The closing verb is the caller's: three pages draw a «Scan again»
    /// button, Duplicates' says «Search again», and the sentence has to name
    /// the control that is actually on the screen.
    private static func changed(_ refresh: Refresh) -> String {
        switch refresh {
        case .scan:
            return L("This is not where Helm found it, so nothing was moved. Scan again to see where it is now.")
        case .search:
            return L("This is not where Helm found it, so nothing was moved. Search again to see where it is now.")
        }
    }

    /// Not the neighbouring sentence, and the difference is the whole point:
    /// `changedSinceScan` is a file that is somewhere else, this is a file that
    /// is nowhere. It names the list rather than the file, because the list is
    /// what was wrong — the person picked this from a measurement that has
    /// since stopped being true.
    private static func gone(_ refresh: Refresh) -> String {
        switch refresh {
        case .scan:
            return L("This is not there any more, so nothing was moved. Scan again to see what is left.")
        case .search:
            return L("This is not there any more, so nothing was moved. Search again to see what is left.")
        }
    }
}
