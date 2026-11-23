import Foundation
import HelmRuntime

/// What the layout file said. `.absent` is the ordinary first run and is silent; `.unreadable`
/// is a file that is there and will not decode (or is too large, or newer than this build knows).
typealias LayoutRead = LaunchpadFileRead<LaunchpadLayout>

/// **`<Application Support>/Helm/Launchpad/layout.json`, private (0600 in a 0700 folder).**
///
/// Not the settings property list: the layout is a document, not a setting, and it is not
/// unattended work, so it is not sealed. Written only on a person's edit; a read never
/// writes. An unreadable file is moved aside once to `layout.json.unreadable` before the first
/// save, so a bad file is not silently overwritten and a read never touches it; when the move
/// fails the bad file stays, the save is not made, and the edit lives only in the snapshot
/// `apply` returns (`saved` false); the next read or apply reloads from the file.
/// Called only under the engine's lock.
final class LayoutStore: @unchecked Sendable {
    private let file: LaunchpadFile

    init(directory: URL = HelmSupport.directory.appendingPathComponent("Launchpad", isDirectory: true)) {
        file = LaunchpadFile(directory: directory, name: "layout.json")
    }

    var directory: URL { file.directory }
    var fileURL: URL { file.url }

    func load() -> LayoutRead {
        file.read(warning: "the saved arrangement could not be read — the apps show in alphabetical order until the next edit",
                  decode: { try? JSONDecoder().decode(LaunchpadLayout.self, from: $0) })
    }

    /// Moves a bad file aside, replacing an earlier one; a missing file is nothing to do.
    /// False when the move failed (logged): the bad file is still there and must not be overwritten.
    func moveUnreadableAside() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        return file.moveAside(warning: "the unreadable arrangement could not be moved aside — it is kept and the edit is not saved")
    }

    /// False when the write did not land; it is logged here and the caller still has its result.
    func save(_ layout: LaunchpadLayout) -> Bool {
        file.save(warning: "the arrangement could not be saved — the edit is only in the snapshot returned, the next read reloads the file") {
            return PrivateFile.writeMakingTheFolder(layout, at: $0)
        }
    }
}
