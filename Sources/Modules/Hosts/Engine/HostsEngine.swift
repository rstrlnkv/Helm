import Foundation
import HelmContract

/// The hosts file, the SSH config and the keys in `~/.ssh`.
public final class HostsEngine: ModuleEngine, @unchecked Sendable {
    /// This module's id, and the only place it is written down.
    ///
    /// It reaches disk as the `module.hosts.*` keys of a store and as the
    /// module named in the log. `HostsDescriptor.id` is built from this rather
    /// than repeating it — the direction the descriptors already carry their
    /// command enums — so the two spellings are one.
    public static let moduleID = "hosts"

    private let localTransport: LocalTransport
    public let transport: EngineTransport

    public init(transport: LocalTransport = LocalTransport()) {
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() {}

    private func wireTransport() {
        // No `[weak self]` while the handler needs nothing from the engine: a
        // capture that is only ever checked for nil reads as a lifetime rule
        // being observed when nothing is captured at all. It comes back with
        // the first arm that does work, and comes back weak.
        localTransport.setHandler { command in
            // A name this engine does not know is a refusal here, once, rather
            // than a `default` at the bottom of a switch nobody re-reads.
            guard let name = HostsCommand(rawValue: command.name) else { return Data() }
            switch name {
            case .load, .applyHosts, .restoreHosts, .settingsChanged:
                return Data()
            }
        }
    }
}
