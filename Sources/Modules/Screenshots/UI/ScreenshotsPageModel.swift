import SwiftUI
import HelmContract
import HelmUI
import Module_Screenshots_Engine

/// What the settings page knows about the world outside Helm: the folder and
/// the system's boxes, as the engine last read them.
@MainActor public final class ScreenshotsPageModel: ObservableObject {
    @Published public private(set) var state = ScreenshotsState.unread
    let vm: ModuleViewModel
    private var eventsTask: Task<Void, Never>?

    private static var cached: ScreenshotsPageModel?

    /// Keyed to the host view model: switching the module off and on builds a new
    /// one, and the old cache would be listening to a transport nothing will
    /// ever emit into again.
    public static func shared(vm: ModuleViewModel) -> ScreenshotsPageModel {
        if let cached, cached.vm === vm { return cached }
        let created = ScreenshotsPageModel(vm: vm)
        cached = created
        ModuleUICache.dropWhenDisabled(ScreenshotsDescriptor.id.rawValue) { cached = nil }
        return created
    }

    private init(vm: ModuleViewModel) {
        self.vm = vm
        let events = vm.transport.events
        eventsTask = Task { [weak self] in
            for await event in events {
                guard let self else { break }
                self.handle(event)
            }
        }
    }

    /// Ends the event loop, which unregisters the transport subscriber.
    deinit { eventsTask?.cancel() }

    private func handle(_ event: EngineEvent) {
        guard ScreenshotsEvent(rawValue: event.name) == .screenshotsState,
              let decoded = try? JSONDecoder().decode(ScreenshotsState.self, from: event.payload)
        else { return }
        state = decoded
    }

    /// Asked on every opening of the page and whenever Helm comes back to the
    /// front: the folder and the boxes are changed in System Settings, which
    /// means this window is behind while it happens.
    func refresh() { vm.send(ScreenshotsCommand.refresh) }
}
