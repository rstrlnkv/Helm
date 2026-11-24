import Foundation

/// Path arithmetic for the walk. Joining a child onto "/" with a plain
/// `+ "/" +` produces "//System", every descendant inherits the doubled slash,
/// and comparisons against absolute paths (the firmlink skip set above all)
/// stop matching.
///
/// It also keeps **one spelling** coming out of a walk: `FileManager.enumerator`
/// given `/var/folders/…` hands back `/private/var/folders/…`, and a gate
/// comparing against the approved root then fails open. A path composed from
/// the root the walk was handed cannot do that, which is why `BulkWalk`
/// composes rather than asks.
public enum ScanPath {
    public static func child(of directory: String, name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }
}
