import SwiftUI
import HelmContract
import HelmUI
import Module_VPN_Engine

@MainActor final class VPNViewModel: ObservableObject {
    @Published private(set) var connections: [VPNConnection] = []
    @Published private(set) var autoConnected: Set<String> = []
    @Published private(set) var defaultName: String?
    /// The last rule firing worth reacting to, or nil. Stale firings never get
    /// here — see `handle`.
    @Published private(set) var lastAutomation: VPNAutomation?
    /// The last command `scutil` did not accept, cleared by the next one it
    /// did. The engine has published this since it learned to read the tool's
    /// output; nothing here decoded it, so pressing Connect on a configuration
    /// macOS refuses ran the spinner and returned the card exactly as it was.
    @Published private(set) var lastFailure: VPNFailure?

    private let transport: EngineTransport
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
    private var spinTintsForTesting: [VPNAutomation.Kind: String]?
    private var eventsTask: Task<Void, Never>?
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
    func notice(for kind: VPNAutomation.Kind) -> VPNNotice {
        if let forced = kind == .dropped ? dropNoticeForTesting : noticeForTesting { return forced }
        if let forced = noticeForTesting { return forced }
        return settings?.notice(for: kind) ?? .menuBar
    }

    /// Whether the menu-bar ring turns when a rule fires. Read at every ask
    /// rather than cached, like `notice`, so a change in Settings applies to
    /// the next firing instead of to the next launch.
    var automationSpin: Bool {
        spinForTesting ?? settings?.automationSpin ?? false
    }

    /// The colour that firing turns in.
    func spinTint(for kind: VPNAutomation.Kind) -> String {
        spinTintsForTesting?[kind]
            ?? settings?.spinTint(for: kind)
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
                       spin: Bool = false,
                       spinTints: [VPNAutomation.Kind: String]? = nil) {
        noticeForTesting = notice
        dropNoticeForTesting = dropNotice
        bannerAuthorizedForTesting = bannerAuthorized
        spinForTesting = spin
        spinTintsForTesting = spinTints
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

    init(transport: EngineTransport, settings: VPNSettings? = nil,
         notices: AutomationNoticePort? = nil) {
        self.transport = transport
        self.settings = settings
        self.notices = notices
        let events = transport.events
        eventsTask = Task { [weak self] in
            for await e in events {
                guard let self else { break }
                self.handle(e)
            }
        }
        // Ask the engine to publish current state.
        send(VPNCommand.refresh)
    }

    /// Ends the event loop, which unregisters the transport subscriber.
    deinit { eventsTask?.cancel(); expiryTask?.cancel(); announcement?.cancel() }

    /// Re-reads the system's answer.
    ///
    /// The engine is asked once in `init` and then only after Helm itself
    /// connects or disconnects, so a tunnel raised from the macOS menu bar,
    /// from System Settings, or one that simply dropped, left this showing
    /// yesterday's state for as long as the app ran.
    func refresh() { send(VPNCommand.refresh) }
    /// The engine's own declaration — see the note on KeepAwake's.
    private typealias StatePayload = VPNEngine.StatePayload
    private func handle(_ e: EngineEvent) {
        guard VPNEvent(rawValue: e.name) == .state,
              let p = try? JSONDecoder().decode(StatePayload.self, from: e.payload) else { return }
        connections = p.connections
        autoConnected = Set(p.autoConnected)
        defaultName = p.defaultName
        lastFailure = p.lastFailure
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
        let mode = notice(for: firing.kind)
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
    /// Named by the engine's own enum, which is what every call site uses.
    ///
    /// The `send(_ name: String, …)` this forwarded to was public, and nothing
    /// outside called it — a door back to the string spelling the enum exists
    /// to close, held open for a caller that never arrived.
    func send(_ command: VPNCommand, payload: Data = Data()) {
        Task { [transport] in
            _ = try? await transport.send(EngineCommand(name: command.rawValue,
                                                        payload: payload))
        }
    }
    func connect(_ name: String) { send(VPNCommand.connect, payload: nameData(name)) }
    func disconnect(_ name: String) { send(VPNCommand.disconnect, payload: nameData(name)) }
    /// The engine's own type — it was declared again here, inside this
    /// function, matched to the other by field name across a JSON hop.
    private func nameData(_ name: String) -> Data {
        (try? JSONEncoder().encode(VPNConnectionRef(name: name))) ?? Data()
    }
}
