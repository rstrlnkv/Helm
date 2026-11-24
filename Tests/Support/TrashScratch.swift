import Foundation
import XCTest

/// Files a test may really move to the Trash, and the way to get them back out.
///
/// These tests trash for real: `HelmTrash.remove` calls
/// `FileManager.trashItem`, so a file lands in `~/.Trash` on the machine of
/// whoever ran `swift test`. Deleting the source path afterwards reclaims
/// nothing, because the move has already emptied it.
///
/// The name is all the cleanup has to go on: `HelmTrash` throws the
/// destination away, and a test process cannot list the Trash without Full
/// Disk Access. So the cleanup reconstructs `~/.Trash/<name>`, safe only if
/// `<name>` is one nobody else could own. The UUID goes in the leaf, because
/// only the moved item's own name survives the move.
public extension XCTestCase {

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
