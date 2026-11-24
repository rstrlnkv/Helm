import Foundation
import HelmRuntime

public struct FileSystemLeftovers: LeftoversFilePort {
    public init() {}

    public func isWritableDirectory(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    /// **Not `resolvingSymlinksInPath()`, which is `realpath` and gives up on a
    /// link whose target is not there**: it fails with `ENOENT` and Foundation hands
    /// back the spelling it was given, so `LeftoversScanner.isItsOwnPlace` would be
    /// told a planted link changes nothing. A link planted before its target exists
    /// makes the scan read `ENOENT` as an empty folder with no row of any kind.
    /// `PathCanonical.followingEveryLink` follows every link in the whole path, for
    /// a target that is not there as well as for one that is.
    public func resolvingSymlinks(_ url: URL) -> URL {
        URL(fileURLWithPath: PathCanonical.followingEveryLink(url.path))
    }

    public func contents(of url: URL) -> DirectoryListing.Contents {
        DirectoryListing.contents(of: url)
    }

    public func exists(_ path: String) -> Bool? { DirectoryListing.exists(atPath: path) }

    public func size(_ url: URL) -> Int { FileWeight.allocated(of: url) }
    /// Follows a link at the file itself: a LaunchAgent a dotfile manager keeps is a link, and a plist read as
    /// nothing would name a rival claimant of the same label by its file name, so the two-claimants rule would
    /// not see it. The target is bounded as any outside file is: no pipe, regular file, `PropertyListFile.byteCeiling`.
    public func readPlist(_ url: URL) -> PlistData? {
        guard let dict = PropertyListFile.dictionary(atPath: url.path, followingLink: true) else { return nil }
        return PlistData(dict)
    }
}

/// What is installed, by walking the applications directories.
///
/// **Not `RunningApps`, and not the Uninstaller's `WorkspaceAppLister`,
/// although all three are about applications.** `RunningApps` answers who is
/// *running* and is a main-thread-only AppKit read behind a snapshot;
/// `WorkspaceAppLister` answers the same question this does, over the same
/// directories (`PropertyListFile.installedBundleIDs`), and backs it with a
/// LaunchServices lookup.
///
/// **What this one does not have is that LaunchServices backstop.** The
/// shared walk covers a vendor folder like `/Applications/Adobe Photoshop 2026/`,
/// but not a helper nested inside another application's bundle, under
/// `Contents/`, which is in no applications directory at any depth
/// (`OrphanDetector.isOrphan`). Uninstaller pays for that lookup because it
/// offers bundles for deletion; this module trashes on the same kind of
/// judgement.
public struct WorkspaceInstalledApps: InstalledAppsPort {
    private let home: String

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.path
    }

    public func installedBundleIDs() -> Set<String> {
        PropertyListFile.installedBundleIDs(home: home)
    }
}

/// What macOS has loaded, and the one switch that changes it. Reading goes
/// through the shared tested parser.
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
    /// list: the exit status is the only thing that tells them apart, and without
    /// it a tool that failed says «nobody has switched anything off».
    public func disabledLabels() -> Set<String>? {
        disabledLabels(timeout: nil)
    }

    private func disabledLabels(timeout: TimeInterval?) -> Set<String>? {
        let result = HelmProcess.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"],
                                     timeout: timeout)
        guard result.status == 0 else { return nil }
        return LaunchctlDisabled.parse(result.output)
    }

    /// **How long one `launchctl` call may take: ten seconds.** `willDisable()` calls
    /// the port on the main thread through a synchronous contract
    /// (`HelmContract/ModuleEngine.swift`), and the reset's order leaves no room to
    /// hop off it, so this deadline is what bounds main.
    static let launchctlDeadline: TimeInterval = 10

    public func setDisabled(_ disabled: Bool, label: String) -> SwitchAnswer {
        // The label comes from a plist on disk, and `LaunchLabel` is the rule
        // about which of those launchctl can be asked about — the same one
        // `LeftoverActions.available` reads before offering the switch, so the
        // page and the port cannot come to disagree about a row.
        guard LaunchLabel.isSwitchable(label) else { return .refused }
        let domain = "gui/\(getuid())"
        let first = run([disabled ? "disable" : "enable", "\(domain)/\(label)"])
        let answer = Self.answer(status: first.status, disabled: disabled, label: label,
                                 listed: { disabledLabels(timeout: Self.launchctlDeadline) })
        // `disable` only stops it from loading next time; boot it out so the
        // switch means something now. Failure is fine — it may not be running.
        _ = run([disabled ? "bootout" : "kickstart", "\(domain)/\(label)"])
        return answer
    }

    /// The status of the first `launchctl` call as launchd's answer. `listed` is asked
    /// only for a non-zero status that is not a timeout.
    static func answer(status: Int32, disabled: Bool, label: String,
                       listed: () -> Set<String>?) -> SwitchAnswer {
        switch status {
        case 0:
            return .accepted
        case HelmProcess.timedOutStatus, -1:
            return .unknown
        default:
            // launchd may have applied it and still answered non-zero, so the
            // refusal is only believed when its own list agrees.
            guard let listed = listed() else { return .unknown }
            return listed.contains(label) == disabled ? .accepted : .refused
        }
    }

    private func run(_ arguments: [String]) -> HelmProcess.Result {
        HelmProcess.run("/bin/launchctl", arguments, timeout: Self.launchctlDeadline)
    }
}
