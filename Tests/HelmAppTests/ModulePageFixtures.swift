import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import Module_Duplicates_UI
import Module_Homebrew_Engine
import Module_Homebrew_UI
import Module_KeepAwake_Engine
import Module_Layout_Engine
import Module_Layout_UI
import Module_Leftovers_Engine
import Module_Leftovers_UI
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
        case DuplicatesEngine.moduleID: configureDuplicates(store)
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

    /// The folder a person has already chosen — what `chooseFolder` writes when
    /// the open panel closes, minus the panel.
    ///
    /// **The seal is deliberately not written.** It exists for the background
    /// scan, which reads this value with nobody at the desk; the page reads the
    /// folder plain, and a fixture that sealed it would need a keychain to seal
    /// it *with* — the person's own, which is the machine boundary every fixture
    /// in this file stays inside.
    private static func configureDuplicates(_ store: NamespacedStore) {
        store.set(duplicatesFolder, for: "folder")
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
    /// Five modules, because five modules are the shape this exists for: a page
    /// whose whole content arrives over the wire. The other four read their
    /// store and are already measured; wiring them would be adding a fixture for
    /// a difference nobody has found.
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
    ///
    /// **Leftovers, because its page is a list and the render had never drawn one.**
    /// Everything on that screen is the answer to `LeftoversCommand.scan`, and
    /// nothing asks for it by itself, so the render measured the invitation: 28
    /// layers against 224/229 for a page with rows, and the bottom bar's report of
    /// a partly-failed removal rendered in no ratchet at all. Two replies, because
    /// the screen has two states worth measuring and the second is only reachable
    /// through the first — a scan, and then the removal the page's own button
    /// sends. `opened` below is what presses them.
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
        case LeftoversEngine.moduleID:
            wire.answers(LeftoversCommand.scan, with: leftovers)
            wire.answers(LeftoversCommand.trash, with: leftoversRemoval)
        case DuplicatesEngine.moduleID:
            wire.answers(DuplicatesCommand.find, with: duplicateFindings)
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
        lastConversionUndone: false,
        conversionsToday: 17)

    // MARK: - Leftovers

    /// A home nobody has, so no path here can be a fact about this Mac.
    ///
    /// The identifiers are `com.example.*` and `systemgroup.com.example.*` —
    /// reserved for documentation, resolving to nothing, and the same care
    /// `configured` takes with bundle ids one section up. Nothing in this module's
    /// page resolves an identifier or reads a path (the row draws both as text), so
    /// what a real id would buy is a render that differs between Macs.
    private static let fixtureHome = "/Users/fixture"

    /// Seven rows: **all five `StaleKind`s, all three `ItemStatus`, one folder Helm
    /// cannot write in, one item launchd has switched off, and one job pointing at a
    /// file that is gone.**
    ///
    /// Every one of those changes what a row draws, and none of them was in any
    /// reading of this render:
    ///   • the two `.launchAgent`s carry the switch, and the second carries the
    ///     «Disabled» badge in place of a status badge and «Turn on» in place of
    ///     «Turn off»;
    ///   • the `.launchDaemon` is `writable: false`, which is the row with no
    ///     checkbox, no switch and «Needs an administrator to delete» in its menu —
    ///     the sentence 4c8bbed9 split in two;
    ///   • the protected `.preference` is the other half of that split, «Protected
    ///     by macOS», and the row whose name is drawn in `HelmText.quiet`;
    ///   • the `.plugin` is megabytes rather than kilobytes, so the figure column is
    ///     measured at the width a real one takes;
    ///   • the `.systemExtension` draws «Manage…» instead of a size and a menu, and
    ///     its path *is* its identifier, which is why its row has no second line;
    ///   • the first row's `missingTarget` is the long detail line — a path and a
    ///     sentence about another path — which is the case the row's truncation rule
    ///     was written for and the one that made the list carry three row heights.
    ///
    /// Sizes are spread across three orders of magnitude on purpose: the bar under
    /// the list adds them up, and a selection of three 4 KB files measures the
    /// narrowest figure that bar can be asked to draw.
    private static let leftovers = [
        StaleItem(path: "\(fixtureHome)/Library/LaunchAgents/com.example.render.updater.plist",
                  identifier: "com.example.render.updater", kind: .launchAgent, sizeBytes: 4_096,
                  missingTarget: "/Applications/Fixture Render.app/Contents/MacOS/updater",
                  runAtLoad: true, status: .orphaned),
        StaleItem(path: "\(fixtureHome)/Library/LaunchAgents/com.example.conference.helper.plist",
                  identifier: "com.example.conference.helper", kind: .launchAgent,
                  sizeBytes: 8_192, runAtLoad: true, status: .inUse, disabled: true),
        // Root's folder: the row that may be neither ticked nor switched, and says why.
        StaleItem(path: "/Library/LaunchDaemons/com.example.render.privileged.plist",
                  identifier: "com.example.render.privileged", kind: .launchDaemon,
                  sizeBytes: 12_288, runAtLoad: true, status: .orphaned, writable: false),
        StaleItem(path: "\(fixtureHome)/Library/Preferences/com.example.render.plist",
                  identifier: "com.example.render", kind: .preference, sizeBytes: 24_576),
        // A namespace `StaleItemRules` protects, rather than one of Apple's: the
        // status is the fixture's to state, and borrowing `com.apple.` for it would
        // be a fixture naming somebody else's software to get a badge drawn.
        StaleItem(path: "\(fixtureHome)/Library/Preferences/systemgroup.com.example.shared.plist",
                  identifier: "systemgroup.com.example.shared", kind: .preference,
                  sizeBytes: 6_144, status: .protectedItem),
        StaleItem(path: "\(fixtureHome)/Library/QuickLook/Fixture Preview.qlgenerator",
                  identifier: "com.example.render.quicklook", kind: .plugin,
                  sizeBytes: 3_356_672),
        // The scan gives an extension its identifier as its path, and the row is
        // read back off that — `LfStr.detail` returns nil for this kind.
        StaleItem(path: "com.example.conference.networkextension",
                  identifier: "com.example.conference.networkextension", kind: .systemExtension,
                  sizeBytes: 0, runAtLoad: true, status: .orphaned),
    ]

    /// One file moved and two refused — **the only shape that draws the report at
    /// all**, and the row the survey measured at 48 → 115 pt (en) / 156 (ru) / 184
    /// (de) before it was lifted out of the button row.
    ///
    /// `HelmRemovalOutcome.verdict` is `.failed` only with a refusal in it and
    /// `.silent` with neither, so a fixture of a clean removal would draw one quiet
    /// sentence and a fixture of nothing would draw `EmptyView` — the state every
    /// reading of this page was already in.
    ///
    /// **It is an answer to a batch that was really sent.** `opened` builds the
    /// selection *from this value*, so the three paths the page ticks are the three
    /// this reply is about: a removal naming a path nobody asked to remove is a state
    /// `HelmTrash.remove` cannot produce, and a fixture free to plant it would be
    /// proving the page against an impossible round (CLAUDE.md § A fake can also be
    /// freer than the port).
    ///
    /// The two reasons are the two a person can act on and the two the row can
    /// carry: `needsFullDiskAccess` is what puts the «Open Settings» button in the
    /// report when the grant is withheld, and `noPermission` is the one that names a
    /// folder rather than a setting.
    ///
    /// The settings file it did move is still in the scan above, and that is not a
    /// contradiction: this module's own confirmation says so — «the app that
    /// installed it may put it back» — and a preferences file is the case that
    /// happens to. What the page must not do is claim the *list* changed, which is
    /// why the rescan after a removal answers the same seven rows.
    private static let leftoversRemoval = LeftoversRemoval(
        removed: [leftovers[3].path],
        refused: [HelmTrash.Refusal(path: leftovers[0].path, reason: .needsFullDiskAccess),
                  HelmTrash.Refusal(path: leftovers[5].path, reason: .noPermission)],
        freedBytes: 24_576)

    /// The two presses this page needs before it holds anything: **Scan, then Move
    /// to Trash.**
    ///
    /// Through the model's own calls, in the order a person makes them: `scan()`
    /// sets `scanned`, drops the ticks a rescan invalidates and takes a
    /// `LatestRequest` token; `removeSelected()` runs the busy gate, writes the
    /// report and rescans behind it. Assigning `items` or `failures` instead would
    /// fixture a state the module cannot reach, and the whole point of this render
    /// is the page somebody is actually looking at. `selected` **is** written
    /// directly, because that is the view's own write path — the row's checkbox
    /// binding and «Select all» both set exactly this property.
    ///
    /// `LeftoversViewModel.shared(vm:)` is the seam because it is what the page's own
    /// `init` calls — keyed to this `ModuleViewModel`, so this is the same object the
    /// page draws and not a second one beside it.
    static let opened: Priming = { id, vm in
        switch id {
        case LeftoversEngine.moduleID:
            return { @MainActor in
                let lvm = LeftoversViewModel.shared(vm: vm)
                await lvm.scan()
                // Exactly the batch `leftoversRemoval` answers, read off that value
                // rather than written out again beside it.
                lvm.selected = Set(leftoversRemoval.removed
                    + leftoversRemoval.refused.map(\.path))
                await lvm.removeSelected()
            }
        case DuplicatesEngine.moduleID:
            return { @MainActor in await openDuplicates(vm) }
        default:
            return nil
        }
    }

    // MARK: - Duplicates

    /// The two presses this page needs before it holds anything: **Search, then
    /// Mark every extra copy.**
    ///
    /// Through the model's own calls, like the leftovers press above: `search()`
    /// is the button, and the loop after it is `settle`'s job done early — the
    /// reply changes the tree, so the marking must land on the page that holds
    /// it. `basketAllExtras()` is what fills the basket bar, and it goes through
    /// the same scope gate the per-group button uses, so the count the bar draws
    /// is one the engine would honour.
    ///
    /// `DuplicatesViewModel.shared(vm:store:)` is the seam because it is what the
    /// page's own `init` calls — keyed to this `ModuleViewModel`, so this is the
    /// same object the page draws. The store handed here is only read on a cache
    /// miss, which is a page that was never built; its model then has no folder
    /// and the guard below makes the press a no-op — the unseeded render, where
    /// the empty state is exactly what should be measured.
    @MainActor private static func openDuplicates(_ vm: ModuleViewModel) async {
        let dvm = DuplicatesViewModel.shared(
            vm: vm, store: NamespacedStore(namespace: DuplicatesEngine.moduleID,
                                           backing: InMemoryKeyValueStore()))
        // No folder, no search to press: the unseeded page draws its start
        // screen, and pressing anything on it would be fixturing a state the
        // module cannot reach.
        guard dvm.folder != nil else { return }
        dvm.search()
        for _ in 0..<20_000 where dvm.phase == .searching { await Task.yield() }
        dvm.basketAllExtras()
    }

    /// A folder nobody has, the `fixtureHome` rule one section down: the page
    /// draws the path as text and the wire answers the search, so nothing here
    /// reads this Mac.
    static let duplicatesFolder = "/Users/fixture/Documents"

    /// Three groups, and each is a different row.
    ///
    /// A plain pair, because that is the module's ordinary case and it carries
    /// the group header's figure; a trio with a deliberately long name, because
    /// the row was measured against names that wrap and a comfortable fixture
    /// measures nothing; and an APFS clone pair — same `cloneFamily` — because
    /// its header is the one that says removing the copy frees *nothing*, which
    /// is the arithmetic `TheGroupHeaderSaysWhatItIsWorthTests` pins one target
    /// over and this render had never drawn.
    ///
    /// Dates are fixed, not `Date()`: the survivor is decided by «date added»,
    /// and a fixture that moved with the clock would re-decide it on some
    /// future afternoon. Each group's first copy is the one that stays —
    /// `SurvivingCopy`'s order, which is how the engine answers.
    static let duplicateGroups = [
        DuplicateGroup(copies: [
            .init(path: "\(duplicatesFolder)/Reports/statement-2025.pdf",
                  bytes: 9_000_000, added: Date(timeIntervalSinceReferenceDate: 700_000_000)),
            .init(path: "\(duplicatesFolder)/Archive/statement-2025.pdf",
                  bytes: 9_000_000, added: Date(timeIntervalSinceReferenceDate: 760_000_000)),
        ]),
        DuplicateGroup(copies: [
            .init(path: "\(duplicatesFolder)/Camera/a-deliberately-long-fixture-photo-export-name.heic",
                  bytes: 3_400_000, added: Date(timeIntervalSinceReferenceDate: 710_000_000)),
            .init(path: "\(duplicatesFolder)/Shared/a-deliberately-long-fixture-photo-export-name.heic",
                  bytes: 3_400_000, added: Date(timeIntervalSinceReferenceDate: 720_000_000)),
            .init(path: "\(duplicatesFolder)/Backup/a-deliberately-long-fixture-photo-export-name.heic",
                  bytes: 3_400_000, added: Date(timeIntervalSinceReferenceDate: 730_000_000)),
        ]),
        DuplicateGroup(copies: [
            .init(path: "\(duplicatesFolder)/Cuts/interview.mov", bytes: 48_000_000,
                  cloneFamily: 42, added: Date(timeIntervalSinceReferenceDate: 705_000_000)),
            .init(path: "\(duplicatesFolder)/Cuts/interview copy.mov", bytes: 48_000_000,
                  cloneFamily: 42, added: Date(timeIntervalSinceReferenceDate: 706_000_000)),
        ]),
    ]

    /// Every copy after each group's first — what «Mark every extra copy» may
    /// tick, read off the groups rather than counted by hand beside them. All
    /// the fixture's paths pass `UserFileScope`, so the count the bar draws is
    /// the whole set.
    static var duplicateExtras: Int {
        duplicateGroups.reduce(0) { $0 + $1.copies.count - 1 }
    }

    /// The counts travel with the groups, because the page draws them as one
    /// answer: the excuses note under the toolbar — three files the walk could
    /// not compare, one application library stepped over — was behind a reply
    /// nothing answered, like everything else on this screen.
    private static let duplicateFindings = DuplicateFindings(
        groups: duplicateGroups, unreadable: 3, librariesSkipped: 1)
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
