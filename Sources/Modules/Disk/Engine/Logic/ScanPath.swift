import Foundation

/// Path arithmetic for the walk. Small, but it earned its own file: joining a
/// child onto "/" with a plain `+ "/" +` produces "//System", every descendant
/// inherits the doubled slash, and comparisons against absolute paths — the
/// firmlink skip set above all — stop matching.
public enum ScanPath {
    public static func child(of directory: String, name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// A path the rest of the app can compare against: "//x" is the only form
    /// the walk can produce that needs collapsing.
    public static func normalize(_ path: String) -> String {
        path.hasPrefix("//") ? String(path.dropFirst()) : path
    }
}
