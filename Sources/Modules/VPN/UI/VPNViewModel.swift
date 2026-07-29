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
    /// Set only by `setForTesting`; nil in the app, always.
    private var noticeForTesting: VPNNotice?
    private var eventsTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    /// How loudly a firing is announced. Read from the store at every ask
    /// rather than cached, so a change in Settings applies to the next firing
    /// instead of to the next launch.
    public var notice: VPNNotice { noticeForTesting ?? settings?.notice ?? .menuBar }

    /// Test seam. `@testable` reaches it; nothing in the app does. It stands in
    /// for the engine that fires the rule and for the store that holds the mode,
    /// neither of which a test of the status item wants to own.
    func setForTesting(automation: VPNAutomation?, notice: VPNNotice) {
        noticeForTesting = notice
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

    public init(transport: EngineTransport, settings: VPNSettings? = nil) {
        self.transport = transport
        self.settings = settings
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
            adopt(firing)
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
