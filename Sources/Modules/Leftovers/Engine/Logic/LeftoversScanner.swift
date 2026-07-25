import Foundation

/// Walks the places login items and settings accumulate, and reports only what
/// is safely removable: the owner is gone, nothing Apple's, nothing in a
/// system location. Filesystem access goes through ports so the whole walk is
/// testable.
public struct LeftoversScanner: Sendable {
    private let home: URL
    private let files: LeftoversFilePort
    private let apps: InstalledAppsPort
    private let extensions: ExtensionsPort

    public init(home: URL, files: LeftoversFilePort,
                apps: InstalledAppsPort, extensions: ExtensionsPort) {
        self.home = home
        self.files = files
        self.apps = apps
        self.extensions = extensions
    }

    public func scan() -> [StaleItem] {
        let installed = apps.installedBundleIDs()
        let activeExtensions = extensions.activeExtensionIdentifiers()
        var out: [StaleItem] = []
        out += launchItems(installed: installed, activeExtensions: activeExtensions)
        out += preferences(installed: installed)
        out += plugins(installed: installed)
        return out.sorted { $0.identifier < $1.identifier }
    }

    // MARK: - Launch agents and daemons

    private func launchItems(installed: Set<String>, activeExtensions: Set<String>) -> [StaleItem] {
        let sources: [(URL, StaleKind)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .launchDaemon),
        ]
        return sources.flatMap { directory, kind in
            files.children(of: directory)
                .filter { $0.pathExtension == "plist" }
                .compactMap { url -> StaleItem? in
                    let info = LaunchAgentReader.read(plist: files.readPlist(url)?.raw ?? [:], path: url.path)
                    // Still activated as a system extension → in use.
                    guard !activeExtensions.contains(info.identifier) else { return nil }
                    // A job whose executable is still there is doing its work.
                    if let program = info.program, files.exists(program) { return nil }
                    guard StaleItemRules.isRemovable(identifier: info.identifier, path: url.path,
                                                     ownerInstalled: owner(of: info.identifier,
                                                                           in: installed),
                                                     installedIDs: installed) else { return nil }
                    return StaleItem(path: url.path, identifier: info.identifier, kind: kind,
                                     sizeBytes: files.size(url),
                                     missingTarget: info.program, runAtLoad: info.runAtLoad)
                }
        }
    }

    // MARK: - Preferences

    private func preferences(installed: Set<String>) -> [StaleItem] {
        let directory = home.appendingPathComponent("Library/Preferences")
        return files.children(of: directory)
            .filter { $0.pathExtension == "plist" }
            .compactMap { url in
                let identifier = url.deletingPathExtension().lastPathComponent
                guard StaleItemRules.isRemovable(identifier: identifier, path: url.path,
                                                 ownerInstalled: owner(of: identifier, in: installed),
                                                 installedIDs: installed) else { return nil }
                return StaleItem(path: url.path, identifier: identifier,
                                 kind: .preference, sizeBytes: files.size(url))
            }
    }

    // MARK: - Plug-ins

    private func plugins(installed: Set<String>) -> [StaleItem] {
        let directories = [
            "Library/QuickLook", "Library/PreferencePanes",
            "Library/Internet Plug-Ins", "Library/Audio/Plug-Ins/Components",
        ].map { home.appendingPathComponent($0) }

        return directories.flatMap { directory in
            files.children(of: directory).compactMap { url -> StaleItem? in
                let info = files.readPlist(url.appendingPathComponent("Contents/Info.plist"))
                guard let identifier = info?.raw["CFBundleIdentifier"] as? String else { return nil }
                guard StaleItemRules.isRemovable(identifier: identifier, path: url.path,
                                                 ownerInstalled: owner(of: identifier, in: installed),
                                                 installedIDs: installed) else { return nil }
                return StaleItem(path: url.path, identifier: identifier,
                                 kind: .plugin, sizeBytes: files.size(url))
            }
        }
    }

    /// An item belongs to an installed app when its id matches one, or extends
    /// one (helpers and extensions carry their app's id as a prefix).
    private func owner(of identifier: String, in installed: Set<String>) -> Bool {
        installed.contains(identifier)
            || installed.contains { identifier.hasPrefix($0 + ".") }
    }
}
