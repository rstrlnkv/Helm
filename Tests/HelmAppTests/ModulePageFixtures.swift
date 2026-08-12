import Foundation
import HelmContract
import HelmRuntime
import Module_Homebrew_Engine
import Module_Homebrew_UI
import Module_KeepAwake_Engine
import Module_Layout_Engine
import Module_Layout_UI
import Module_VPN_UI
// `@testable` for one reason: `VPNEngine.StatePayload`'s memberwise init is
// internal, the way every synthesized one is, and the wire fixture below builds
// that payload rather than hand-writing its JSON. Field names matched across a
// JSON hop by hand is the defect `VPNConnectionRef`'s own doc records.
@testable import Module_VPN_Engine

// What a module page is opened *on*, in one file: the store a person has
// configured (`Seed`) and what their engine has already said (`Wire`).
//
// Split from `ModulePageRender` because the two answer different questions. That
// file is *how* a page is drawn and measured — the window, the appearance, the
// settling — and it is the same for every module. This one is *what* each module
// is holding when it draws, and it grows a section per module. Reading either
// without the other was the shape of the defect they exist for: the harness was
// complete and the state it rendered was empty.

extension ModulePageRender {

    /// The rows a person has, for the modules whose pages hide their widest
    /// controls until something is configured.
    ///
    /// Keep Awake was the one written first, because it is the one that was
    /// measured: three shapes of control were in none of the 72 renders — the
    /// per-app rule rows, the condition pop-up each of them carries, and the
    /// battery floor's slider under its own figure. What the page drew instead was
    /// the empty state's single prominent button.
    ///
    /// **Bundle ids that resolve to nothing, on purpose.** `AppInfo.resolve` falls
    /// back to the id itself for an app this Mac does not have, so the row's name
    /// is the fixture's own string rather than a fact about what is installed —
    /// and the icon is the system's generic bundle icon rather than somebody's
    /// software. A real id would make these numbers a measurement of this machine,
    /// which is the thing the `Wire` below is careful about one section down.
    ///
    /// Two rules, not one: a list is what the page draws differently from an empty
    /// state, and the second row is where the «Add app…» line at the foot of the
    /// list appears.
    ///
    /// **VPN's half is here too, and it is only half a fixture on its own.** A
    /// rule row needs the store — the rule — *and* the wire — the connection it
    /// names: the row's two pop-ups are filled from `vm.connections`, the
    /// «holding now» mark is read off `autoConnected`, and the whole card is
    /// behind `hasConnections`. So this and `answering` are written to match, and
    /// `TheWireFixtureReachesThePagesTests` is what says they still do.
    /// A `switch`, the shape `answering` takes below: two fixtures reading one
    /// `if` and a `guard` was a line away from the second one silently shadowing
    /// the first.
    static let configured: Seed = { id, store in
        switch id {
        case KeepAwakeEngine.moduleID: configureKeepAwake(store)
        case VPNDescriptor.id.rawValue: configureVPN(store)
        default: break
        }
    }

    private static func configureKeepAwake(_ store: NamespacedStore) {
        let settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([
            AppTrigger(bundleID: "com.example.render", needsPower: true),
            AppTrigger(bundleID: "com.example.conference", needsExternalDisplay: true),
        ])
        // The two rule rows switched on, so their notes and marks are drawn as
        // well as their switches, and the mark column exists at all.
        settings.setAutoExternalDisplay(true)
        settings.setAutoPower(true)
        // The floor's own row carries the figure beside the slider, and the note
        // under it is only drawn with the guard armed.
        settings.setBatteryGuardEnabled(true)
        settings.setBatteryGuardPercent(45)
        // The interval pop-up beside «Move the pointer» is disabled until this is
        // on — a disabled control is still measured, but a page with it off is not
        // a page anybody has once they have asked for the feature.
        settings.setJiggleEnabled(true)
        settings.setJiggleIntervalMinutes(30)
        settings.setDefaultDurationMinutes(120)
    }

