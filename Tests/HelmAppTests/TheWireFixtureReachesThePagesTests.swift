import AppKit
import HelmContract
import HelmRuntime
import Module_Autopilot_UI
import Module_Duplicates_Engine
import Module_Duplicates_UI
import Module_Homebrew_UI
import Module_Layout_UI
import Module_Leftovers_Engine
import Module_Leftovers_UI
import Module_VPN_Engine
import Module_VPN_UI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A page whose content arrives over the wire is measured by nothing until
/// the wire is fixtured.**
///
/// `ModulePageRender` grew a `seededBy:` store fixture because a page drawn
/// against an empty store draws a page nobody has. The store was only half of
/// it: three of the nine modules put their whole screen behind something the
/// *engine* sends, and against a transport that never answers those pages draw
/// their empty states. VPN made that visible on 2026-08-12 — `hasConnections`
/// put the rules, the notice cards and the spin section behind one question, and
/// the render's VPN page fell from 160-odd layers to 55, taking three cards out
/// of every ratchet built on it with no test going red.
///
/// This file is the guard on the fixture itself. Every assertion here is about
/// *structure* — did the wire arrive, is it still live, is silence still silence
/// for a module nobody wired — because the numbers it recovers live in
/// `ModulePageRender.floors` and in `LongStringGeometryRatchetTests`, and a
/// number that moves has to move in the commit that measures it.
@MainActor
final class TheWireFixtureReachesThePagesTests: XCTestCase {

    // MARK: - The fixture arrives

    /// **The wire reaches the page, and it is the three sections that came
    /// back.** Without this the fixture is a parameter nobody can see the effect
    /// of, and the ratchets go on rendering an empty state while the harness
    /// claims otherwise — the same shape as a language filtered out of its own
    /// guard, one argument along.
    ///
    /// Asserted two ways, because one of them is blind. The layer count says the
    /// page grew; the control walk says *which* control came back — VPN's «spin
    /// the icon» switch is inside `if hasConnections`, so it is drawn at zero
    /// connections in no language and on no screen. It is the only AppKit-backed
    /// control the three recovered sections carry, which is why the inventory in
    /// `LongStringGeometryRatchetTests` moved by exactly one when the gate landed.
    func testTheWiredVPNPageDrawsWhatTheEmptyOneCannot() {
        let silent = page(for: vpn, wiredBy: ModulePageRender.unwired)
        let wired = page(for: vpn, wiredBy: ModulePageRender.answering)
        // The empty state's own floor, which is the number `floors["vpn"]` carried
        // for the one commit this harness had no wire: 55 layers in light, and this
        // render names light. Asserted rather than skipped, because a comparison
        // between two pages that both drew nothing is green for ever.
        silent.assertItDrewSomething(atLeast: 45)
        wired.assertItDrewSomething()

        XCTAssertGreaterThan(wired.layers.count, silent.layers.count, """
            the wired VPN page draws \(wired.layers.count) layers against \(silent.layers.count) \
            on a transport that never answers, so the connections the fixture sends are not \
            reaching the page at all and every render taken of it is still the empty state.
            """)
        XCTAssertEqual(switches(in: silent), 0,
                       "VPN's spin toggle is behind `hasConnections`, so an unwired page has none")
        XCTAssertGreaterThanOrEqual(switches(in: wired), 1, """
            no switch is drawn on the wired VPN page, so the spin section is still missing — \
            the layer count above grew somewhere else.
            """)
    }

