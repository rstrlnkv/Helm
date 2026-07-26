import SwiftUI
import HelmContract
import HelmUI
import Module_Layout_Engine

@MainActor public final class LayoutViewModel: ObservableObject {
    @Published public private(set) var state = LayoutState(enabled: false, automatic: true,
                                                           suspended: false,
                                                           lastConversion: nil,
                                                           conversionsToday: 0)
    public let vm: ModuleViewModel

    private static var cached: LayoutViewModel?

    /// Keyed to the host view model: turning the module off and on builds a new
    /// one, and the old cache would be talking to a deallocated engine.
    public static func shared(vm: ModuleViewModel) -> LayoutViewModel {
        if let cached, cached.vm === vm { return cached }
        let created = LayoutViewModel(vm: vm)
        cached = created
        return created
    }

    private init(vm: ModuleViewModel) {
        self.vm = vm
        let events = vm.transport.events
        Task { [weak self] in
            for await event in events { await self?.handle(event) }
        }
    }

    private func handle(_ event: EngineEvent) {
        guard event.name == "layoutState",
              let decoded = try? JSONDecoder().decode(LayoutState.self, from: event.payload)
        else { return }
        state = decoded
    }

    public func undoLast() { vm.send("undoLastConversion") }
}
