import Foundation
import HelmContract
import HelmRuntime

/// Finds login items, settings and plug-ins whose owner is gone, and trashes
/// the ones the user picks. Scanning walks many directories, so it runs off the
/// concurrency pool via `blocking`.
public final class LeftoversEngine: ModuleEngine, @unchecked Sendable {
    private let scanner: LeftoversScanner
    private let files: LeftoversFilePort
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    private let extensions: ExtensionsPort

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                files: LeftoversFilePort = FileSystemLeftovers(),
                apps: InstalledAppsPort = WorkspaceInstalledApps(),
                extensions: ExtensionsPort = ActiveExtensions(),
                transport: LocalTransport = LocalTransport()) {
        self.files = files
        self.extensions = extensions
        self.scanner = LeftoversScanner(home: home, files: files, apps: apps, extensions: extensions)
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    public func scan() async -> [StaleItem] {
        await blocking { self.scanner.scan() }
    }

    public func trash(_ paths: [String]) async -> LeftoversRemoval {
        await blocking {
            var removed: [String] = [], failed: [TrashFailureDetail] = []
            var freed = 0
            // The view model already decides what may be offered; this is the
            // engine refusing to act on a path outside an app's own folders no
            // matter who asked. Refusals are reported, never dropped quietly.
            let (allowed, refused) = RemovableScope.partition(Array(Set(paths)))
            for path in refused {
                HelmLog.shared.warn("leftovers", "refused out-of-scope path")
                failed.append(TrashFailureDetail(path: path,
                                                 message: TrashFailure.Reason.outOfScope.rawValue))
            }
            for path in allowed {
                let url = URL(fileURLWithPath: path)
                let size = self.files.size(url)
                let result = self.files.trash(url)
                if result.succeeded {
                    removed.append(path); freed += size
                } else {
                    failed.append(TrashFailureDetail(path: path, message: result.message))
                }
            }
            HelmLog.shared.info("leftovers", "removed \(removed.count), failed \(failed.count)")
            return LeftoversRemoval(removed: removed, failed: failed, freedBytes: freed)
        }
    }

    private func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: work()) }
        }
    }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "scan":
                return (try? JSONEncoder().encode(await self.scan())) ?? Data()
            case "setDisabled":
                guard let request = try? JSONDecoder().decode(LeftoversToggle.self,
                                                              from: command.payload)
                else { return Data() }
                await self.blocking { self.extensions.setDisabled(request.disabled,
                                                                  label: request.label) }
                return Data()
            case "trash":
                guard let paths = try? JSONDecoder().decode([String].self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.trash(paths))) ?? Data()
            default:
                return Data()
            }
        }
    }
}

public struct TrashFailureDetail: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let message: String
    public init(path: String, message: String) {
        self.path = path; self.message = message
    }
}

public struct LeftoversRemoval: Codable, Equatable, Sendable {
    public let removed: [String]
    public let failed: [TrashFailureDetail]
    public let freedBytes: Int
    public init(removed: [String], failed: [TrashFailureDetail], freedBytes: Int) {
        self.removed = removed; self.failed = failed; self.freedBytes = freedBytes
    }
}
