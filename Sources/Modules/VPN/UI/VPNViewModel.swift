import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// What the model asks of the engine: the person's door and nothing the rules
/// use. A fake stands for the engine in `AStoppedVPNModelReachesNoWorkTests`.
protocol VPNWork: AnyObject, Sendable {
    /// The latest state, then every later one, in order; registered before it returns.
    func stream() -> AsyncStream<VPNEngine.StatePayload>
    /// Re-read the system's answer; returns at once.
    func refresh()
    /// A press on a card. Never an automatic act: the engine's own `auto` flag
    /// is not reachable through this.
    func press(_ verb: VPNVerb, on name: String)
    /// One speed run on the named tunnel; the engine refuses any but the one
    /// carrying the default route, and says so in its next state.
    func measureSpeed(_ name: String)
    /// Re-read the saved rules, on the engine's own queue; returns at once.
    func reloadRules()
}

extension VPNEngine: VPNWork {}

@MainActor public final class VPNViewModel: ObservableObject {
    @Published private(set) var connections: [VPNConnection] = []
    @Published private(set) var autoConnected: Set<String> = []
    /// The last rule firing worth reacting to, or nil. Stale firings never get
    /// here — see `apply`.
    @Published private(set) var lastAutomation: VPNAutomation?
    /// The last command `scutil` did not accept, cleared by the next one it
    /// did. The engine has published this since it learned to read the tool's
    /// output; nothing here decoded it, so pressing Connect on a configuration
    /// macOS refuses ran the spinner and returned the card exactly as it was.
    @Published private(set) var lastFailure: VPNFailure?
    /// Configurations whose stored secret Helm may not read unattended — sorted by
    /// the engine, so the page draws them in one order.
    ///
    /// A standing state rather than an event, and it is what the two sentences on
    /// this page are drawn from: a rule whose tunnel is in here cannot fire until
    /// somebody presses Connect once, and the engine stops attempting a
    /// `--nc start` it knows cannot work (`VPNSecretBook`).
    @Published private(set) var secretsBehindAPrompt: [String] = []
    /// Every connected tunnel that has an interface reading, the one carrying
    /// the default route first. Empty when nothing is up — the strip is absent
    /// then, rather than empty.
    @Published private(set) var tunnels: [VPNTunnelState] = []
    /// **Which tunnel** a measurement is in flight for, or nil — the engine's
    /// answer, not this object's memory of a press.
    ///
    /// The press still sets it, because the engine answers on its own work
    /// queue, after the press has returned, and a button that does nothing for a
    /// moment reads as a button that did not work; but every state that arrives overwrites it with what the engine
    /// says (`VPNTunnelState.measuring`). A flag that only a press could set was
    /// wrong in three ways: a page opened while a run was going knew nothing
    /// about it, a run outliving the page that started it left the next one
    /// spinning, and a run the tool refused over a quiet tunnel changed no other
    /// field — so the engine withheld the payload as a duplicate and the arrival
    /// that was meant to clear the spinner never came.
    ///
    /// A name rather than a `Bool` because a run belongs to one tunnel: one
    /// boolean would turn a spinner over every tunnel in the list while a single
    /// run was going.
    @Published private(set) var measuring: String?

    private let work: any VPNWork
    private let settings: VPNSettings?
    /// What macOS is asked to post a banner through. Optional because nothing
    /// in a test may reach the real one — `UNUserNotificationCenter.current()`
    /// takes the whole run down from a process that is not a bundled app — so a
    /// view model built without a port simply never posts.
    private var notices: AutomationNoticePort?
    /// Set only by `setForTesting`; nil in the app, always.
    private var noticeForTesting: VPNNotice?
    private var dropNoticeForTesting: VPNNotice?
    private var bannerAuthorizedForTesting: Bool?
    private var spinForTesting: Bool?
    private var eventsTask: Task<Void, Never>?
    private(set) var closed = false
    private var expiryTask: Task<Void, Never>?
    /// The announcement of the last firing, while it is still in flight.
    ///
    /// Held so it can be waited on: what a firing said is decided across an
    /// `await`, and a test that instead yielded a fixed number of times would
    /// be asserting on whichever half had finished — green by luck, which is
    /// how an inert fix shipped here once. `deinit` cancels it with the others;
    /// nothing inside checks for cancellation, so that is bookkeeping rather
    /// than a way to call a banner back.
    private(set) var announcement: Task<Void, Never>?

    /// How loudly a firing is announced. Read from the store at every ask
    /// rather than cached, so a change in Settings applies to the next firing
    /// instead of to the next launch.
    var notice: VPNNotice { noticeForTesting ?? settings?.notice ?? .menuBar }