    /// Two per-app rules, and the second one is broken on purpose.
    ///
    /// A rule pointing at a VPN the system no longer has is the one row on that
    /// card with something to say — a warning line, and a `Picker` that has to
    /// carry the name it holds as its own entry or it draws **blank**, which is
    /// the defect the page's own comment records. It is also a state the store can
    /// be in and the wire cannot contradict: somebody renamed a configuration in
    /// System Settings.
    ///
    /// The first points at the tunnel the fixture says is up *and* auto-connected,
    /// which is what draws the «holding now» dot — both halves, because either
    /// alone would put that mark under a rule whose VPN is down.
    ///
    /// The notice mode and the spin switch are left at their shipped defaults:
    /// they are drawn either way once there are connections, and a fixture that
    /// changed them would be measuring a preference rather than a page.
    private static func configureVPN(_ store: NamespacedStore) {
        VPNSettings(store: store).setRulesJSON(VPNRules.encode([
            "com.example.render": VPNAppRule(vpnName: "Fixture Amsterdam"),
            "com.example.conference": VPNAppRule(vpnName: "Fixture Renamed In System Settings",
                                                connectOnLaunch: true,
                                                disconnectOnQuit: false),
        ]))
    }
}

// MARK: - The wire

extension ModulePageRender {

    /// What a module's own engine would have said, as a fixture.
    ///
    /// The other half of `Seed`. A page reads two things as it is built: the
    /// store, which `Seed` writes, and the wire, which is this — a table of
    /// command→reply for the pages that ask, and a list of events for the pages
    /// that are told. Three of the nine modules put their whole screen behind the
    /// second one, so against a transport that never answered the render was
    /// measuring their empty states and calling it the page.
    ///
    /// **Both spellings take the module's own enum, never a string.** A command
    /// name is a string on both sides of a transport and nothing but the enum
    /// checks that the two agree — a table keyed by a literal would answer a
    /// command the module never sends and refuse the one it does, and neither
    /// would be an error anywhere. `VPNConnectionRef`'s doc has the same story
    /// about a payload's field names.
    struct Wire {
        private(set) var replies: [String: Data] = [:]
        private(set) var events: [EngineEvent] = []

        /// The reply to one command, for a page that asks.
        mutating func answers<C: RawRepresentable, T: Encodable>(_ command: C, with value: T)
        where C.RawValue == String {
            replies[command.rawValue] = Self.json(value)
        }

        /// One event, already on the wire when the page subscribes.
        mutating func says<E: RawRepresentable, T: Encodable>(_ event: E, _ value: T)
        where E.RawValue == String {
            events.append(EngineEvent(name: event.rawValue, payload: Self.json(value)))
        }

        /// A payload that will not encode becomes an empty one, which the view
        /// model refuses and the page then draws as the state it already had —
        /// visible as a failure of `assertItDrewSomething` or of the guards in
        /// `TheWireFixtureReachesThePagesTests`, never as a quiet pass. Every
        /// value the fixtures below hand it is a `Codable` struct of strings,
        /// numbers and arrays, so the branch is unreachable today; it is written
        /// this way so the day it is reachable is a red test rather than a trap.
        private static func json<T: Encodable>(_ value: T) -> Data {
            (try? JSONEncoder().encode(value)) ?? Data()
        }
    }

    /// A module id in, the wire that module's page is opened on out.
    ///
    /// Shaped like `Seed` — one closure for the whole registry rather than a
    /// table per call site — so `pages(in:)` can pass one fixture down nine
    /// modules and a module with nothing to say costs a caller nothing.
    typealias Wiring = (String) -> Wire

    /// No module is answered anything: the harness as it was before the fixture,
    /// kept so the fixture's own effect can be measured against it.
    ///
    /// It is not a leftover. Every guard on the fixture is a comparison — «the
    /// wired page draws what the empty one cannot» — and without a way to render
    /// the empty one those guards would have nothing to subtract.
    static let unwired: Wiring = { _ in Wire() }

