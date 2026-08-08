import Foundation
import HelmContract
import HelmRuntime

/// Finds login items, settings and plug-ins whose owner is gone, and trashes
/// the ones the user picks. Scanning walks many directories, so it runs off the
/// concurrency pool via `blocking`.
public final class LeftoversEngine: ModuleEngine, @unchecked Sendable {
    private let scanner: LeftoversScanner
    /// The one the scan uses. The removal gate used to fall back to the
    /// process's own home, so an engine built for a different one scanned
    /// there and would have refused to remove there — two homes in a type
    /// that was handed one.
    private let home: String
    private let files: LeftoversFilePort
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    /// The write half. The scan gets `loaded` and cannot reach this.
    private let switcher: LoginItemSwitchPort

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                files: LeftoversFilePort = FileSystemLeftovers(),
                apps: InstalledAppsPort = WorkspaceInstalledApps(),
                loaded: LoadedItemsPort = ActiveExtensions(),
                switcher: LoginItemSwitchPort = ActiveExtensions(),
                transport: LocalTransport = LocalTransport()) {
        self.files = files
        self.switcher = switcher
        self.home = home.path
        self.scanner = LeftoversScanner(home: home, files: files, apps: apps, extensions: loaded)
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    public func scan() async -> [StaleItem] {
        let items = await HelmActivity.phase("leftovers.scan") {
            await offTheCooperativePool { self.scanner.scan() }
        }
        HelmLog.shared.memory("leftovers.scan")
        // Counts and kinds, no names: a login item names an app, and an app
        // names a habit.
        HelmLog.shared.info("leftovers", "found \(items.count) stale item(s)")
        return items
    }

    public func trash(_ paths: [String]) async -> LeftoversRemoval {
        await offTheCooperativePool {
            // The view model already decides what may be offered; this is the
            // engine refusing to act on a path outside an app's own folders no
            // matter who asked. The gate stays here — `HelmTrash` takes paths
            // that have already passed one.
            let (allowed, refused) = RemovableScope.partition(Array(Set(paths)), home: self.home)
            // The loop this used to write by hand was the last of the four
            // `HelmTrash` was made for, and the only one that classified
            // nothing: `localizedDescription` reached the screen untranslated,
            // so a refusal by Full Disk Access read as "The operation couldn't
            // be completed" with the domain, the code and the path thrown away.
            HelmLog.shared.info("leftovers",
                                "trashing \(allowed.count), refused \(refused.count) out of scope")
            return HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "leftovers")
        }
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            guard let name = LeftoversCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .scan:
                return (try? JSONEncoder().encode(await self.scan())) ?? Data()
            case .setDisabled:
                guard let request = try? JSONDecoder().decode(LeftoversToggle.self,
                                                              from: command.payload)
                else { return Data() }
                await offTheCooperativePool { self.switcher.setDisabled(request.disabled,
                                                                        label: request.label) }
                return Data()
            case .trash:
                guard let paths = try? JSONDecoder().decode([String].self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.trash(paths))) ?? Data()
            }
        }
    }
}

/// What the trash command answers with — the same value `DiskRemoval` and
/// `DuplicateRemoval` name, and for the same reason.
///
/// It was a field-for-field copy: `failed` for `refused`, and a
/// `TrashFailureDetail` whose `message` carried `reason.rawValue` so that the
/// page could hand it back to `TrashReasonText.sentence`. Nothing in the type
/// said the string was a reason. The engine built the real result and unpacked
/// it into the copy line by line; both ends of this wire are in one build, and
/// the UI target imports this one, so one declaration serves both.
public typealias LeftoversRemoval = HelmTrash.Result