    /// **The rules card takes both halves, and neither alone is worth anything.**
    /// A rule row is the store's (the rule) and the wire's (the connection it
    /// names): the row's two pop-ups are filled from `vm.connections`, the «holding
    /// now» mark is read off `autoConnected`, and the whole card is behind
    /// `hasConnections`. So three renders, and the seeded-and-wired one has to beat
    /// both — a fixture where one half quietly stopped arriving would otherwise
    /// look exactly like a page that has no rules, which is the state this render
    /// spent every one of its 72 readings in.
    func testTheRulesCardNeedsTheWireAsWellAsTheStore() {
        let neither = page(for: vpn, wiredBy: ModulePageRender.unwired)
        let storeOnly = page(for: vpn, seededBy: ModulePageRender.configured,
                             wiredBy: ModulePageRender.unwired)
        let wireOnly = page(for: vpn, wiredBy: ModulePageRender.answering)
        let both = page(for: vpn, seededBy: ModulePageRender.configured,
                        wiredBy: ModulePageRender.answering)

        XCTAssertEqual(storeOnly.layers.count, neither.layers.count, """
            the store fixture alone changes VPN's page — \(storeOnly.layers.count) layers against \
            \(neither.layers.count) — and it must not: with no connections the rules card is not \
            drawn at all, so a difference here means the page is showing rules on a Mac that has \
            no VPN, which is the thing 5b675ad took out.
            """)
        XCTAssertGreaterThan(both.layers.count, wireOnly.layers.count, """
            VPN's page draws \(both.layers.count) layers with both halves of the fixture and \
            \(wireOnly.layers.count) with the wire alone, so the two rules the seed writes are \
            reaching no row — and the rules card in every render is still its empty state.
            """)
    }

    /// **Homebrew's page has two of them, and this render only ever drew the poorer
    /// one.** `HomebrewSettingsPage.body` branches on `hb.status.installed`, which
    /// arrives as a *reply* — so under a transport that never answered, every
    /// reading was of «Homebrew is not installed»: 12 layers, on a machine that has
    /// brew. The toolbar's segmented control is the sharper half of the assertion:
    /// it exists only in the manager body, so its presence *is* the branch, where
    /// the layer count is only the size.
    func testTheWiredHomebrewPageIsTheManagerAndNotTheInstallScreen() {
        let silent = page(for: homebrew, wiredBy: ModulePageRender.unwired)
        let wired = page(for: homebrew, wiredBy: ModulePageRender.answering)
        // The install screen's own measured floor — 12 layers in both appearances,
        // three runs — rather than the module's, which is now the manager's.
        silent.assertItDrewSomething(atLeast: 10)
        wired.assertItDrewSomething()

        XCTAssertGreaterThan(wired.layers.count, silent.layers.count, """
            Homebrew's page draws \(wired.layers.count) layers wired and \
            \(silent.layers.count) unwired, so the status reply is not arriving and the render is \
            still measuring the install screen of a Mac that has brew.
            """)
        XCTAssertEqual(segmentedControls(in: silent), 0,
                       "the install screen has no toolbar, so it has no segmented control")
        XCTAssertEqual(segmentedControls(in: wired), 1, """
            the wired Homebrew page draws \(segmentedControls(in: wired)) segmented controls where \
            the manager's toolbar has one — so either the toolbar is missing, which is the whole \
            second half of `LongStringGeometryRatchetTests`' recorded inventory, or there are now \
            two and that inventory is the place to say so.
            """)
    }

    /// **Layout's three engine-owned rows.** `conversionsToday`, the «paused by
    /// secure input» note and the last conversion are all read off `LayoutState`,
    /// and nothing else on that page can draw them.
    ///
    /// A comparison rather than a floor, and `ModulePageRender.floors` says why:
    /// that page also carries a permission note whose presence depends on whether
    /// the process running the suite holds Accessibility, so an absolute number in
    /// this band would be a fact about somebody's terminal. Both sides here are
    /// rendered in the same process, so the machine cancels out.
    func testTheWiredLayoutPageDrawsWhatOnlyTheEngineKnows() {
        let silent = page(for: layout, wiredBy: ModulePageRender.unwired)
        let wired = page(for: layout, wiredBy: ModulePageRender.answering)
        silent.assertItDrewSomething()
        wired.assertItDrewSomething()

        XCTAssertGreaterThan(wired.layers.count, silent.layers.count, """
            Layout's page draws \(wired.layers.count) layers wired and \(silent.layers.count) \
            unwired, so the `LayoutState` the fixture sends is reaching neither the figure in the \
            metric strip, nor the note about secure input, nor the last conversion row.
            """)
    }