    /// What each module's engine says, fixed.
    ///
    /// Three modules, because three modules are the shape this exists for: a page
    /// whose whole content arrives over the wire. The other six read their store
    /// and are already measured; wiring them would be adding a fixture for a
    /// difference nobody has found.
    ///
    /// **VPN, because VPN was the module that lost a page.** On 2026-08-12 three
    /// sections went behind `!vm.connections.isEmpty` — correctly: a Mac with no
    /// VPN configured was being shown 800 pt of automation for events that cannot
    /// happen. Connections arrive as an *event*, so under a silent transport the
    /// render's VPN page became the empty state, 55 layers where it had drawn
    /// 160-odd, and the rules card, the notice cards and the spin section left
    /// every ratchet built on this render at once.
    ///
    /// Three connections rather than one, and each is a different status, because
    /// the card's verb is decided from it (`VPNCardAction`) and «what can you ask
    /// for while a tunnel is coming up» is the question that commit answered:
    /// `.connected` draws Disconnect and the ring, `.disconnected` draws the
    /// prominent Connect, `.connecting` draws a live Disconnect. Three also puts
    /// the grid at its widest column count, which is where a card is narrowest.
    ///
    /// **`lastAutomation` is nil, and that is a determinism decision.** A firing
    /// is only news for `VPNAutomation.nameDuration` seconds; the view model
    /// `adopt`s a fresh one and schedules a task to drop it when that window
    /// closes. A fixture carrying one would therefore render differently
    /// depending on how far into the window `settle` happened to be, and would
    /// spin the menu-bar ring of the test process' status item on the way past —
    /// a measurement that moves with the clock is the weather, not a gate.
    ///
    /// **`lastFailure` is set, and it is a state the engine really reaches.** A
    /// command `scutil` refused, with the connections still listed. The page draws
    /// `HelmBanner` for it — a component `RadiusLadderRatchetTests` had written
    /// down as beyond its reach, because it needs a reply.
    ///
    /// **Names that are nobody's.** Three invented tunnel names, so the widths
    /// this measures are the fixture's own string rather than a fact about what
    /// this Mac has configured — the same reason `configured` uses bundle ids
    /// that resolve to nothing.
    ///
    /// **Homebrew, because its page has two of them and this render only ever saw
    /// the poorer one.** `HomebrewSettingsPage.body` branches on
    /// `hb.status.installed`, and that status is a *reply* — so against a silent
    /// transport every reading was of the «Homebrew is not installed» screen — 12
    /// layers in both appearances, on a machine that has brew. Three replies, which
    /// are exactly the three the page asks for as it opens
    /// (`loadIfNeeded` → `refreshStatus`, `refreshInstalled`, then one `desc`
    /// batch per kind): a status, four packages, and their descriptions.
    ///
    /// **Layout, for the three rows that are the engine's and not the store's.**
    /// `conversionsToday`, the «paused by secure input» note and the last
    /// conversion all come from `LayoutState`, and the page drew none of them.
    /// Its *store* is deliberately not seeded, and the reason is sharper than the
    /// survey's: `LayoutDescriptor.makeEngine` calls `indicator.refresh()`
    /// outright, and `LanguageIndicator.refresh` builds a real `NSStatusItem` the
    /// moment it reads `indicator` = true. Writing the key straight into the
    /// backing store dodges `.helmStoreChanged` and does not dodge that — so a
    /// seeded Layout store puts a flag in the menu bar of the test run and two
    /// `DistributedNotificationCenter` observers behind it, held by a descriptor
    /// that lives as long as the process. A measurement may read this Mac; it may
    /// not decorate it.
    static let answering: Wiring = { id in
        var wire = Wire()
        switch id {
        case VPNDescriptor.id.rawValue:
            wire.says(VPNEvent.state, vpnState)
        case HomebrewDescriptor.id.rawValue:
            wire.answers(HomebrewCommand.status, with: brewStatus)
            wire.answers(HomebrewCommand.listInstalled, with: brewInstalled)
            wire.answers(HomebrewCommand.descriptions, with: brewDescriptions)
        case LayoutDescriptor.id.rawValue:
            wire.says(LayoutEvent.layoutState, layoutState)
        default:
            break
        }
        return wire
    }

    private static let vpnState = VPNEngine.StatePayload(
        connections: [
            VPNConnection(id: "fixture-1", name: "Fixture Amsterdam",
                          status: .connected, kind: "IKEv2"),
            VPNConnection(id: "fixture-2", name: "Fixture Reykjavík",
                          status: .disconnected, kind: "IPSec"),
            VPNConnection(id: "fixture-3", name: "Fixture Osaka",
                          status: .connecting, kind: "L2TP"),
        ],
        // Helm's own book of what it raised itself. The connected tunnel is in
        // it, which is what draws the «holding now» mark under a rule.
        autoConnected: ["Fixture Amsterdam"],
        defaultName: "Fixture Amsterdam",
        lastAutomation: nil,
        lastFailure: VPNFailure(name: "Fixture Reykjavík", reason: .refused, verb: .connect))

    /// A path nothing on this Mac is at, so the page's own «found at» line is the
    /// fixture's string. `/opt/homebrew` and `/usr/local` are the two real ones
    /// and either would make this a reading of the machine.
    private static let brewStatus = BrewStatus(installed: true,
                                              brewPath: "/opt/fixture/bin/brew")

