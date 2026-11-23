import Foundation
import HelmRuntime

/// What a Launchpad file said: `.absent` is the ordinary first run and is silent; `.unreadable` is a file that is there and
/// will not decode (or is too large, or newer than this build knows).
enum LaunchpadFileRead<Value> {
    case absent
    case loaded(Value)
    case unreadable
}

extension LaunchpadFileRead: Equatable where Value: Equatable {}
extension LaunchpadFileRead: Sendable where Value: Sendable {}

/// **The file mechanics `LayoutStore` and `LaunchCountStore` share**: the bounded read, the one warning per distinct bad
/// file, the move aside to `<name>.unreadable`, the private save. Holds no lock: `LaunchCountStore` takes its own, `LayoutStore` runs under the engine's.
final class LaunchpadFile: @unchecked Sendable {
    let directory: URL
    let name: String
    /// Size and modification time of the bad file last warned about: one warning per distinct bad file.
    private var warnedAbout: String?

    init(directory: URL, name: String) {
        self.directory = directory
        self.name = name
    }

    var url: URL { directory.appendingPathComponent(name) }
    private var asideURL: URL { directory.appendingPathComponent(name + ".unreadable") }

    /// Absent when there is no file; unreadable (warned once per distinct file with `warning`) when it is there and
    /// will not read, is over the ceiling, or `decode` refuses it.
    func read<Value>(warning: String, decode: (Data) -> Value?) -> LaunchpadFileRead<Value> {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? unreadable(warning) : .absent
        }
        defer { try? handle.close() }
        // One byte past the ceiling tells an oversize file without reading all of it.
        guard let data = try? handle.read(upToCount: LaunchpadLimits.maxFileBytes + 1),
              data.count <= LaunchpadLimits.maxFileBytes,
              let value = decode(data) else { return unreadable(warning) }
        return .loaded(value)
    }

    private func unreadable<Value>(_ warning: String) -> LaunchpadFileRead<Value> {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = "\(attributes?[.size] ?? 0) \((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
        if stamp != warnedAbout {
            warnedAbout = stamp
            HelmLog.shared.warn(LaunchpadEngine.moduleID, warning)
        }
        return .unreadable
    }

    /// Moves the file aside, replacing an earlier aside. False when the move failed (logged with `warning`).
    func moveAside(warning: String) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: asideURL.path) { try FileManager.default.removeItem(at: asideURL) }
            try FileManager.default.moveItem(at: url, to: asideURL)
            return true
        } catch {
            HelmLog.shared.warn(LaunchpadEngine.moduleID, warning)
            return false
        }
    }

    func removeAside() { try? FileManager.default.removeItem(at: asideURL) }

    /// `write` is the `PrivateFile.writeMakingTheFolder` call for the value (JSON or bytes); false is logged with `warning`.
    func save(warning: String, _ write: (URL) -> Bool) -> Bool {
        let ok = write(url)
        if !ok { HelmLog.shared.warn(LaunchpadEngine.moduleID, warning) }
        return ok
    }
}
