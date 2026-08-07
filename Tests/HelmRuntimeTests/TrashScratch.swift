import Foundation
import XCTest

/// Files a test may really move to the Trash, and the way to get them back out.
///
/// **These tests trash for real.** `HelmTrash.remove` calls
/// `FileManager.trashItem`, which is the whole point of the type — so a file a
/// test hands it leaves the temporary directory and lands in `~/.Trash`, on the
/// machine of whoever ran `swift test`. Deleting the temporary directory
/// afterwards reclaims nothing: the file is no longer in it.
///
/// Two of these test files already carried a teardown that looked like the
/// cure and was not:
///
/// ```swift
/// // Trashed, so put it back out of the Trash rather than leaving it there.
/// addTeardownBlock { try? FileManager.default.removeItem(atPath: bundle) }
/// ```
///
/// `bundle` is the *source* path, which the move has already emptied. The
/// removal succeeds against nothing while the comment says the opposite, which
/// is the shape that let this run for months.
///
/// **The name is all the cleanup has to go on.** `HelmTrash` calls
/// `trashItem(at:resultingItemURL: nil)` and throws the destination away, and
/// the Trash cannot be listed without Full Disk Access — a test process does
/// not have it, and asking for the directory's contents fails with 257. So the
/// cleanup reconstructs `~/.Trash/<name>`, which is only safe if `<name>` is
/// one nobody else could own: the files here were called `one.txt`, `bundle`
/// and `one.bin`, and a cleanup removing `~/.Trash/bundle` would be deleting
/// somebody's own work. Every leaf carries a UUID for that reason, and the
/// UUID has to be in the **leaf** — putting it in the parent directory, which
/// is what these files did, tells the Trash nothing, because only the moved
/// item's own name survives the move.
extension XCTestCase {

    /// A temporary directory for files this test intends to trash, removed in
    /// teardown along with anything left in it.
    func trashScratchDirectory(_ label: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// `"one.bin"` → `"one-<uuid>.bin"`, keeping the extension so a test about
    /// bundles still makes something that reads as a bundle.
    func unownableLeaf(_ base: String) -> String {
        let url = URL(fileURLWithPath: base)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let unique = "\(stem)-\(UUID().uuidString)"
        return ext.isEmpty ? unique : "\(unique).\(ext)"
    }

    /// Takes `name` back out of the Trash when the test ends.
    ///
    /// Registered for the name a test is *about to* trash rather than after the
    /// fact, so a failure between the move and the end of the test still gets
    /// cleaned up.
    func reclaimFromTrash(_ name: String) {
        addTeardownBlock {
            let fm = FileManager.default
            let home = URL(fileURLWithPath: NSHomeDirectory())
            let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                     appropriateFor: home, create: false))
                ?? home.appendingPathComponent(".Trash")
            try? fm.removeItem(at: trash.appendingPathComponent(name))
        }
    }
}