    /// **Leftovers' whole page is a reply, and nothing asks for it.** `scan()` is
    /// called by no `.task` and no `onAppear`, deliberately — so a table answering
    /// `LeftoversCommand.scan` reaches a page that never asks, and the render stays
    /// on the invitation whatever the fixture holds. `ModulePageRender.Priming` is
    /// the press, and this is the guard that it lands.
    ///
    /// Three assertions about structure rather than one about size. The segmented
    /// control is the sharpest: the status filter is inside `if !lvm.items.isEmpty`,
    /// so it exists on a page with rows and on no other. The model's own state is the
    /// second — a list of the fixture's length, and a report of one moved file and
    /// two refusals, which is the row that rendered in no ratchet before this. The
    /// layer count is the loosest and is asserted as a comparison, because it is the
    /// one that moves when a row gains a badge.
    func testTheWiredLeftoversPageDrawsTheListAndTheRemovalReport() throws {
        let silent = page(for: leftovers, wiredBy: ModulePageRender.unwired)
        let wired = page(for: leftovers, wiredBy: ModulePageRender.answering)
        // A refused scan is not the invitation: the page believes it has scanned and
        // found nothing, which is the empty state without a button. **10, not the 20
        // this carried until 2026-08-14**: a page with nothing on it drew «Select
        // all», «Clear selection» and «Move to Trash» — the bar had no emptiness
        // guard where the toolbar had one — and the four controls it lost are worth
        // eight layers. Measured at 12, twice.
        silent.assertItDrewSomething(atLeast: 10)
        wired.assertItDrewSomething()

        XCTAssertEqual(segmentedControls(in: silent), 0,
                       "the status filter is behind `!items.isEmpty`, so a page with no rows "
                       + "has none")
        XCTAssertEqual(segmentedControls(in: wired), 1, """
            the wired leftovers page draws \(segmentedControls(in: wired)) segmented controls where \
            a page with rows has one — so either the scan reply is not arriving or the toolbar has \
            gained a second, and `LongStringGeometryRatchetTests`' inventory is where that is said.
            """)

        let model = LeftoversViewModel.shared(vm: wired.viewModel)
        XCTAssertTrue(model.scanned, """
            the page's own model has never scanned, so this is not the model the render drew — \
            `LeftoversViewModel.shared(vm:)` keys its cache on the view model, and a fresh one \
            here means the priming never ran.
            """)
        XCTAssertEqual(model.items.count, 7,
                       "the scan reply reached the model as \(model.items.count) rows")
        XCTAssertEqual(model.failures.count, 2, """
            the removal report is \(model.failures.count) refusals rather than two, so the row \
            above the action bar — the one the reflow in 1657762f is about — is drawn by no \
            reading of this render.
            """)
        XCTAssertEqual(model.removedCount, 1)

        XCTAssertGreaterThan(wired.layers.count, silent.layers.count + 100, """
            the wired leftovers page draws \(wired.layers.count) layers against \
            \(silent.layers.count) for a page with no rows — a list of seven rows in five \
            sections is worth about 200, so the fixture is reaching the model and not the screen.
            """)
    }

