import SwiftUI
import HelmUI
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
    @Published public private(set) var state = LayoutState(enabled: false,
                                                           suspended: false,
                                                           lastConversion: nil,
                                                           lastConversionUndone: false,
                                                           totals: .none)
    private let work: any LayoutWork
    private var events: StreamFollower?
    private(set) var closed = false

    init(work: any LayoutWork) {
        self.work = work
        events = StreamFollower(work.stream(), owner: self) { $0.state = $1 }
    }

    /// Ends the event loop, which unregisters the engine's subscriber, and
    /// closes the doors to the engine. The host calls it through the
    /// descriptor's `stop(_:)` before the engine's `deactivate()`.
    func stop() {
        closed = true
        events?.cancel()
    }

    func fix() {
        guard !closed else { return }
        work.fix()
    }

    func settingsChanged() {
        guard !closed else { return }
        work.settingsChanged()
    }
}
