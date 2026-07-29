import SwiftUI
import HelmContract
import HelmUI
import Module_VPN_Engine

@MainActor public final class VPNViewModel: ObservableObject {
    @Published public private(set) var connections: [VPNConnection] = []
    @Published public private(set) var autoConnected: Set<String> = []
    @Published public private(set) var defaultName: String?
    /// The last rule firing worth reacting to, or nil. Stale firings never get
    /// here — see `handle`.
    @Published public private(set) var lastAutomation: VPNAutomation?

    private let transport: EngineTransport
    private let settings: VPNSettings?
    /// What macOS is asked to post a banner through. Optional because nothing
    /// in a test may reach the real one — `UNUserNotificationCenter.current()`
    /// takes the whole run down from a process that is not a bundled app — so a
    /// view model built without a port simply never posts.
    private var notices: AutomationNoticePort?
    /// Set only by `setForTesting`; nil in the app, always.
    private var noticeForTesting: VPNNotice?
    private var bannerAuthorizedForTesting: Bool?
    private var eventsTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    /// How loudly a firing is announced. Read from the store at every ask
    /// rather than cached, so a change in Settings applies to the next firing
    /// instead of to the next launch.
    public var notice: VPNNotice { noticeForTesting ?? settings?.notice ?? .menuBar }

    /// What macOS last said about banners, as the store remembers it.
    public var bannerAuthorized: Bool {
        bannerAuthorizedForTesting ?? settings?.bannerAuthorized ?? false
    }

    /// The mode as it will actually behave, which is not always the mode that
    /// was chosen: `.system` without the permission is the menu-bar label, and
    /// anything that acts on the choice has to ask this rather than the raw one.
    public var effectiveNotice: VPNNotice {
        notice.effective(bannerAuthorized: bannerAuthorized)
    }

    /// What macOS answered the last time it was asked, this launch. Nil until
    /// something asks — the settings page shows the refusal, and only a refusal
    /// heard in front of the person is worth putting on screen.
    @Published public private(set) var bannerAuthorization: NoticeAuthorization?

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
    public func choose(_ notice: VPNNotice) async -> NoticeAuthorization? {
        settings?.setNotice(notice)
        guard let port = notices else { return nil }
        return record(await AutomationNotice.prepare(for: notice, port: port))
    }

    /// Re-reads what macOS says now, prompting nobody.
    ///
    /// The mirror is a memory of an answer, and the person can revoke banners
    /// in System Settings without Helm hearing a thing; then `.system` would
    /// post nothing and suppress the label on the strength of a stale yes.
    @discardableResult
    public func refreshBannerAuthorization() async -> NoticeAuthorization? {
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
                       bannerAuthorized: Bool = false,
                       notices: AutomationNoticePort? = nil) {
        noticeForTesting = notice
        bannerAuthorizedForTesting = bannerAuthorized
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

    public init(transport: EngineTransport, settings: VPNSettings? = nil,
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
        send("refresh")
    }

    /// Ends the event loop, which unregisters the transport subscriber.
    deinit { eventsTask?.cancel(); expiryTask?.cancel() }

    /// Re-reads the system's answer.
    ///
    /// The engine is asked once in `init` and then only after Helm itself
    /// connects or disconnects, so a tunnel raised from the macOS menu bar,
    /// from System Settings, or one that simply dropped, left this showing
    /// yesterday's state for as long as the app ran.
    public func refresh() { send("refresh") }
    /// The engine's own declaration — see the note on KeepAwake's.
    private typealias StatePayload = VPNEngine.StatePayload
    private func handle(_ e: EngineEvent) {
        guard e.name == "state",
              let p = try? JSONDecoder().decode(StatePayload.self, from: e.payload) else { return }
        connections = p.connections
        autoConnected = Set(p.autoConnected)
        defaultName = p.defaultName
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
    private func announce(_ firing: VPNAutomation) {
        guard let port = notices else { return }
        let mode = notice
        let authorized = bannerAuthorized
        let title = VPNStr.automationBannerTitle(firing.kind)
        let body = VPNStr.automationBannerBody(firing.name, kind: firing.kind)
        // Captures no `self`: a task that outlives the model must not hold it.
        Task {
            await AutomationNotice.announce(notice: mode, authorized: authorized,
                                            title: title, body: body, port: port)
        }
    }
    public func send(_ name: String, payload: Data = Data()) {
        Task { _ = try? await transport.send(EngineCommand(name: name, payload: payload)) }
    }
    public func connect(_ name: String) { send("connect", payload: nameData(name)) }
    public func disconnect(_ name: String) { send("disconnect", payload: nameData(name)) }
    public func toggleDefault() { send("toggle") }
    private func nameData(_ name: String) -> Data {
        struct P: Codable { let name: String }
        return (try? JSONEncoder().encode(P(name: name))) ?? Data()
    }
}
