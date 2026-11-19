import Foundation
import HelmContract
import HelmRuntime
import Module_Launchpad_Engine

/// What the model asks of the engine. A port, so a model's test holds the engine's place without a Mac's apps in reach.
protocol LaunchpadWork: AnyObject, Sendable {
    func read() -> LaunchpadSnapshot
    func hide(_ id: AppID) -> LaunchpadSnapshot?
    func resetArrangement() -> LaunchpadSnapshot?
    func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot?
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

/// The module's state, the one door to its engine and the one door to its window.
///
/// The window is opened only here (`showLaunchpad`, `toggleLaunchpad`), by the hotkey and by the page's button; `present`
/// is what builds it, set by the descriptor, and a model without it (a test) opens nothing. Whatever shows a snapshot
/// runs `whileShown()`: the snapshot is held only while somebody does, so a closed window holds no list of apps.
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
    /// One continuation per `whileShown()` running, so the page and the window watch together and either may leave.
    private var watchers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var closed = false
    /// The reset the person was asked about and has not answered.
    @Published private(set) var pendingReset = false
    /// Builds the window; nil in a test, and the window then never opens.
    var present: (@MainActor (LaunchpadViewModel) -> any LaunchpadWindowHandle)?
    private var window: (any LaunchpadWindowHandle)?
    /// The Dock helper nested in this Helm, set by the descriptor; nil when there is none, and the page then has no row for it.
    var helperURL: URL?
    /// Shows the helper in Finder; the descriptor sets it, so the page holds no AppKit.
    var revealHelper: @MainActor (URL) -> Void = { _ in }
    /// The module's own settings store, for the page's shortcut row.
    let store: NamespacedStore

    init(work: any LaunchpadWork, store: NamespacedStore) {
        self.work = work
        self.store = store
    }

    /// Closes the model: the host calls it before the engine's `deactivate()`. Whatever is still out lands nowhere.
    func stop() {
        closeLaunchpad()
        closed = true
        for continuation in watchers.values { continuation.finish() }
        watchers = [:]
        snapshot = nil
        notice = nil
        pendingReset = false
    }

    // MARK: - The window's door

    /// Opens the window, or brings the open one forward. Nothing after `stop()`.
    func showLaunchpad() {
        guard !closed else { return }
        if let window { window.bringForward(); return }
        guard let present else { return }
        let opened = present(self)
        window = opened
        opened.onClose = { [weak self, weak opened] in
            guard let self, let opened, self.window === opened else { return }
            self.window = nil
        }
        opened.present()
    }

    /// The shortcut's press: closes the window when it is open, opens it when it is not.
    func toggleLaunchpad() {
        if window != nil { closeLaunchpad() } else { showLaunchpad() }
    }

    func closeLaunchpad() {
        guard let open = window else { return }
        window = nil
        open.close()
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

    /// A drop in the window: one edit by anchors. Answers the snapshot that is shown after it, which is the old one when the edit
    /// was refused (the layout is read again then) or answered late.
    func place(_ change: LaunchpadEdit) async -> LaunchpadSnapshot? {
        await edit { $0.apply(change) }
        return snapshot
    }

    func rename(_ folder: UUID, to name: String) async { await edit { $0.apply(.rename(folder, to: name)) } }

    /// Asking changes nothing on disk: only `confirmReset` after it does.
    func askToReset() { if !closed { pendingReset = true } }
    func cancelReset() { pendingReset = false }

    /// Reads and clears the question first, so one answer resets once; nothing when it was not asked or the model is closed.
    func confirmReset() async {
        let asked = pendingReset
        pendingReset = false
        guard asked, !closed else { return }
        await edit { $0.resetArrangement() }
    }

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
        guard !closed, !watchers.isEmpty, latest.isLatest(mine), read != snapshot else { return }
        snapshot = read
    }

    /// One launch at a time: a second press while one is out is ignored. `name` is the one on the tile that was pressed.
    /// True only when the app was opened: the window closes then, and on anything else it stays with the notice.
    @discardableResult func launch(_ id: AppID, name: String) async -> Bool {
        guard !closed, !launching else { return false }
        launching = true
        defer { launching = false }
        let act = acts.take()
        let outcome = await work.launch(id)
        guard !closed, acts.isLatest(act) else { return outcome == .launched }
        switch outcome {
        case .launched: notice = nil
        case .gone: notice = .gone(name); await refresh()
        case .unreadable: notice = .couldNotOpen(name); await refresh()
        case .failed: notice = .couldNotOpen(name)
        }
        return outcome == .launched
    }

    /// What the page and the window run while they are on screen. The token is local to this task, so cancelling the task
    /// stops the watch; it is taken **before** the first read, so a change between the two is not lost. When the last
    /// watcher leaves, the snapshot and the notice go with it.
    func whileShown() async {
        guard !closed else { return }
        notice = nil
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        watchers[id] = continuation
        let token = work.observeChanges { continuation.yield() }
        defer {
            withExtendedLifetime(token) {}
            watchers[id] = nil
            if watchers.isEmpty { snapshot = nil; notice = nil }
        }
        await refresh()
        for await _ in stream {
            guard !closed else { break }
            await refresh()
        }
    }
}
