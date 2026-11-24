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
    /// did. Without it a refused Connect would run the spinner and return the
    /// card unchanged.
    @Published private(set) var lastFailure: VPNFailure?
    /// Configurations whose stored secret Helm may not read unattended, sorted
    /// by the engine. A standing state: a rule whose tunnel is in here cannot
    /// fire until somebody presses Connect once, and the engine stops
    /// attempting a `--nc start` it knows cannot work (`VPNSecretBook`).
    @Published private(set) var secretsBehindAPrompt: [String] = []
    @Published private(set) var ruleRefusals: [String: VPNRuleTrust.Verdict] = [:]
    /// Every connected tunnel that has an interface reading, the one carrying
    /// the default route first. Empty when nothing is up — the strip is absent
    /// then, rather than empty.
    @Published private(set) var tunnels: [VPNTunnelState] = []
    /// **Which tunnel** a measurement is in flight for, or nil: the engine's
    /// answer, not this object's memory of a press.
    ///
    /// The press sets it, because the engine answers on its own queue after
    /// the press returns, and a button that does nothing for a moment reads as
    /// broken. Every arriving state overwrites it (`VPNTunnelState.measuring`),
    /// so a page opened mid-run knows of the run, and a run refused over a
    /// quiet tunnel still clears it.
    ///
    /// A name rather than a `Bool` because a run belongs to one tunnel.
    @Published private(set) var measuring: String?

    private let work: any VPNWork
    private let settings: VPNSettings
    /// What macOS is asked to post a banner through. Optional because no test
    /// may reach the real one: `UNUserNotificationCenter.current()` crashes a
    /// process that is not a bundled app. Without a port nothing is posted.
    private var notices: AutomationNoticePort?
    private var events: StreamFollower?
    private(set) var closed = false
    private var expiryTask: Task<Void, Never>?
    /// The announcement of the last firing, while it is still in flight.
    ///
    /// Held so a test can wait on it: what a firing says is decided across an
    /// `await`, and yielding a fixed number of times would assert on whichever
    /// half had finished. Cancelling it is bookkeeping, not a way to call a
    /// banner back: nothing inside checks for cancellation.
    private(set) var announcement: Task<Void, Never>?

    /// **The configuration a firing happened on, when the name says so without
    /// ambiguity.**
    ///
    /// A firing carries the configuration's *name*, because `scutil --nc start`
    /// takes one; the per-connection settings are keyed by id. This join
    /// refuses to guess: macOS lets two configurations carry one display name
    /// (Architecture/VPN.md § VPN), so two matches, or none, answer nil and
    /// the module-wide value applies.
    func connectionID(named name: String) -> String? {
        let matches = connections.filter { $0.name == name }
        return matches.count == 1 ? matches[0].id : nil
    }

    /// The three questions a firing asks, resolved on the configuration it
    /// happened on, and read from the store at every ask, so a change in
    /// Settings applies to the next firing. **Nothing in the firing path may
    /// read the module-wide value directly**, or each card's switch is written
    /// and never read (`TheRingTurnsInThisTunnelsColourTests`). A name that
    /// does not say one configuration falls back to the module-wide rule.
    func notice(for kind: VPNAutomation.Kind, on name: String) -> VPNNotice {
        settings.notice(for: kind, connectionID: connectionID(named: name))
    }

    func automationSpin(on name: String) -> Bool {
        settings.automationSpin(connectionID: connectionID(named: name))
    }

    func spinTint(for kind: VPNAutomation.Kind, on name: String) -> String {
        settings.spinTint(for: kind, connectionID: connectionID(named: name))
    }

    /// Whether a banner would actually be shown.
    ///
    /// The freshest answer wins: `bannerAuthorization` is what macOS said this
    /// launch, the store only what it said some launch ago, and the permission
    /// may have gone since.
    var bannerAuthorized: Bool {
        if let heard = bannerAuthorization { return heard == .authorized }
        return settings.bannerAuthorized
    }

    /// The mode as it will actually behave, which is not always the mode that
    /// was chosen: `.system` without the permission is the menu-bar label, and
    /// anything that acts on the choice has to ask this rather than the raw one.
    ///
    /// For the firing in hand, on the configuration it happened on.
    func effectiveNotice(for kind: VPNAutomation.Kind, on name: String) -> VPNNotice {
        notice(for: kind, on: name).effective(bannerAuthorized: bannerAuthorized)
    }

    /// What macOS answered the last time it was asked this launch, by the
    /// settings page or by a firing. Nil until something asks, so the settings
    /// row says nothing about a permission that has never come up.
    @Published private(set) var bannerAuthorization: NoticeAuthorization?

    /// Whether there is any way to reach macOS's banners from here.
    ///
    /// The descriptor alone supplies the port, and a wire forgotten there would
    /// leave banners mute while every test with its own fake passed.
    /// `VPNNoticeChoiceTests` asks this.
    var reachesBanners: Bool { notices != nil }

    /// The person picked a mode on a card.
    ///
    /// Writes nothing: the card's choice is its book entry, and the module-wide
    /// `automationNotice` / `dropNotice` is not this control's to change (it
    /// says «this connection only»).
    ///
    /// The only place in this module that asks macOS for the notification
    /// permission (`NoticeChannel.tell` asks for other news), and only for the
    /// mode that needs one. macOS grants that prompt once ever, so it is not
    /// spent at launch or on a page visit.
    @discardableResult
    func choose(_ notice: VPNNotice) async -> NoticeAuthorization? {
        guard let port = notices else { return nil }
        return record(await AutomationNotice.prepare(for: notice, port: port))
    }

    /// A card's choice, for the configuration `id` alone: its book entry is
    /// written, then macOS is asked (`choose`) for the mode's permission. The
    /// kind names the setting: `.dropped` is the tunnel that fell over, anything
    /// else is the rules. Returns the book as stored, for the page to draw.
    @discardableResult
    func chooseNotice(_ notice: VPNNotice, for kind: VPNAutomation.Kind,
                      on id: String) -> VPNNoticeBook {
        let written = updateNoticeBook {
            kind == .dropped ? $0.setting(id, drop: notice) : $0.setting(id, notice: notice)
        }
        Task { await choose(notice) }
        return written
    }

    /// The one writer of the notice book: reads it fresh, applies `change`,
    /// stores and returns the result, so no caller writes a book it read at
    /// render time.
    @discardableResult
    func updateNoticeBook(_ change: (VPNNoticeBook) -> VPNNoticeBook) -> VPNNoticeBook {
        let written = change(settings.noticeBook)
        settings.setNoticeBook(written)
        return written
    }

    /// Re-reads what macOS says now, prompting nobody.
    ///
    /// The person can revoke banners in System Settings without Helm hearing,
    /// and `.system` would then post nothing on the strength of a stale yes.
    @discardableResult
    func refreshBannerAuthorization() async -> NoticeAuthorization? {
        guard let port = notices else { return nil }
        return record(await port.authorizationState())
    }

    private func record(_ answer: NoticeAuthorization) -> NoticeAuthorization {
        bannerAuthorization = answer
        settings.setBannerAuthorized(answer == .authorized)
        return answer
    }

    /// Test seam, reached only through `@testable`. It stands in for the engine
    /// that fires the rule and for the banner port.
    func setForTesting(automation: VPNAutomation?,
                       notices: AutomationNoticePort? = nil) {
        if let notices { self.notices = notices }
        if let automation { adopt(automation) } else { lastAutomation = nil }
    }

    /// Takes a firing, and gives it up again when its name window closes.
    ///
    /// The host redraws the icon only when this model publishes or a spin is
    /// running, and the name outlives the spin, so without the expiry the
    /// name would stay on the icon until an unrelated redraw.
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

    /// Nothing is asked of the engine; what it says from now on arrives on the stream.
    init(work: any VPNWork, settings: VPNSettings,
         notices: AutomationNoticePort? = nil) {
        self.work = work
        self.settings = settings
        self.notices = notices
        events = StreamFollower(work.stream(), owner: self) { $0.apply($1) }
    }

    /// Ends the event loop, which unregisters the engine's subscriber, ends the
    /// firing's expiry and announcement, and closes the doors to the engine. The
    /// host calls it through the descriptor's `stop(_:)` before the engine's
    /// `deactivate()`.
    func stop() {
        closed = true
        events?.cancel()
        expiryTask?.cancel()
        expiryTask = nil
        announcement?.cancel()
        announcement = nil
    }

    deinit { expiryTask?.cancel(); announcement?.cancel() }

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
        ruleRefusals = p.ruleRefusals
        tunnels = p.tunnels
        // **The engine says whether a run is going; this only repeats it.**
        // **The engine says whether a run is going; this only repeats it.**
        // Inferring the end from the reading fails twice: a run answering the
        // same numbers, and a refused run that never touches `speed`.
        measuring = p.tunnels.first(where: \.measuring)?.name
        // Stale firings are dropped here: the engine repeats its last firing in
        // every payload, and the first refresh after launch would otherwise
        // spin the ring for something that happened yesterday.
        if let firing = p.lastAutomation, VPNAutomation.showsName(firing, now: Date()) {
            // Asked before `adopt`, so it means "this one is new": a refresh
            // inside the name window must not post the same banner again.
            let unheard = firing != lastAutomation
            adopt(firing)
            if unheard { announce(firing) }
        }
    }

    /// The banner, in the mode that posts one.
    ///
    /// It rides the same arrival as the ring and the label: `.system` hides the
    /// menu-bar name because the banner carries it. The words are written here
    /// because `L()` is here; the engine decides whether to post.
    ///
    /// What macOS answers on the way is published, so a revoked permission
    /// turns `.system` back into the menu-bar name at the next firing, and the
    /// redraw (`statusChanges` is this model's `objectWillChange`) lands well
    /// inside the ring's three seconds. The stored mirror is left alone: it is
    /// written where the person sees it change.
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
    /// route and publishes when it does, which clears the optimistic flag
    /// (`measuring`).
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
    /// The one writer of the stored rules: saves them, and the engine re-reads
    /// them unless the model is stopped.
    func saveRules(_ rules: [String: VPNAppRule]) {
        settings.setRulesJSON(VPNRules.encode(rules))
        guard !closed else { return }
        work.reloadRules()
    }
}
