import Foundation

/// An application bundle found sitting in the Trash.
///
/// Dragging an app to the Trash is how most people uninstall on a Mac, and it
/// leaves the app's files behind. The bundle in the Trash is intact, so its own
/// `Info.plist` names the bundle id those files are found by.
public struct TrashedApp: Equatable, Sendable {
    let bundleID: String
    /// What the person will recognise, which is not always what the file is called.
    let name: String
    let path: String
}

/// Reading that bundle, minus the I/O.
///
/// The plist read stays with the caller, so this is a pure decision: the
/// fallback chain for the name, and the refusals. The id decides which
/// leftovers are claimed, and the name heads a list offered for deletion, where
/// an empty heading is worse than a filename.
enum TrashedAppIdentity {

    /// nil when there is nothing worth offering — no bundle id, or a bundle whose
    /// `Info.plist` could not be read at all.
    ///
    /// `info` is untrusted: it is a file on disk that anything can write, so every
    /// value is checked for its type rather than force-cast. A number where a name
    /// belongs is not a name.
    static func of(path: String, info: [String: Any]?) -> TrashedApp? {
        guard let info, let bundleID = string(info["CFBundleIdentifier"]) else { return nil }
        let fileName = (path as NSString).lastPathComponent
        let fallback = fileName.hasSuffix(".app")
            ? String(fileName.dropLast(4))
            : fileName
        let name = string(info["CFBundleDisplayName"])
            ?? string(info["CFBundleName"])
            ?? fallback
        return TrashedApp(bundleID: bundleID, name: name, path: path)
    }

    /// A string that is actually a string and actually says something. Blank is
    /// treated as absent throughout: an empty bundle id would generate globs that
    /// match everything, and an empty name would head the window with nothing.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Which trashed apps to offer to clean up after, and which no to keep.
///
/// The offer is unprompted, so declining has to stick across launches, and stop
/// sticking when the app leaves the Trash, or one decline would mean never being
/// asked about that app again.
enum TrashOfferMemory {

    /// In the order found, which the caller sets to the order the apps arrived —
    /// filtering must not reshuffle the groups the window draws.
    static func toOffer(found: [TrashedApp], dismissed: Set<String>) -> [TrashedApp] {
        found.filter { !dismissed.contains($0.bundleID) }
    }

    /// The record, swept: an id whose app is no longer in the Trash (restored or
    /// deleted) is forgotten, and a later removal is a new question.
    ///
    /// Only forgets. Finding an app does not decline it.
    static func stillDismissed(_ dismissed: Set<String>,
                               found: [TrashedApp]) -> Set<String> {
        dismissed.intersection(found.map(\.bundleID))
    }
}