    /// **Duplicates' screen takes all three parts, and this render had none of
    /// them.** The folder is the store's (`configured` writes what `chooseFolder`
    /// would have), the findings are the wire's (`find` is a reply, and the page
    /// draws nothing it was not answered), and the search is a press (`opened`
    /// searches and then marks every extra copy, which is what fills the basket
    /// bar) — so until today the groups, the group headers and the basket bar
    /// were measured by nothing at the app level, and `floors["duplicates"]`
    /// was the empty state's 8.
    ///
    /// The model's own state is asserted before any count: `shared(vm:)` keys
    /// its cache on the view model, so a model here that never searched is not
    /// the model the render drew, and every layer number after that would be
    /// about a different page.
    func testTheWiredDuplicatesPageDrawsTheGroupsAndTheBasket() {
        let silent = page(for: duplicates, wiredBy: ModulePageRender.unwired)
        let wired = page(for: duplicates, seededBy: ModulePageRender.configured,
                         wiredBy: ModulePageRender.answering)
        // The empty state's own measured floor — what `floors["duplicates"]`
        // carried while there was no fixture.
        silent.assertItDrewSomething(atLeast: 8)
        // The whole fixture reads **228 layers, three consecutive runs, measured
        // 2026-08-15** — three groups of headers and rows, the toolbar, the
        // policy row, the excuses note and the basket bar. 200 is a group's
        // worth under that; losing any of the three parts fails it by ~220,
        // because the page without them is the empty state's 9.
        wired.assertItDrewSomething(atLeast: 200)

        let model = DuplicatesViewModel.shared(
            vm: wired.viewModel,
            store: NamespacedStore(namespace: DuplicatesEngine.moduleID,
                                   backing: InMemoryKeyValueStore()))
        XCTAssertEqual(model.phase, .result, """
            the page's own model never finished a search, so either the folder the seed \
            writes is not reaching the store the page reads, or the findings the wire \
            answers are not reaching the model — and the render below is still the \
            empty state.
            """)
        XCTAssertEqual(model.groups.count, ModulePageRender.duplicateGroups.count,
                       "the findings reached the model as \(model.groups.count) groups")
        XCTAssertEqual(model.basket.count, ModulePageRender.duplicateExtras, """
            «mark every extra copy» ticked \(model.basket.count) of \
            \(ModulePageRender.duplicateExtras) extras, so the basket bar under the list \
            is drawn by no reading of this render.
            """)
        XCTAssertGreaterThan(wired.layers.count, silent.layers.count + 100, """
            duplicates draws \(wired.layers.count) layers with the whole fixture and \
            \(silent.layers.count) empty — a list of \(ModulePageRender.duplicateGroups.count) \
            groups with headers, rows and the basket bar is worth well over a hundred, so \
            the fixture is reaching the model and not the screen.
            """)
    }

    /// And the priming is a press, not a second fixture: the same wire with nobody
    /// pressing anything draws the invitation, which is what every reading of this
    /// page was before today.
    func testWithoutThePressTheWiredLeftoversPageIsStillTheInvitation() {
        let pressed = page(for: leftovers, wiredBy: ModulePageRender.answering)
        let untouched = ModulePageRender.page(for: leftovers, in: .aqua,
                                              width: ModulePageRender.pageWidth,
                                              wiredBy: ModulePageRender.answering,
                                              primedBy: ModulePageRender.unprimed)
        // 10 for the reason the reading above says: the invitation is one button
        // now, where it used to be that button plus a second Scan in the toolbar
        // and a bar of three. Measured at 12, twice.
        untouched.assertItDrewSomething(atLeast: 10)

        XCTAssertEqual(segmentedControls(in: untouched), 0, """
            an unprimed leftovers page has \(segmentedControls(in: untouched)) segmented controls, \
            so it is holding rows — something now asks for the scan by itself, and if that is \
            deliberate the priming is what should go rather than this assertion.
            """)
        XCTAssertGreaterThan(pressed.layers.count, untouched.layers.count + 100,
                            "the press is what the fixture needs, and it changed nothing")
    }

    // MARK: - The fixture is a wire, not a value

    /// **A fake that finishes is not this port.** `LocalTransport`'s stream never
    /// ends and replays its last event per name to a subscriber that arrives
    /// late — which is exactly the case a settings page is, since the engine
    /// emits during `activate()` and the page is built afterwards. A fixture that
    /// yielded once into a stream it then closed would leave a page that happened
    /// to subscribe first looking right and every later reader empty, and no
    /// count in this file could tell the difference.
    ///
    /// Both halves asserted: the page's own subscription is still open after the
    /// render settled, and a reader that subscribes *after* everything has
    /// happened still receives the state.
    /// Waited on rather than iterated inline: a stream that has nothing to say
    /// never returns from `for await`, so the fixture failing to carry its event
    /// would hang the suite instead of failing it — and a check that hangs is
    /// read as an infrastructure problem rather than as a finding.
    func testTheWireStaysOpenAndReplaysToALateReader() {
        let wired = page(for: vpn, wiredBy: ModulePageRender.answering)
        XCTAssertGreaterThan(wired.transport.subscriberCount, 0, """
            nothing is subscribed to the fixture after the page settled — either the page never \
            listened or the stream finished, and a stream that finishes makes every later \
            reading of this harness a reading of an empty page.
            """)

        let arrived = expectation(description: "a late subscriber is handed the state")
        let reader = Task { @MainActor in
            for await event in wired.transport.events {
                XCTAssertEqual(event.name, VPNEvent.state.rawValue, """
                    a reader subscribing after the render was handed «\(event.name)» — the \
                    fixture is not replaying the state the way the transport the app runs on does.
                    """)
                arrived.fulfill()
                break
            }
        }
        wait(for: [arrived], timeout: 5)
        reader.cancel()
    }

