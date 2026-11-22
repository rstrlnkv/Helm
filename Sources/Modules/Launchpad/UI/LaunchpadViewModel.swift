import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

/// What the model asks of the engine. A port, so a model's test holds the engine's place without a Mac's apps in reach.
protocol LaunchpadWork: AnyObject, Sendable {
    func read(reason: CatalogReadReason) -> LaunchpadSnapshot
    func hide(_ id: AppID) -> LaunchpadSnapshot?
    func resetArrangement() -> LaunchpadSnapshot?
    func apply(_ edit: LaunchpadEdit) -> LaunchpadSnapshot?
    func unhide(_ id: AppID) -> LaunchpadSnapshot?
    func resetLaunchCounts() -> LaunchpadSnapshot?
    func launch(_ id: AppID) async -> LaunchOutcome
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
    /// What the trackpad watch came to; nil when none runs.
    var pinchWatch: TouchWatchStart? { get }
    func setPinchWatching(_ on: Bool) -> TouchWatchStart?
    func systemPinchSetting() -> SystemPinch
}

/// Where the person's pinch switch is kept: a plain key of the module's store, off when missing. **Deployed stored data: this name never moves.**
enum LaunchpadPinchKey {
    static let on = "gesture.pinch"
}

/// What the page says about the pinch watch. `unavailable` folds the framework missing and a layout that was refused: the person can do nothing about either.
enum PinchState: Equatable {
    case off, watching, noTrackpad, unavailable

    init(_ start: TouchWatchStart?) {
        switch start {
        case nil: self = .off
        case .watching: self = .watching
        case .noTrackpad: self = .noTrackpad
        case .frameworkMissing, .layoutRefused: self = .unavailable
        }
    }
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
    /// Makes the port a lock asks Touch ID or the password through; one per lock, so one scope closing cannot cancel another's prompt. A test replaces it.
    var makeAuth: () -> any LaunchpadAuthPort = { SystemLaunchpadAuth() }
    @Published private(set) var snapshot: LaunchpadSnapshot?
    @Published private(set) var notice: LaunchNotice?
    private var latest = LatestRequest()
    /// Which edit or launch may still say how it went: a newer one has the say.
    private var acts = LatestRequest()
    private var launching = false
    /// One continuation per `whileShown()` running, so the page and the window watch together and either may leave.
    private var watchers: [Int: AsyncStream<Void>.Continuation] = [:]
    /// Which of those is the window's own (the one that ran with `.open`, as `LaunchpadWindow` calls it): a held handle says nothing of whether it is watching yet.
    private var windowWatchers: Set<Int> = []
    private var watcherCount = 0
    private var closed = false
    /// The reset the person was asked about and has not answered.
    @Published private(set) var pendingReset = false
    /// Builds the window; nil in a test, and the window then never opens.
    var present: (@MainActor (LaunchpadViewModel) -> any LaunchpadWindowHandle)?
    private var window: (any LaunchpadWindowHandle)?
    /// What the fingers' scrub is doing to the window, from `began` to `ended`. `spent`: a reduced-motion hand that already acted.
    private enum Scrub { case none, opening, closing, forwarding, reduced(PinchDirection), spent }
    private var scrub = Scrub.none
    /// Whether the person asked for less motion, asked at each `began`; a test sets it.
    var reduceMotion: () -> Bool = { HelmMotion.reduceMotion }
    /// The Dock helper nested in this Helm, set by the descriptor; nil when there is none, and the page then has no row for it.
    var helperURL: URL?
    /// Shows the helper in Finder; the descriptor sets it, so the page holds no AppKit.
    var revealHelper: @MainActor (URL) -> Void = { _ in }
    /// Shows an app's file in Finder and puts its path on the pasteboard; the descriptor sets them, so the window holds no AppKit. No-ops until then, so no test
    /// touches the Mac's Finder or pasteboard.
    var revealApp: @MainActor (String) -> Void = { _ in }
    /// `concealed`: the copy is of a hidden app, and the pasteboard marks it so a clipboard manager need not keep it.
    var copyPath: @MainActor (String, _ concealed: Bool) -> Void = { _, _ in }
    /// The module's own settings store, for the page's shortcut row.
    let store: NamespacedStore
    /// The grid the person chose; read from the store (`LaunchpadGridSettings`), written only by `setGrid`.
    @Published private(set) var grid: LaunchpadGridSettings
    /// The view the window opens in, as the store holds it; the window reads it once, when it is built.
    @Published private(set) var viewMode: LaunchpadViewMode
    /// The pinch switch, as the store holds it; the watch itself is the engine's (`pinchState`).
    @Published private(set) var pinchOn: Bool
    @Published private(set) var pinchState: PinchState
    /// True while the system's own four- or five-finger pinch is on, so both would open something. Read, never written.
    @Published private(set) var systemPinchIsOn = false
    /// Opens System Settings at Trackpad; the descriptor sets it, so the page holds no AppKit.
    var openTrackpadSettings: @MainActor () -> Void = {}

