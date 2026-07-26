import AppKit
import Foundation
import HelmRuntime

public struct FileSystemLeftovers: LeftoversFilePort {
    public func isWritable(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    public init() {}

    public func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .map { url.appendingPathComponent($0) } ?? []
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func size(_ url: URL) -> Int {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey])
        else { return 0 }
        if values.isDirectory == true {
            let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
            var total = 0
            while let item = items?.nextObject() as? URL {
                total += (try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize ?? 0
            }
            return total
        }
        return values.totalFileAllocatedSize ?? 0
    }

    public func readPlist(_ url: URL) -> PlistData? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return PlistData(dict)
    }

    public func trash(_ url: URL) -> TrashResult {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .success
        } catch {
            return TrashResult(succeeded: false, message: (error as NSError).localizedDescription)
        }
    }
}

public struct WorkspaceInstalledApps: InstalledAppsPort {
    private let searchDirs: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications"),
        ]
    }

    public func installedBundleIDs() -> Set<String> {
        var ids: Set<String> = []
        for dir in searchDirs { collect(dir, depth: 0, into: &ids) }
        return ids
    }

    /// Vendors nest their apps (/Applications/Adobe Photoshop 2026/…app), and
    /// missing those bundles made their settings look ownerless.
    private func collect(_ dir: URL, depth: Int, into ids: inout Set<String>) {
        guard depth <= 2 else { return }
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in items {
            if item.pathExtension == "app" {
                let info = item.appendingPathComponent("Contents/Info.plist")
                if let id = NSDictionary(contentsOf: info)?["CFBundleIdentifier"] as? String {
                    ids.insert(id)
                }
            } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collect(item, depth: depth + 1, into: &ids)
            }
        }
    }
}

/// Extensions currently activated, via the shared tested parser — this file
/// used to carry its own ad-hoc line splitter.
public struct ActiveExtensions: ExtensionsPort {
    public init() {}
    public func installedExtensions() -> [SystemExtensionInfo] {
        SystemExtensionCLI.installed()
    }

    public func disabledLabels() -> Set<String> {
        LaunchctlDisabled.parse(run(["print-disabled", "gui/\(getuid())"]))
    }

    public func setDisabled(_ disabled: Bool, label: String) {
        // The label comes from a plist on disk. A `/` in it re-points the
        // service target at the domain itself, and `launchctl bootout gui/<uid>`
        // ends the user's login session.
        guard !label.isEmpty, !label.contains("/") else { return }
        let domain = "gui/\(getuid())"
        _ = run([disabled ? "disable" : "enable", "\(domain)/\(label)"])
        // `disable` only stops it from loading next time; boot it out so the
        // switch means something now. Failure is fine — it may not be running.
        _ = run([disabled ? "bootout" : "kickstart", "\(domain)/\(label)"])
    }

    private func run(_ arguments: [String]) -> String {
        HelmProcess.run("/bin/launchctl", arguments).output
    }

    public func activeExtensionIdentifiers() -> Set<String> {
        Set(SystemExtensionCLI.installed().map(\.identifier))
    }
}
