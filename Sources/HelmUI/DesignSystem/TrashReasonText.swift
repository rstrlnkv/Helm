import Foundation
import HelmRuntime

/// Why a path refused to move, in a sentence.
///
/// One table for every module that removes, because a reason phrased two ways
/// in two modules is two things to the person reading it.
public enum TrashReasonText {
    /// The verb of the caller's own refresh control, where a sentence ends by
    /// naming one.
    ///
    /// A sentence that names a control must name the one on the screen:
    /// Duplicates' says «Search again», the others «Scan again». Each variant
    /// is a full key with its own eight translations, because a verb
    /// interpolated into eight grammars would be right in one of them.
    public enum Refresh {
        case scan, search
    }

    public static func sentence(_ raw: String, refresh: Refresh = .scan) -> String {
        switch raw {
        case "needsFullDiskAccess":
            return L(.needsFullDiskAccess)
        case "activeSystemExtension":
            return L(.activeSystemExtension)
        case TrashFailure.Reason.outOfScope.rawValue:
            return L(.outOfScope)
        case TrashFailure.Reason.changedSinceScan.rawValue:
            return changed(refresh)
        case TrashFailure.Reason.missing.rawValue:
            return gone(refresh)
        case TrashFailure.Reason.unreadable.rawValue:
            // Not `changedSinceScan`'s sentence, which says the file is not
            // where Helm found it. Only the duplicate verification raises this,
            // reading both sides of a pair, so the sentence may name the copy
            // that stays. No refresh verb: the step is the access, not the list.
            return L(.unreadable)
        case TrashFailure.Reason.readOnlyVolume.rawValue:
            return L(.readOnlyVolume)
        case TrashFailure.Reason.diskFull.rawValue:
            return L(.diskFull)
        case "noPermission":
            return L(.noPermission)
        default:
            // The one case that cannot name a cause, because `TrashFailure`
            // only classifies the codes it has seen. It can still name a step.
            return L(.unknownReason)
        }
    }

    /// Names what changed rather than apologising for the refusal: the person
    /// chose this file on the strength of a scan, and the scan is what stopped
    /// being true.
    ///
    /// Module-neutral, because the refusal is: `HelmTrash` raises it for every
    /// module when an ancestor of the path changed since the gate, and nothing
    /// re-checks what made the file a candidate. The closing verb is the
    /// caller's (`Refresh`).
    private static func changed(_ refresh: Refresh) -> String {
        switch refresh {
        case .scan:
            return L(.changedSinceScan)
        case .search:
            return L(.changedSinceSearch)
        }
    }

    /// Not the neighbouring sentence: `changedSinceScan` is a file that is
    /// somewhere else, this is a file that is nowhere. It names the list rather
    /// than the file, because the list is what stopped being true.
    private static func gone(_ refresh: Refresh) -> String {
        switch refresh {
        case .scan:
            return L(.missingAfterScan)
        case .search:
            return L(.missingAfterSearch)
        }
    }
}
