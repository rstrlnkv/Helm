import Foundation
import HelmRuntime

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
        // Read once. `activeExtensionIdentifiers()` and `installedExtensions()`
        // each shelled out to systemextensionsctl and parsed the same list, so
        // a scan launched the tool twice for one answer.
        let extensionList = extensions.installedExtensions()
        let activeExtensions = Set(extensionList.map(\.identifier))
        let disabled = extensions.disabledLabels()
        var out: [StaleItem] = []
        out += launchItems(installed: installed, activeExtensions: activeExtensions,
                           disabled: disabled)
        out += preferences(installed: installed)
        out += plugins(installed: installed)
        out += systemExtensions(extensionList, installed: installed)
        return out.sorted { $0.identifier < $1.identifier }
    }

    // MARK: - System extensions

    /// Extensions are not files Helm can move: macOS removes them with the app
    /// that installed them, or from System Settings. They are listed so the
    /// user can see what loads and where it came from, never as something to
    /// tick — hence `.inUse`/`.protectedItem`, never `.orphaned`… except when
    /// the host app is gone, which is exactly what the user wants to know.
    private func systemExtensions(_ list: [SystemExtensionInfo],
                                  installed: Set<String>) -> [StaleItem] {
        list.map { info in
            let host = StaleItemRules.hostIdentifier(of: info.identifier)
            // The separator, as in UninstallerEngine and `owner(of:)`:
            // "com.acmecorp.vpn.ext" is not owned by an installed "com.acme",
            // and an empty id in the installed set is a prefix of everything —
            // it used to mark every extension on the machine as in use.
            let hostPresent = installed.contains {
                !$0.isEmpty && ($0 == host || info.identifier.hasPrefix($0 + "."))
            }
            return StaleItem(path: info.identifier, identifier: info.identifier,
                             kind: .systemExtension, sizeBytes: 0,
                             runAtLoad: info.enabled,
                             status: hostPresent ? .inUse : .orphaned)
        }
    }

    // MARK: - Launch agents and daemons

    private func launchItems(installed: Set<String>, activeExtensions: Set<String>,
                             disabled: Set<String>) -> [StaleItem] {
        let sources: [(URL, StaleKind)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .launchAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .launchDaemon),
        ]
        return sources.flatMap { directory, kind in
            files.children(of: directory)
                .filter { $0.pathExtension == "plist" }
                .map { url -> StaleItem in
                    let info = LaunchAgentReader.read(plist: files.readPlist(url)?.raw ?? [:], path: url.path)
                    let targetAlive = info.program.map(files.exists) ?? false
                    let status = self.status(identifier: info.identifier, path: url.path,
                                             installed: installed,
                                             inUse: targetAlive || activeExtensions.contains(info.identifier))
                    return StaleItem(path: url.path, identifier: info.identifier, kind: kind,
                                     sizeBytes: files.size(url),
                                     missingTarget: targetAlive ? nil : info.program,
                                     runAtLoad: info.runAtLoad, status: status,
                                     disabled: disabled.contains(info.identifier),
                                     writable: files.isWritable(url))
                }
        }
    }

    // MARK: - Preferences

    private func preferences(installed: Set<String>) -> [StaleItem] {
        let directory = home.appendingPathComponent("Library/Preferences")
        return files.children(of: directory)
            .filter { $0.pathExtension == "plist" }
            .map { url in
                let identifier = url.deletingPathExtension().lastPathComponent
                return StaleItem(path: url.path, identifier: identifier,
                                 kind: .preference, sizeBytes: files.size(url),
                                 status: status(identifier: identifier, path: url.path,
                                                installed: installed, inUse: false),
                                 // Asked, not assumed. The initialiser defaults
                                 // this to true, which offered a locked or
                                 // root-owned plist to "Select all".
                                 writable: files.isWritable(url))
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
                return StaleItem(path: url.path, identifier: identifier,
                                 kind: .plugin, sizeBytes: files.size(url),
                                 status: status(identifier: identifier, path: url.path,
                                                installed: installed, inUse: false),
                                 writable: files.isWritable(url))
            }
        }
    }

    /// Removable only when the safety rules allow it; otherwise the item is
    /// either in use (an owner exists, or its target is alive) or protected.
    private func status(identifier: String, path: String,
                        installed: Set<String>, inUse: Bool) -> ItemStatus {
        let ownerInstalled = owner(of: identifier, in: installed)
        if StaleItemRules.isRemovable(identifier: identifier, path: path,
                                      ownerInstalled: ownerInstalled || inUse,
                                      installedIDs: installed) {
            return .orphaned
        }
        return (ownerInstalled || inUse) ? .inUse : .protectedItem
    }

    /// An item belongs to an installed app when its id matches one, or extends
    /// one (helpers and extensions carry their app's id as a prefix).
    private func owner(of identifier: String, in installed: Set<String>) -> Bool {
        installed.contains(identifier)
            || installed.contains { identifier.hasPrefix($0 + ".") }
    }
}