    /// …and the one for a tunnel that fell over by itself, which is a separate
    /// setting because it is separate news. `noticeForTesting` covers both: a
    /// test that sets a mode is setting the module's voice, and one that wants
    /// them to differ passes `dropNotice`.
    /// Through `VPNNotice.mode`, which is the same rule the store reads: this end
    /// used to answer «the drop setting for a drop, the rules' setting for
    /// everything else» in its own words, and a teardown Helm performed then took
    /// the rules' volume however loudly the person had asked to hear about losing
    /// a tunnel. Two spellings of one decision, and only one of them was fixed.
    func notice(for kind: VPNAutomation.Kind) -> VPNNotice {
        let rules = noticeForTesting ?? settings?.notice ?? .menuBar
        let drop = dropNoticeForTesting ?? noticeForTesting ?? settings?.dropNotice ?? .menuBar
        return VPNNotice.mode(for: kind, rules: rules, drop: drop)
    }

    /// **The configuration a firing happened on, when the name says so without
    /// ambiguity.**
    ///
    /// A firing carries the configuration's *name*, because that is what
    /// `scutil --nc start` takes; the per-connection settings are keyed by its
    /// id, because a name is retyped. This is the join, and it refuses to guess:
    /// macOS lets two configurations carry one display name (ARCHITECTURE.md §
    /// VPN), and applying one of two namesakes' settings to a firing that might
    /// be the other's is a setting applied to the wrong tunnel. Two matches, or
    /// none, and the module-wide value is the honest answer.
    func connectionID(named name: String) -> String? {
        let matches = connections.filter { $0.name == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// The three questions a firing asks, resolved on the configuration it
    /// happened on. **Nothing in the firing path may read the module-wide value
    /// directly**: it did until 2026-08-17, and the switch each card had just
    /// been given was therefore written to the store and never read — the
    /// popover was a control that changed nothing (`TheRingTurnsInThisTunnelsColourTests`).
    func notice(for kind: VPNAutomation.Kind, on name: String) -> VPNNotice {
        guard noticeForTesting == nil, dropNoticeForTesting == nil,
              let settings, let id = connectionID(named: name)
        else { return notice(for: kind) }
        return settings.notice(for: kind, connectionID: id)
    }

    func automationSpin(on name: String) -> Bool {
        guard spinForTesting == nil, let settings, let id = connectionID(named: name)
        else { return automationSpin }
        return settings.automationSpin(connectionID: id)
    }

    func spinTint(for kind: VPNAutomation.Kind, on name: String) -> String {
        guard let settings, let id = connectionID(named: name)
        else { return spinTint(for: kind) }
        return settings.spinTint(for: kind, connectionID: id)
    }

    /// Whether the menu-bar ring turns when a rule fires. Read at every ask
    /// rather than cached, like `notice`, so a change in Settings applies to
    /// the next firing instead of to the next launch.
    var automationSpin: Bool {
        spinForTesting ?? settings?.automationSpin ?? false
    }

    /// The colour that firing turns in.
    func spinTint(for kind: VPNAutomation.Kind) -> String {
        settings?.spinTint(for: kind)
            ?? (kind == .connected ? "green" : "orange")
    }

    /// Whether a banner would actually be shown.
    ///
    /// The freshest answer wins: `bannerAuthorization` is what macOS said this
    /// launch, and the store is only what it said some launch ago. The order
    /// matters because a firing asks macOS on its way past and the label
    /// decision is read a moment later — the stored mirror is the thing that
    /// was believed while the permission was already gone.
    var bannerAuthorized: Bool {
        if let heard = bannerAuthorization { return heard == .authorized }
        return bannerAuthorizedForTesting ?? settings?.bannerAuthorized ?? false
    }

    /// The mode as it will actually behave, which is not always the mode that
    /// was chosen: `.system` without the permission is the menu-bar label, and
    /// anything that acts on the choice has to ask this rather than the raw one.
    var effectiveNotice: VPNNotice {
        notice.effective(bannerAuthorized: bannerAuthorized)
    }

    /// The same, for the firing in hand. A tunnel that fell over answers to its
    /// own setting, and the menu-bar name is decided from the firing's kind
    /// rather than from the rules' mode.
    func effectiveNotice(for kind: VPNAutomation.Kind) -> VPNNotice {
        notice(for: kind).effective(bannerAuthorized: bannerAuthorized)
    }

    /// The same for a firing, on the configuration it happened on.
    func effectiveNotice(for kind: VPNAutomation.Kind, on name: String) -> VPNNotice {
        notice(for: kind, on: name).effective(bannerAuthorized: bannerAuthorized)
    }

    /// What macOS answered the last time it was asked, this launch — by the
    /// settings page, or by a firing on its way to a banner. Nil until
    /// something asks, which is why the settings row says nothing about a
    /// permission that has never come up.
    @Published private(set) var bannerAuthorization: NoticeAuthorization?

    /// Whether there is any way to reach macOS's banners from here.
    ///
    /// The descriptor is the only thing that supplies the port, and a wire
    /// forgotten there would leave the banner mode mute for good while every
    /// test carrying its own fake port went on passing. `VPNNoticeChoiceTests`
    /// asks this so that cannot happen quietly.
    var reachesBanners: Bool { notices != nil }

    /// The person picked a mode.
    ///
    /// The only place in Helm that asks macOS for the notification permission,
    /// and it asks only for the mode that needs one — `AutomationNotice.prepare`
    /// reads the state for the other two. macOS grants that prompt once ever, so
    /// asking at launch, or on every visit to this page, spends it on somebody
    /// who was not asking for notifications.
    @discardableResult
    func choose(_ notice: VPNNotice, for kind: VPNAutomation.Kind = .connected) async
        -> NoticeAuthorization? {
        // The kind names the *setting*, not one event: `.dropped` is the tunnel
        // that fell over, anything else is the rules.
        if kind == .dropped { settings?.setDropNotice(notice) } else { settings?.setNotice(notice) }
        guard let port = notices else { return nil }
        return record(await AutomationNotice.prepare(for: notice, port: port))
    }

    /// Re-reads what macOS says now, prompting nobody.
    ///
    /// The mirror is a memory of an answer, and the person can revoke banners
    /// in System Settings without Helm hearing a thing; then `.system` would
    /// post nothing and suppress the label on the strength of a stale yes.
    @discardableResult
    func refreshBannerAuthorization() async -> NoticeAuthorization? {
        guard let port = notices else { return nil }
        return record(await port.authorizationState())
    }

    private func record(_ answer: NoticeAuthorization) -> NoticeAuthorization {
        bannerAuthorization = answer
        settings?.setBannerAuthorized(answer == .authorized)
        return answer
    }

    /// Test seam. `@testable` reaches it; nothing in the app does. It stands in
    /// for the engine that fires the rule and for the store that holds the mode,
    /// neither of which a test of the status item wants to own.
    func setForTesting(automation: VPNAutomation?, notice: VPNNotice,
                       dropNotice: VPNNotice? = nil,
                       bannerAuthorized: Bool = false,
                       notices: AutomationNoticePort? = nil,
                       spin: Bool = false) {
        noticeForTesting = notice
        dropNoticeForTesting = dropNotice
        bannerAuthorizedForTesting = bannerAuthorized
        spinForTesting = spin
        if let notices { self.notices = notices }
        if let automation { adopt(automation) } else { lastAutomation = nil }
    }

    /// Takes a firing, and gives it up again when its name window closes.
    ///
    /// The expiry is not decoration. The host redraws the icon when this model
    /// publishes or while it has a frame of a spin left to draw, and the name
    /// outlives the spin by 1.8 s — so once the ring stops, nothing on either
    /// side has any reason to look again, and the name sat on the icon until an
    /// unrelated event happened to redraw it away.
    private func adopt(_ firing: VPNAutomation) {
        lastAutomation = firing
        expiryTask?.cancel()
        let remaining = VPNAutomation.nameDuration - Date().timeIntervalSince(firing.at)
        // `self` is resolved only after the sleep, so the wait itself holds
        // nothing — and `deinit` cancels whatever is still waiting.
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, remaining) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.lastAutomation = nil
        }
    }

