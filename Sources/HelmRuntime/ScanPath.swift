import Foundation

/// Path arithmetic for the walk. Small, but it earned its own file: joining a
/// child onto "/" with a plain `+ "/" +` produces "//System", every descendant
/// inherits the doubled slash, and comparisons against absolute paths — the
/// firmlink skip set above all — stop matching.
enum ScanPath {
    static func child(of directory: String, name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
