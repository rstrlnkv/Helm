import Foundation

/// Path arithmetic for the walk. Small, but it earned its own file: joining a
/// child onto "/" with a plain `+ "/" +` produces "//System", every descendant
/// inherits the doubled slash, and comparisons against absolute paths — the
/// firmlink skip set above all — stop matching.
///
/// It is also what keeps **one spelling** coming out of a walk. Measured
/// 2026-08-20: `FileManager.enumerator` given a root spelled `/var/folders/…`
/// hands back children spelled `/private/var/folders/…`, so a gate comparing a
/// walk's paths against the root it approved matches nothing and fails open
/// without a word. A path composed from the root the walk was handed cannot do
/// that — which is why `BulkWalk` composes rather than asks, and why this sits
/// beside it rather than inside the one module that used to own it.
public enum ScanPath {
    public static func child(of directory: String, name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
