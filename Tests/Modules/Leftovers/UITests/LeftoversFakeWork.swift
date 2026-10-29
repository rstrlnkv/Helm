import Foundation
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The engine's place for the pages in this target: one scan answer and an empty
/// removal.
///
/// It is not in `HelmTestSupport` itself for the reason nothing module-shaped
/// can be: that target is below the modules and knows no `StaleItem`.
final class LeftoversFakeWork: LeftoversWork, @unchecked Sendable {

    private let items: [StaleItem]
    private let removal = LeftoversRemoval(removed: [], refused: [], freedBytes: 0)

    init(items: [StaleItem]) {
        self.items = items
    }

    func scan() async -> [StaleItem] { items }

    func trash(_ paths: [String]) async -> LeftoversRemoval { removal }

    func setDisabled(_ request: LeftoversToggle) async {}
}
