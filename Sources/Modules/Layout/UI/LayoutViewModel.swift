import SwiftUI
import Module_Layout_Engine

/// What the model asks of the engine: the one door. A fake stands for the engine
/// in `AStoppedLayoutModelReachesNoWorkTests`.
protocol LayoutWork: AnyObject, Sendable {
    /// The latest state, then every later one, in order; registered before it returns.
    func stream() -> AsyncStream<LayoutState>
    /// The gesture and the hotkey: fix whatever is in front of the caret.
    func fix()
    /// Re-read the store, on the engine's own serial queue; returns at once.
    func settingsChanged()
}

extension LayoutEngine: LayoutWork {}

@MainActor public final class LayoutViewModel: ObservableObject {
    @Published public private(set) var state = LayoutState(enabled: false, automatic: true,
                                                           suspended: false,
                                                           lastConversion: nil,
                                                           lastConversionUndone: false,
                                                           totals: .none)
    private let work: any LayoutWork
    private var eventsTask: Task<Void, Never>?
    private(set) var closed = false

    /// The stream is taken here, synchronously, before the first suspension:
    /// `stream()` registers the subscriber and replays the latest state in one
    /// step, so no state emitted from this line on is missed.
    init(work: any LayoutWork) {
        self.work = work
        let states = work.stream()
        eventsTask = Task { [weak self] in
            for await state in states {
                guard let self, !self.closed else { break }
                self.state = state
            }
        }
    }

    /// Ends the event loop, which unregisters the engine's subscriber, and
    /// closes the doors to the engine. The host calls it through the
    /// descriptor's `stop(_:)` before the engine's `deactivate()`.
    func stop() {
        closed = true
        eventsTask?.cancel()
        eventsTask = nil
    }

    /// The backstop for a model dropped without `stop()`: the loop re-acquires
    /// `self` per state, so it does not keep the model alive.
    deinit { eventsTask?.cancel() }

    func fix() {
        guard !closed else { return }
        work.fix()
    }

    func settingsChanged() {
        guard !closed else { return }
        work.settingsChanged()
    }
}
