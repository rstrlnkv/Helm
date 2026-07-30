import Foundation

/// An application bundle found sitting in the Trash.
///
/// The Uninstaller could only ever clean up after an app removed *through Helm*.
/// Dragging one from `/Applications` to the Trash — which is how almost everyone
/// uninstalls on a Mac — left its support files, caches and preferences behind with
/// nothing to say so. The bundle in the Trash is intact, so its own `Info.plist`
/// answers the only question that matters for finding those files: which bundle id.
public struct TrashedApp: Equatable, Sendable {
    public let bundleID: String
    /// What the person will recognise, which is not always what the file is called.
    public let name: String
    public let path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Reading that bundle, minus the I/O.
///
/// The plist read stays with the caller so this is a pure decision: the fallback
/// chain for the name, and the refusals. Both matter more than they look. The id
/// decides which leftovers get claimed, and a wrong or empty one claims files
/// belonging to nobody; the name is the heading the window puts above a list of
/// things it is offering to delete, and an empty heading is worse than a filename.
public enum TrashedAppIdentity {

    /// nil when there is nothing worth offering — no bundle id, or a bundle whose
    /// `Info.plist` could not be read at all.
    ///
    /// `info` is untrusted: it is a file on disk that anything can write, so every
    /// value is checked for its type rather than force-cast. A number where a name
    /// belongs is not a name.
    public static func of(path: String, info: [String: Any]?) -> TrashedApp? {
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
/// The offer is unprompted — a window appears because the person dragged an app to
/// the Trash — so declining has to stick. A window that returns at the next launch
/// for an app they already said no to is the difference between a helpful app and
/// one people switch off. And it has to stop sticking when the app leaves the
/// Trash, or one decline means never being asked about that app again.
public enum TrashOfferMemory {

    /// In the order found, which the caller sets to the order the apps arrived —
    /// filtering must not reshuffle the groups the window draws.
    public static func toOffer(found: [TrashedApp], dismissed: Set<String>) -> [TrashedApp] {
        found.filter { !dismissed.contains($0.bundleID) }
    }

    /// The record, swept: an id whose app is no longer in the Trash is forgotten,
    /// because the decision was about a state that no longer exists. Restored or
    /// finally deleted, either way a later removal is a new question.
    ///
    /// Only forgets. Finding an app does not decline it.
    public static func stillDismissed(_ dismissed: Set<String>,
                                      found: [TrashedApp]) -> Set<String> {
        dismissed.intersection(found.map(\.bundleID))
    }
}
