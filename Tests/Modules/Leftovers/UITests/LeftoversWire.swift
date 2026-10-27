import Foundation
import HelmContract
import HelmRuntime
import Module_Leftovers_Engine

/// The wire the pages in this target are drawn against: one scan reply and one
/// removal reply.
///
/// It is not in `HelmTestSupport` itself for the reason nothing module-shaped
/// can be: that target is below the modules and knows no `StaleItem`.
final class LeftoversWire: EngineTransport, @unchecked Sendable {

    private let items: [StaleItem]
    private let removal = LeftoversRemoval(removed: [], refused: [], freedBytes: 0)

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(items: [StaleItem]) {
        self.items = items
    }

    /// The enum, not the two literals this used to switch on. A fake that answers
    /// names of its own goes on answering after the module renames one — and what
    /// it answers then is `Data()`, which this codebase spells «the module could
    /// not answer».
    func send(_ command: EngineCommand) async throws -> Data {
        switch LeftoversCommand(rawValue: command.name) {
        case .scan: return (try? JSONEncoder().encode(items)) ?? Data()
        case .trash: return (try? JSONEncoder().encode(removal)) ?? Data()
        case .setDisabled, .none: return Data()
        }
    }
}