    /// The stream is taken here, synchronously, before the first suspension:
    /// `stream()` registers the subscriber and replays the latest state in one
    /// step, so no state emitted from this line on is missed. Nothing is asked
    /// of the engine; `activate()` emits and the replay delivers.
    init(work: any VPNWork, settings: VPNSettings? = nil,
         notices: AutomationNoticePort? = nil) {
        self.work = work
        self.settings = settings
        self.notices = notices
        let states = work.stream()
        eventsTask = Task { [weak self] in
            for await state in states {
                guard let self, !self.closed else { break }
                self.apply(state)
            }
        }
    }

    /// Ends the event loop, which unregisters the engine's subscriber, ends the
    /// firing's expiry and announcement, and closes the doors to the engine. The
    /// host calls it through the descriptor's `stop(_:)` before the engine's
    /// `deactivate()`.
    func stop() {
        closed = true
        eventsTask?.cancel()
        eventsTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        announcement?.cancel()
        announcement = nil
    }

    /// The backstop for a model dropped without `stop()`: the loop re-acquires
    /// `self` per state, so it does not keep the model alive.
    deinit { eventsTask?.cancel(); expiryTask?.cancel(); announcement?.cancel() }

    /// Re-reads the system's answer when the page or the panel tile appears. The
    /// engine also re-reads on its own after every network change
    /// (`VPNEngine.networkChanged`); this is the ask for a surface that has just
    /// come on screen.
    func refresh() {
        guard !closed else { return }
        work.refresh()
    }

