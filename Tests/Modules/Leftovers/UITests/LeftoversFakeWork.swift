import Foundation
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// The engine's place for the pages in this target: one scan answer and an empty
/// removal, and what it was asked: the scans, the switches and the paths each
/// `trash` was handed.
///
/// It is not in `HelmTestSupport` itself for the reason nothing module-shaped
/// can be: that target is below the modules and knows no `StaleItem`.
final class LeftoversFakeWork: LeftoversWork, @unchecked Sendable {

    private let items: [StaleItem]
    private let removal = LeftoversRemoval(removed: [], refused: [], freedBytes: 0)
    private(set) var scans = 0
    private(set) var switches = 0
    private(set) var trashed: [[String]] = []

    init(items: [StaleItem]) {
        self.items = items
    }

    func scan() async -> [StaleItem] {
        scans += 1
        return items
    }

    func trash(_ paths: [String]) async -> LeftoversRemoval {
        trashed.append(paths)
        return removal
    }

    func setDisabled(_ request: LeftoversToggle) async { switches += 1 }
}
