import Foundation

/// Which copy of identical content stays, and in what order the rest follow.
///
/// The module baskets every copy but the first in one click, so this is the
/// decision the whole screen rests on. It used to be alphabetical — not a
/// belief about anything, just the order the list happened to be sorted in for
/// display — which meant `~/Desktop/photo.jpg` beat
/// `~/Documents/Archive/2019/photo.jpg` and Helm offered to delete the filed
/// original while keeping the clutter.
///
/// Three things decide it, in this order:
///
/// 1. **The oldest date added.** The original is the one that has been there
///    longest; everything after it is a copy of it. This is the same date the
///    Finder calls "Date Added" and the same one Autopilot's rules read — not
///    the creation date, which a file carries with it when it is copied and
///    which would call the copy as old as the original.
/// 2. **The shallowest path.** Filesystems batch the date for files that
///    arrived together, so it ties often. A file four folders down was put
///    there by somebody; a file at the top of the folder is where things land.
/// 3. **Alphabetically**, so two copies that are alike in every way the rule
///    can see still come back in one fixed order and the row does not move
///    between scans.
public enum SurvivingCopy {

    /// The group's paths, the survivor first.
    public static func order(_ files: [FileFacts]) -> [String] {
        files.sorted(by: keeps).map(\.path)
    }

    private static func keeps(_ a: FileFacts, _ b: FileFacts) -> Bool {
        // A volume that does not record when a file was added reports nothing,
        // and nothing is not "the beginning of time": read that way it would
        // hand the decision to whichever copy the filesystem knows least about.
        // A copy we know something about outranks one we do not.
        switch (a.added, b.added) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        let depthA = depth(a.path), depthB = depth(b.path)
        if depthA != depthB { return depthA < depthB }
        return a.path < b.path
    }

    private static func depth(_ path: String) -> Int {
        path.split(separator: "/").count
    }
}