    init(work: any LaunchpadWork, store: NamespacedStore) {
        self.work = work
        self.store = store
        grid = LaunchpadGridSettings.read(from: store)
        viewMode = LaunchpadViewMode.read(from: store)
        pinchOn = store.bool(LaunchpadPinchKey.on, default: false)
        pinchState = PinchState(work.pinchWatch)
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

    // MARK: - The grid

    /// Takes a new grid: clamped, refused when it is the one held. A `live` call (a drag in progress) only publishes it, so
    /// the open window re-pages from it and nothing is written; any other call publishes it and then writes it by `commitGrid`.
    func setGrid(_ new: LaunchpadGridSettings, live: Bool = false) {
        let next = new.normalized()
        guard !closed, next != grid else { return }
        if live { grid = next } else { grid = next; commitGrid() }
    }

    /// Writes the keys that differ from what the store holds, and says so in one log line: a drag ends in one write.
    func commitGrid() {
        let stored = LaunchpadGridSettings.read(from: store)
        guard !closed, stored != grid else { return }
        grid.write(changedFrom: stored, to: store)
        HelmLog.shared.info("launchpad", "grid \(grid.automatic ? "automatic x\(grid.sizeMultiplier)" : "\(grid.columns)x\(grid.rows)"), icon \(Int(grid.iconSize))")
    }

    func resetGrid() { setGrid(.standard) }

    /// Reads the store again, for a window about to open and the page appearing: a value edited behind Helm's back shows then.
    func reloadGrid() {
        let read = LaunchpadGridSettings.read(from: store)
        if read != grid { grid = read }
    }

    // MARK: - The view

    /// Written when the window's switch is used; refused when equal. The arrangement is neither read nor written.
    func setViewMode(_ new: LaunchpadViewMode) {
        guard !closed, new != viewMode else { return }
        viewMode = new
        store.set(new.rawValue, for: LaunchpadViewMode.key)
        HelmLog.shared.info("launchpad", "view \(new.rawValue)")
    }

    /// Reads the store again, for a window about to open.
    func reloadViewMode() {
        let read = LaunchpadViewMode.read(from: store)
        if read != viewMode { viewMode = read }
    }

    // MARK: - The pinch

    /// The switch: written to the store, then the watch follows it. Nothing after `stop()`.
    func setPinch(on: Bool) {
        guard !closed, on != pinchOn else { return }
        pinchOn = on
        store.set(on, for: LaunchpadPinchKey.on)
        pinchState = PinchState(work.setPinchWatching(on))
        HelmLog.shared.info("launchpad", "pinch switched \(on ? "on" : "off")")
    }

    /// For the page appearing: the switch as the store holds it now, the watch as the engine has it, and what the system's pinch says.
    func reloadPinch() async {
        guard !closed else { return }
        let read = store.bool(LaunchpadPinchKey.on, default: false)
        if read != pinchOn { pinchOn = read; _ = work.setPinchWatching(read) }
        pinchState = PinchState(work.pinchWatch)
        let work = self.work
        let system = await offTheCooperativePool { work.systemPinchSetting() }
        if !closed { systemPinchIsOn = system == .on }
    }

    /// What the fingers do to the window, as the engine says it. A scrub follows the hand: a pinch opens the window from nothing
    /// and a spread closes the one that is open, each a half of the shortcut's press, and the end completes it or puts it back.
    /// A pinch with the window open brings it forward, a spread with none open does nothing. With reduced motion nothing follows
    /// the hand: the window opens or closes at once, where the gesture reaches 1 or, short of that, where it ends complete (released past the
    /// midpoint or flicked), unless it already did. Nothing after `stop()`.
    func pinched(_ event: PinchEvent) {
        guard !closed else { return }
        switch event {
        case .began(let direction, let progress):
            if reduceMotion() {
                scrub = .reduced(direction)
                if progress >= 1 { complete(direction); scrub = .spent }
                return
            }
            switch (direction, window) {
            case (.pinch, nil):
                guard let opened = openWindow() else { scrub = .none; return }
                opened.beginScrub(.pinch)
                opened.scrub(to: progress)
                scrub = .opening
            case (.pinch, _):
                scrub = .forwarding
            case (.spread, let open?):
                open.beginScrub(.spread)
                open.scrub(to: progress)
                scrub = .closing
            case (.spread, nil):
                scrub = .none
            }
        case .moved(let progress):
            switch scrub {
            case .opening, .closing: window?.scrub(to: progress)
            case .reduced(let direction): if progress >= 1 { complete(direction); scrub = .spent }
            case .none, .forwarding, .spent: break
            }
        case .ended(let outcome):
            let was = scrub
            scrub = .none
            switch (was, outcome) {
            case (.opening, .complete): window?.endScrub(.complete)
            case (.opening, .revert):
                let half = window
                window = nil
                half?.endScrub(.revert)
            case (.closing, .complete):
                let open = window
                window = nil
                open?.endScrub(.complete)
            case (.closing, .revert): window?.endScrub(.revert)
            case (.forwarding, .complete): window?.bringForward()
            case (.reduced(let direction), .complete): complete(direction)
            default: break
            }
        }
    }

    /// The shortcut's two halves, whole: a pinch opens the window or brings it forward, a spread closes it.
    private func complete(_ direction: PinchDirection) {
        guard !closed else { return }
        switch direction {
        case .pinch: showLaunchpad()
        case .spread: closeLaunchpad()
        }
    }

    // MARK: - The window's door

    /// Opens the window, or brings the open one forward. Nothing after `stop()`.
    func showLaunchpad() {
        guard !closed else { return }
        if let window { scrub = .none; window.bringForward(); return }
        openWindow()?.present()
    }

    /// Builds the window and holds it, its `onClose` set; nil when there is no builder (a test).
    private func openWindow() -> (any LaunchpadWindowHandle)? {
        guard let present else { return nil }
        reloadGrid()
        reloadViewMode()
        let opened = present(self)
        window = opened
        opened.onClose = { [weak self, weak opened] in
            guard let self, let opened, self.window === opened else { return }
            self.window = nil
            scrub = .none
        }
        return opened
    }

    /// The shortcut's press: closes the window when it is open, opens it when it is not.
    func toggleLaunchpad() {
        if window != nil { closeLaunchpad() } else { showLaunchpad() }
    }

    func closeLaunchpad() {
        scrub = .none
        guard let open = window else { return }
        window = nil
        open.close()
    }

    func refresh(reason: CatalogReadReason) async {
        guard !closed else { return }
        let mine = latest.take()
        let work = self.work
        let read = await offTheCooperativePool { work.read(reason: reason) }
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

    /// Empties the counts the category view orders by; nothing is written when there are none.
    func resetLaunchCounts() async { await edit { $0.resetLaunchCounts() } }

    func rename(_ folder: UUID, to name: String) async { await edit { $0.apply(.rename(folder, to: name)) } }
    func resize(_ folder: UUID, large: Bool) async { await edit { $0.apply(.resize(folder, large: large)) } }
    /// nil gives the app back to its own category.
    func moveToCategory(_ id: AppID, to target: LaunchpadCategoryTarget?) async { await edit { $0.apply(.setCategory(id, target)) } }
    func returnAllMoved() async { await edit { $0.apply(.returnAllToOwnCategory) } }

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
        guard let edited = await offTheCooperativePool({ change(work) }) else { await refresh(reason: .refresh); return }
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
        case .launched:
            notice = nil
            // The engine counted it: a page that is shown reads the new counts. The window's own watch is no such page: it closes with this launch
            // and drops the snapshot, so that read would be for nobody.
            if watchers.keys.contains(where: { !windowWatchers.contains($0) }) { await refresh(reason: .launch) }
        case .gone: notice = .gone(name); await refresh(reason: .launch)
        case .unreadable: notice = .couldNotOpen(name); await refresh(reason: .launch)
        case .failed: notice = .couldNotOpen(name)
        }
        return outcome == .launched
    }

