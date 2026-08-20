import Foundation
import HelmRuntime

public struct FileSystemLeftovers: LeftoversFilePort {
    public init() {}

    public func isWritableDirectory(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    public func resolvingSymlinks(_ url: URL) -> URL { url.resolvingSymlinksInPath() }

    public func contents(of url: URL) -> DirectoryListing.Contents {
        DirectoryListing.contents(of: url)
    }

    /// `stat`, not `FileManager.fileExists`, because the errno is the answer.
    ///
    /// `ENOENT` and `ENOTDIR` are «there is nothing there»; `ENAMETOOLONG` is a
    /// path no file can have. Everything else — `EACCES` above all, and the one
    /// this Mac gives for a file under a mode-000 parent — is «this process may
    /// not look», which is not a fact about the file.
    public func exists(_ path: String) -> Bool? {
        var info = stat()
        guard stat(path, &info) != 0 else { return true }
        switch errno {
        case ENOENT, ENOTDIR, ENAMETOOLONG: return false
        default: return nil
        }
    }

    public func size(_ url: URL) -> Int { FileWeight.allocated(of: url) }
    public func readPlist(_ url: URL) -> PlistData? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        return PlistData(dict)
    }
}

/// What is installed, by walking the applications directories.
///
/// **Not `RunningApps`, and not the Uninstaller's `WorkspaceAppLister`,
/// although all three are about applications.** `RunningApps` answers who is
/// *running* and is a main-thread-only AppKit read behind a snapshot;
/// `WorkspaceAppLister` answers the same question this does but over a
/// different set of directories, and backs it with a LaunchServices lookup.
/// Four questions, four answers, and the reason they are not one type is that
/// the answers differ.
///
/// **What this one does not have is that LaunchServices backstop.** The depth-2
/// walk below covers the case its own comment names — a vendor folder like
/// `/Applications/Adobe Photoshop 2026/` — but not the other case
/// `OrphanDetector.isOrphan` records: a helper nested inside another
/// application's bundle, under `Contents/`, which is in no applications
/// directory at any depth. Uninstaller pays for that lookup because it once
/// offered such bundles for deletion while their apps were installed and
/// running. This module trashes on the same kind of judgement.
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
            // One `Info.plist` per application, over four directories two levels
            // deep — a bulk read of file contents, so the pool goes inside the
            // iteration (ARCHITECTURE.md § Memory).
            autoreleasepool {
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
}

/// What macOS has loaded, and the one switch that changes it. Reading goes
/// through the shared tested parser — this file used to carry its own ad-hoc
/// line splitter.
///
/// One type for both protocols because both are `launchctl` and
/// `systemextensionsctl` on this machine; the split is about what a *caller*
/// may do, and the scanner is handed only the reading half.
public struct ActiveExtensions: LoadedItemsPort, LoginItemSwitchPort {
    public init() {}
    public func installedExtensions() -> [SystemExtensionInfo]? {
        SystemExtensionCLI.installedIfAnswered()
    }

    /// `nil` for a `launchctl` that did not answer, which is not an empty disabled
    /// list: the exit status is the only thing that tells them apart, and dropping
    /// it made a tool that failed say «nobody has switched anything off».
    public func disabledLabels() -> Set<String>? {
        let result = HelmProcess.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"])
        guard result.status == 0 else { return nil }
        return LaunchctlDisabled.parse(result.output)
    }

    public func setDisabled(_ disabled: Bool, label: String) {
        // The label comes from a plist on disk, and `LaunchLabel` is the rule
        // about which of those launchctl can be asked about — the same one
        // `LeftoverActions.available` reads before offering the switch, so the
        // page and the port cannot come to disagree about a row.
        guard LaunchLabel.isSwitchable(label) else { return }
        let domain = "gui/\(getuid())"
        _ = run([disabled ? "disable" : "enable", "\(domain)/\(label)"])
        // `disable` only stops it from loading next time; boot it out so the
        // switch means something now. Failure is fine — it may not be running.
        _ = run([disabled ? "bootout" : "kickstart", "\(domain)/\(label)"])
    }

    private func run(_ arguments: [String]) -> String {
        HelmProcess.run("/bin/launchctl", arguments).output
    }

}