    private func apply(_ p: VPNEngine.StatePayload) {
        connections = p.connections
        autoConnected = Set(p.autoConnected)
        lastFailure = p.lastFailure
        secretsBehindAPrompt = p.secretsBehindAPrompt
        tunnels = p.tunnels
        // **The engine says whether a run is going; this only repeats it.**
        // Comparing the reading against the last one is true of neither awkward
        // ending: a run that answers the same numbers as before would leave the
        // spinner turning for ever, and a run the port refused — a `-1009`, a
        // tool killed at its deadline — never touches `speed` at all. Clearing
        // on any arrival covered both, until the arrival itself stopped coming:
        // over a quiet tunnel a refused run leaves every field of the payload
        // as it was, and `emitState` withholds a duplicate. So the run's own
        // state travels with the rest, and both ends of it are a change.
        measuring = p.tunnels.first(where: \.measuring)?.name
        // Stale firings are dropped here rather than downstream. The engine
        // keeps its last one for good and repeats it in every state payload, so
        // the first refresh after launch would otherwise spin the ring for
        // something that happened yesterday. Dropped once, on arrival, so that
        // nothing downstream has to ask a second time how old it is.
        if let firing = p.lastAutomation, VPNAutomation.showsName(firing, now: Date()) {
            // Asked before `adopt`, which is what makes the answer mean "this
            // one is new": the engine repeats its last firing in every state
            // payload, and a refresh inside the name window would otherwise
            // post the same banner again.
            let unheard = firing != lastAutomation
            adopt(firing)
            if unheard { announce(firing) }
        }
    }

    /// The banner, in the mode that posts one.
    ///
    /// It rides the same arrival as the ring and the label, so a firing reaches
    /// all three channels or none — `.system` hides the menu-bar name because
    /// the banner is meant to carry it, and a banner wired anywhere else would
    /// leave that mode saying nothing at all.
    ///
    /// The words are written here because `L()` is here: the engine decides
    /// whether to post, this decides what it says.
    ///
    /// What macOS answers on the way through is kept, because the label
    /// decision downstream reads it: a permission revoked in System Settings
    /// turns `.system` back into the menu-bar name at the next firing rather
    /// than at the next visit to the settings page. Publishing it is what
    /// redraws the icon — `statusChanges` is this model's `objectWillChange` —
    /// so the name appears a hop after the ring starts, well inside its three
    /// seconds. The stored mirror is left alone here: it is what the settings
    /// page displays, and it is written where the person can see it change.
    private func announce(_ firing: VPNAutomation) {
        guard let port = notices else { return }
        let mode = notice(for: firing.kind, on: firing.name)
        let title = VPNStr.automationBannerTitle(firing.kind)
        let body = VPNStr.automationBannerBody(firing.name, kind: firing.kind)
        // Resolves `self` only after the await, so the wait holds nothing.
        announcement = Task { [weak self] in
            let heard = await AutomationNotice.announce(notice: mode, title: title,
                                                        body: body, port: port)
            guard let heard else { return }
            self?.bannerAuthorization = heard
        }
    }

    /// Asks for one measurement, **on a named tunnel**. It spends real traffic
    /// and takes `NetworkQualitySpeed.typicalRun`, which is why nothing calls this
    /// but a press.
    ///
    /// The engine refuses a name that is not the tunnel carrying the default
    /// route and publishes when it does, so the optimistic flag below is cleared
    /// by that refusal exactly the way it is cleared by a run that finished
    /// (`measuring` says why the press sets it).
    func measureSpeed(_ name: String) {
        guard !closed else { return }
        measuring = name
        work.measureSpeed(name)
    }
    func connect(_ name: String) {
        guard !closed else { return }
        work.press(.connect, on: name)
    }
    func disconnect(_ name: String) {
        guard !closed else { return }
        work.press(.disconnect, on: name)
    }
    /// The saved rules changed: the engine re-reads them.
    func rulesChanged() {
        guard !closed else { return }
        work.reloadRules()
    }
}