    /// **Silence is still the default, and it is the same object saying it.** A
    /// module nobody wrote a fixture for has to draw exactly what it drew before,
    /// or every recorded number in this suite moved for a reason nobody wrote
    /// down. Autopilot is wired by nothing, so the two renders may differ by
    /// nothing.
    func testAModuleWithNoFixtureIsDrawnExactlyAsBefore() {
        let silent = page(for: autopilot, wiredBy: ModulePageRender.unwired)
        let offered = page(for: autopilot, wiredBy: ModulePageRender.answering)
        silent.assertItDrewSomething()

        XCTAssertEqual(offered.layers.count, silent.layers.count, """
            autopilot draws \(offered.layers.count) layers with the fixture table offered and \
            \(silent.layers.count) without it, and there is no fixture for that module — so the \
            wire is answering something it was never given.
            """)
    }

    /// **A command the fixture does not name is refused, not answered blank.**
    /// An empty `Data` decodes to nothing for a JSON reply and to *something* for
    /// a raw one, and the difference is a page that shows an error against a page
    /// that shows a zero. The transport this harness stands in for refuses while
    /// its engine is silent, and so does this.
    func testACommandTheFixtureDoesNotNameIsRefused() async {
        var wire = ModulePageRender.Wire()
        wire.answers(VPNCommand.refresh, with: VPNConnectionRef(name: "fixture"))
        let transport = FixtureTransport(wire)

        var refused = false
        do {
            _ = try await transport.send(EngineCommand(name: VPNCommand.connect.rawValue,
                                                       payload: Data()))
        } catch {
            refused = true
        }
        XCTAssertTrue(refused, "a command with no entry in the table was answered")

        let answered = try? await transport.send(EngineCommand(name: VPNCommand.refresh.rawValue,
                                                               payload: Data()))
        XCTAssertNotNil(answered, "the command the fixture does name was refused")
    }

    // MARK: - Plumbing

    private func page(for descriptor: any ModuleDescriptor,
                      seededBy seed: @escaping ModulePageRender.Seed = { _, _ in },
                      wiredBy wire: @escaping ModulePageRender.Wiring)
        -> ModulePageRender.Page {
        ModulePageRender.page(for: descriptor, in: .aqua, width: ModulePageRender.pageWidth,
                              seededBy: seed, wiredBy: wire)
    }

    private func switches(in page: ModulePageRender.Page) -> Int {
        page.controls.filter { $0.shortName == "AppKitSwitch" }.count
    }

    private func segmentedControls(in page: ModulePageRender.Page) -> Int {
        page.controls.filter { $0.shortName == "AppKitSegmentedControl" }.count
    }

    private func descriptor(_ id: String) -> any ModuleDescriptor {
        ModuleRegistry.all.first { $0.idRaw == id }!
    }

    private var vpn: any ModuleDescriptor { descriptor(VPNDescriptor.id.rawValue) }
    private var homebrew: any ModuleDescriptor { descriptor(HomebrewDescriptor.id.rawValue) }
    private var layout: any ModuleDescriptor { descriptor(LayoutDescriptor.id.rawValue) }
    private var duplicates: any ModuleDescriptor { descriptor(DuplicatesEngine.moduleID) }
    private var leftovers: any ModuleDescriptor { descriptor(LeftoversEngine.moduleID) }
    /// The module with no fixture, and it stands for the other three.
    private var autopilot: any ModuleDescriptor { descriptor(AutopilotDescriptor.id.rawValue) }
}