    /// The Hidden card is gone: a notice that names an app is dropped, for it may name a hidden one. One that does not stays.
    func dropNamedNotice() {
        switch notice {
        case .gone, .couldNotOpen: notice = nil
        case .notSaved, nil: break
        }
    }

    /// What the page and the window run while they are on screen. The token is local to this task, so cancelling the task
    /// stops the watch; it is taken **before** the first read, so a change between the two is not lost. When the last
    /// watcher leaves, the snapshot and the notice go with it.
    func whileShown(reason: CatalogReadReason = .open) async {
        guard !closed else { return }
        notice = nil
        watcherCount += 1
        let id = watcherCount
        // A second watcher (the settings page beside the window) reads nothing at its start and nothing for a change: the oldest one's read
        // lands in the one snapshot they share.
        let alone = watchers.isEmpty
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        watchers[id] = continuation
        if reason == .open { windowWatchers.insert(id) }
        let token = work.observeChanges { continuation.yield() }
        defer {
            withExtendedLifetime(token) {}
            watchers[id] = nil
            windowWatchers.remove(id)
            if watchers.isEmpty { snapshot = nil; notice = nil }
        }
        if alone { await refresh(reason: reason) }
        for await _ in stream {
            guard !closed else { break }
            if id == watchers.keys.min() { await refresh(reason: .watch) }
        }
    }
}
