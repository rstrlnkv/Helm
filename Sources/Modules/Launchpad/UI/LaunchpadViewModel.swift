import Foundation
import HelmRuntime
import Module_Launchpad_Engine

/// What the model asks of the engine. A port, so a model's test holds the engine's place without a Mac's apps in reach.
protocol LaunchpadWork: AnyObject, Sendable {
    func read() -> LaunchpadSnapshot
    func hide(_ id: AppID) -> LaunchpadSnapshot?
    func unhide(_ id: AppID) -> LaunchpadSnapshot?
    func launch(_ id: AppID) async -> LaunchOutcome
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
}

extension LaunchpadEngine: LaunchpadWork {}

/// What the page says about the last thing that did not go through. The names are the apps', as the snapshot gave them.
enum LaunchNotice: Equatable {
    case gone(String)
    case couldNotOpen(String)
    case notSaved
}

/// The module's state and the one door to its engine.
///
/// `snapshot` is nil until the engine has answered once — busy, not empty. Every answer
/// from a hop off the main actor is dropped when a newer request exists or the model is closed — a
/// snapshot by the newer read, a notice by the newer edit or launch — and a snapshot is assigned only
/// when it differs from what is shown, so a watch event that changed nothing redraws nothing.
@MainActor public final class LaunchpadViewModel: ObservableObject {
    private let work: any LaunchpadWork
    @Published private(set) var snapshot: LaunchpadSnapshot?
    @Published private(set) var notice: LaunchNotice?
    private var latest = LatestRequest()
    /// Which edit or launch may still say how it went: a newer one has the say.
    private var acts = LatestRequest()
    private var launching = false
    private var changes: AsyncStream<Void>.Continuation?
    private var closed = false

    init(work: any LaunchpadWork) { self.work = work }

    /// Closes the model: the host calls it before the engine's `deactivate()`. Whatever is still out lands nowhere.
    func stop() {
        closed = true
        changes?.finish()
        changes = nil
        snapshot = nil
        notice = nil
    }

    func refresh() async {
        guard !closed else { return }
        let mine = latest.take()
        let work = self.work
        let read = await offTheCooperativePool { work.read() }
        land(read, mine)
    }

    func hide(_ id: AppID) async { await edit { $0.hide(id) } }
    func unhide(_ id: AppID) async { await edit { $0.unhide(id) } }

    /// Refused (the app is gone since the page was drawn) reads again; a save that did not land is said.
    private func edit(_ change: @escaping @Sendable (any LaunchpadWork) -> LaunchpadSnapshot?) async {
        guard !closed else { return }
        notice = nil
        let mine = latest.take()
        let act = acts.take()
        let work = self.work
        guard let edited = await offTheCooperativePool({ change(work) }) else { await refresh(); return }
        land(edited, mine)
        if !edited.saved, !closed, acts.isLatest(act) { notice = .notSaved }
    }

    private func land(_ read: LaunchpadSnapshot, _ mine: Int) {
        guard !closed, latest.isLatest(mine), read != snapshot else { return }
        snapshot = read
    }

    /// One launch at a time: a second press while one is out is ignored. `name` is the one on the tile that was pressed.
    func launch(_ id: AppID, name: String) async {
        guard !closed, !launching else { return }
        launching = true
        defer { launching = false }
        let act = acts.take()
        let outcome = await work.launch(id)
        guard !closed, acts.isLatest(act) else { return }
        switch outcome {
        case .launched: notice = nil
        case .gone: notice = .gone(name); await refresh()
        case .unreadable: notice = .couldNotOpen(name); await refresh()
        case .failed: notice = .couldNotOpen(name)
        }
    }

    /// What the page runs while it is on screen. The token is local to this task, so cancelling the task (the page leaving) stops
    /// the watch; it is taken **before** the first read, so a change between the two is not lost.
    func whileShown() async {
        guard !closed else { return }
        notice = nil
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        changes = continuation
        let token = work.observeChanges { continuation.yield() }
        await refresh()
        for await _ in stream {
            guard !closed else { break }
            await refresh()
        }
        withExtendedLifetime(token) {}
    }
}
