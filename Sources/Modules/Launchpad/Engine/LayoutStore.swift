import Foundation
import HelmRuntime

/// What the layout file said. `.absent` is the ordinary first run and is silent; `.unreadable`
/// is a file that is there and will not decode (or is too large, or newer than this build knows).
enum LayoutRead: Equatable, Sendable {
    case absent
    case loaded(LaunchpadLayout)
    case unreadable
}

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
    let directory: URL
    /// Size and modification time of the bad file last warned about: one warning per distinct bad file.
    private var warnedAbout: String?

    init(directory: URL = HelmSupport.directory.appendingPathComponent("Launchpad", isDirectory: true)) {
        self.directory = directory
    }

    var fileURL: URL { directory.appendingPathComponent("layout.json") }
    private var asideURL: URL { directory.appendingPathComponent("layout.json.unreadable") }

    func load() -> LayoutRead {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return FileManager.default.fileExists(atPath: fileURL.path) ? unreadable() : .absent
        }
        defer { try? handle.close() }
        // One byte past the ceiling tells an oversize file without reading all of it.
        guard let data = try? handle.read(upToCount: LaunchpadLimits.maxFileBytes + 1),
              data.count <= LaunchpadLimits.maxFileBytes,
              let layout = try? JSONDecoder().decode(LaunchpadLayout.self, from: data) else { return unreadable() }
        return .loaded(layout)
    }

    private func unreadable() -> LayoutRead {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let stamp = "\(attributes?[.size] ?? 0) \((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        guard stamp != warnedAbout else { return .unreadable }
        warnedAbout = stamp
        HelmLog.shared.warn(LaunchpadEngine.moduleID,
                            "the saved arrangement could not be read — the apps show in alphabetical order until the next edit")
        return .unreadable
    }

    /// Moves a bad file aside, replacing an earlier one; a missing file is nothing to do.
    /// False when the move failed (logged): the bad file is still there and must not be overwritten.
    func moveUnreadableAside() -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            if FileManager.default.fileExists(atPath: asideURL.path) { try FileManager.default.removeItem(at: asideURL) }
            try FileManager.default.moveItem(at: fileURL, to: asideURL)
            return true
        } catch {
            HelmLog.shared.warn(LaunchpadEngine.moduleID,
                                "the unreadable arrangement could not be moved aside — it is kept and the edit is not saved")
            return false
        }
    }

    /// False when the write did not land; it is logged here and the caller still has its result.
    func save(_ layout: LaunchpadLayout) -> Bool {
        let ok = PrivateFile.writeMakingTheFolder(layout, at: fileURL)
        if !ok {
            HelmLog.shared.warn(LaunchpadEngine.moduleID,
                                "the arrangement could not be saved — the edit is only in the snapshot returned, the next read reloads the file")
        }
        return ok
    }
}