    /// Four packages, and each one is a different row.
    ///
    /// A cask and a formula, because the row draws a badge for one and not the
    /// other; a package with no description in the batch below, because a row whose
    /// second line is missing is the row that reflows; and one name of 45
    /// characters, because the row was measured against a long cask name beside a
    /// German description and that is the case a ratchet should be reading rather
    /// than the comfortable one.
    private static let brewInstalled = [
        BrewPackage(name: "fixture-formula", version: "1.2.3", isCask: false),
        BrewPackage(name: "fixture-cask", version: "2026.7", isCask: true),
        BrewPackage(name: "fixture-undescribed", version: "0.1", isCask: false),
        BrewPackage(name: "fixture-with-a-deliberately-long-package-name",
                    version: "11.0.1_2", isCask: false),
    ]

    /// Keyed by bare name, which is what `brew desc` answers with and what
    /// `HomebrewViewModel.load` re-keys through `BrewKey`. One package is left
    /// out on purpose — see above.
    private static let brewDescriptions = [
        "fixture-formula": "A formula that exists only in this measurement",
        "fixture-cask": "A cask that exists only in this measurement",
        "fixture-with-a-deliberately-long-package-name":
            "A description long enough to wrap in a language that writes longer words than English",
    ]

    /// The module watching, and paused — which is three rows the page cannot
    /// otherwise draw.
    ///
    /// `suspended: true` is not the ordinary state and is deliberately the one
    /// fixtured: it is the only state that draws the «Helm is silent while secure
    /// input is on» note, and a note explaining a silence is exactly the sort of
    /// thing that regresses without a reading. `conversionsToday` puts a figure
    /// in the metric strip where the empty state puts a zero, and
    /// `lastConversion` draws the row under it.
    ///
    /// The words are invented, and the type's own doc says why that matters: a
    /// `ConversionEvent` holds what somebody typed, and a fixture is the one place
    /// it can be written down.
    private static let layoutState = LayoutState(
        enabled: true, automatic: true, suspended: true,
        lastConversion: ConversionEvent(before: "ghbdtn", after: "привет",
                                        app: "com.example.render", trailing: " "),
        conversionsToday: 17)
}

/// A transport that answers exactly what a fixture gave it, and nothing else.
///
/// **It is `LocalTransport` inside, and that is the whole design.** The class the
/// app runs on does two things a hand-rolled stand-in does not: `events`
/// broadcasts — every access is a fresh stream and `emit` fans out — and it
/// **replays** its last event per name to a subscriber that arrives late, which
/// is what a settings page always is, since the engine emits during `activate()`
/// and the page is built afterwards. A fake with one continuation and no replay
/// could not be in either of those states, so no test written against it could
/// fail the way the app can (CLAUDE.md § A fake simpler than the thing it stands
/// for). Rather than reimplement two behaviours whose absence is invisible, this
/// wraps the real one.
///
/// What it adds is a refusal. A command with no entry in the table throws, which
/// is what a module gets between its page opening and its first reply, and it is
/// what this harness did for every command before there was a fixture at all —
/// so a module nobody wired draws exactly what it drew. `LocalTransport`'s own
/// default handler answers empty `Data` instead, which is a *different* silence:
/// an empty reply decodes to nothing for JSON and to something for a raw string.
///
/// An empty `Wire` therefore is the old `SilentTransport`, and it is the same
/// object as the wired one — so a page measured both ways differs by the payload
/// and by nothing else. Two classes there would have made every comparison in
/// `TheWireFixtureReachesThePagesTests` a comparison of two transports.
final class FixtureTransport: EngineTransport, @unchecked Sendable {
    private let local = LocalTransport()

    init(_ wire: ModulePageRender.Wire) {
        let table = wire.replies
        local.setHandler { command in
            guard let reply = table[command.name] else { throw CancellationError() }
            return reply
        }
        // Emitted before anybody subscribes, on purpose: the replay is what
        // carries it to the view model the page builds a moment later, and a
        // fixture that only reached a subscriber already listening would be
        // testing a transport this app does not have.
        for event in wire.events { local.emit(event) }
    }

    func send(_ command: EngineCommand) async throws -> Data { try await local.send(command) }
    var events: AsyncStream<EngineEvent> { local.events }
    /// How many readers are listening right now — the seam that tells a live wire
    /// from a stream that finished, which draw the same page.
    var subscriberCount: Int { local.subscriberCount }
}
