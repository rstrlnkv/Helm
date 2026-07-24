import Foundation
import HelmContract
import HelmRuntime

/// Thin lifecycle engine: the island's real machinery is its window controller,
/// which lives in the UI layer (it IS a window). The descriptor injects
/// start/stop here so ModuleHost's enable/disable drives the island like any
/// other module. activate/deactivate arrive on the main thread (ModuleHost).
public final class IslandEngine: ModuleEngine, @unchecked Sendable {
    public let transport: EngineTransport
    private let onActivate: @MainActor () -> Void
    private let onDeactivate: @MainActor () -> Void

    public init(transport: LocalTransport = LocalTransport(),
                onActivate: @escaping @MainActor () -> Void,
                onDeactivate: @escaping @MainActor () -> Void) {
        self.transport = transport
        self.onActivate = onActivate
        self.onDeactivate = onDeactivate
    }

    public func activate() { MainActor.assumeIsolated { onActivate() } }
    public func deactivate() { MainActor.assumeIsolated { onDeactivate() } }
}
