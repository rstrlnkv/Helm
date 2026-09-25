import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **What `LeftoversSettingsPage` declares onto the window's own toolbar —
/// read off `HelmWindowToolbarChannel`, never off a rendered `NSToolbar`.**
///
/// `SettingsToolbar` is `HelmApp`-only (`LivePageToolbarFixture`'s own
/// header), and this module's `UITests` target cannot build one — but the
/// page's declaration itself, `HelmPageToolbarContent`, crosses no such
/// boundary: it reaches this target through the same
/// `HelmWindowToolbarChannel` `MountedRender`'s own `channel:` parameter
/// already wires in. What a live bar draws from a menu form or a capsule
/// model is `HelmApp`'s to prove (`Tests/HelmAppTests`); this file is about
/// the one fact this page owns outright — what it *says*.
@MainActor
final class TheToolbarDeclarationMatchesWhatThePageOffersTests: XCTestCase {

    /// Answers `scan` at once and holds `trash` open until released — the
    /// same fixture `OneRemovalAtATimeTests` reads at the page's construction
    /// level; this file asks the same question one layer up, of the
    /// toolbar's own declaration.
    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private(set) var trashRequests = 0
        private let released = AsyncStream<Void>.makeStream()
        let items: [StaleItem]

        init(items: [StaleItem]) { self.items = items }

        func release() { released.continuation.finish() }

        func send(_ command: EngineCommand) async throws -> Data {
            switch LeftoversCommand(rawValue: command.name) {
            case .scan:
                return (try? JSONEncoder().encode(items)) ?? Data()
            case .trash:
                trashRequests += 1
                // Hangs until `release()`. A `return` here would clear the
                // flag before the caller resumed, and the gate would be
                // untested — `OneRemovalAtATimeTests`' own note.
                for await _ in released.stream {}
                return (try? JSONEncoder().encode(
                    LeftoversRemoval(removed: [], refused: [], freedBytes: 0))) ?? Data()
            case .setDisabled, .none:
                return Data()
            }
        }
    }

    private var render: MountedRender?

    override func tearDown() {
        render?.drop()
        render = nil
        super.tearDown()
    }

    private func item(_ path: String, kind: StaleKind = .launchAgent,
                      status: ItemStatus = .orphaned) -> StaleItem {
        StaleItem(path: path, identifier: "com.acme.\(path)", kind: kind,
                  sizeBytes: 4_096, status: status)
    }

    private func declaredContent(_ channel: HelmWindowToolbarChannel) -> HelmPageToolbarContent? {
        channel.content(for: LeftoversDescriptor.id.rawValue)
    }

    private func mountPage(_ vm: ModuleViewModel, channel: HelmWindowToolbarChannel) -> MountedRender {
        let mounted = MountedRender(LeftoversSettingsPage(vm: vm), width: 900, height: 700,
                                    appearance: .aqua, channel: channel)
        mounted.settle(30)
        render = mounted
        return mounted
    }

    // MARK: - Before a scan

    /// **Nothing to filter and nothing to hide by kind — so the switcher is
    /// absent rather than dimmed, and both capsule actions are declared but
    /// hidden.** The kinds menu has no list to hide anything from, and Scan
    /// is hidden because the invitation on the page's own empty state is the
    /// one offering it (`invitationCarriesTheScan`).
    func testBeforeAScanThereAreNoTabsAndBothActionsAreHidden() async throws {
        let transport = LeftoversWire(items: [])
        let vm = ModuleViewModel(transport: transport)
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        let declared = try XCTUnwrap(declaredContent(channel))
        XCTAssertTrue(declared.tabs.isEmpty, "no list yet — the switcher must not be there at all")
        XCTAssertNil(declared.selectedTab, "no tabs, so no selection to bind")

        let kinds = try XCTUnwrap(declared.actions.first { $0.id == "kinds" })
        XCTAssertFalse(kinds.isVisible, "nothing scanned — there is no list to filter by kind")
        let scan = try XCTUnwrap(declared.actions.first { $0.id == "scan" })
        XCTAssertFalse(scan.isVisible, "the invitation's own button is the one Scan on this screen")
        mounted.settle(30)
    }

    // MARK: - With a list

    /// **The two tabs, the kinds menu checked for every `StaleKind`, and
    /// Scan reading "Scan again" — in every language.** A visible string gets
    /// one English key and eight translations (`CLAUDE.md`'s own rule), so a
    /// check of it has to run in all eight or it is a check of one. The
    /// language-independent shape (ids, which items are checked, which
    /// action is a menu) is asked once per language too, rather than split
    /// out, since a fresh mount is already being paid for.
    func testWithAListTheTabsAndKindsMenuAndRescanAreDeclared() async throws {
        let one = item("/tmp/one.plist")
        let transport = LeftoversWire(items: [one])
        let vm = ModuleViewModel(transport: transport)
        let lvm = LeftoversViewModel.shared(vm: vm)
        await lvm.scan()

        AppLanguage.each { language in
            let channel = HelmWindowToolbarChannel()
            let mounted = MountedRender(LeftoversSettingsPage(vm: vm), width: 900, height: 700,
                                        appearance: .aqua, channel: channel)
            mounted.settle(30)
            defer { mounted.drop() }
            guard let declared = self.declaredContent(channel) else {
                return XCTFail("\(language): the page declared nothing")
            }
            XCTAssertEqual(declared.tabs.map(\.id), ["onlyLeftovers", "all"], "\(language)")
            XCTAssertEqual(declared.tabs.map(\.title), [LfStr.filterLeftovers, LfStr.filterAll],
                           "\(language)")
            guard let selectedTab = declared.selectedTab else {
                return XCTFail("\(language): a list exists — there must be a tab bound")
            }
            XCTAssertEqual(selectedTab.wrappedValue, "onlyLeftovers",
                           "\(language): leftovers-only is the default filter")

            guard let kinds = declared.actions.first(where: { $0.id == "kinds" }) else {
                return XCTFail("\(language): no kinds action declared")
            }
            XCTAssertTrue(kinds.isVisible, "\(language)")
            guard case .menu(let items) = kinds.kind else {
                return XCTFail("\(language): the kinds action must be a menu, not a button or a toggle")
            }
            XCTAssertEqual(items.map(\.id), StaleKind.allCases.map(\.rawValue), "\(language)")
            XCTAssertTrue(items.allSatisfy(\.isOn),
                          "\(language): nothing is hidden yet — every kind starts checked")

            guard let scan = declared.actions.first(where: { $0.id == "scan" }) else {
                return XCTFail("\(language): no scan action declared")
            }
            XCTAssertTrue(scan.isVisible,
                          "\(language): a list exists and nothing found nothing — the toolbar carries Scan")
            XCTAssertEqual(scan.title, LfStr.rescan,
                           "\(language): a scan has already happened — the word is \"again\"")
        }
    }

    // MARK: - Busy

    /// **Scan is disabled while a removal is running** — the declaration-level
    /// twin of `OneRemovalAtATimeTests.testAScanStartedByHandWhileARemovalRunsIsRefused`:
    /// that test proves the model refuses the press, this one proves the
    /// toolbar's own button already reads dimmed before anybody presses it.
    func testScanIsDisabledWhileARemovalIsRunning() async throws {
        let one = item("/tmp/one.plist")
        let transport = HeldTransport(items: [one])
        let vm = ModuleViewModel(transport: transport)
        let lvm = LeftoversViewModel.shared(vm: vm)
        await lvm.scan()
        lvm.selected = Set(lvm.selectablePaths)
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        let removal = Task { await lvm.removeSelected() }
        for _ in 0..<200 where transport.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.trashRequests, 1, "precondition: the removal is in flight")
        mounted.settle(30)

        let declared = try XCTUnwrap(declaredContent(channel))
        let scan = try XCTUnwrap(declared.actions.first { $0.id == "scan" })
        XCTAssertFalse(scan.isEnabled, "Scan must be dimmed while a removal is running")

        transport.release()
        await removal.value
    }

    // MARK: - Choosing a kind

    /// **Choosing a kind hides it and drops its ticks** — pressing the menu
    /// item runs the same `hiddenKinds`/`dropHiddenSelections` pair the old
    /// in-page `Toggle` ran.
    func testChoosingAKindHidesItAndDropsItsTicks() async throws {
        let agent = item("/tmp/agent.plist", kind: .launchAgent)
        let daemon = item("/tmp/daemon.plist", kind: .launchDaemon)
        let transport = LeftoversWire(items: [agent, daemon])
        let vm = ModuleViewModel(transport: transport)
        let lvm = LeftoversViewModel.shared(vm: vm)
        await lvm.scan()
        lvm.selected = [daemon.path]
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var kinds = try XCTUnwrap(declared.actions.first { $0.id == "kinds" })
        guard case .menu(let items) = kinds.kind else { return XCTFail("expected a menu") }
        let daemonItem = try XCTUnwrap(items.first { $0.id == StaleKind.launchDaemon.rawValue })
        daemonItem.perform()
        mounted.settle(30)

        XCTAssertTrue(lvm.hiddenKinds.contains(.launchDaemon), "the kind must now be hidden")
        XCTAssertFalse(lvm.visibleItems.contains(daemon), "a hidden kind's rows must leave the list")
        XCTAssertTrue(lvm.selected.isEmpty, """
            the tick on the now-hidden row must be dropped — a selection nobody can see must not \
            outlive its row
            """)

        declared = try XCTUnwrap(declaredContent(channel))
        kinds = try XCTUnwrap(declared.actions.first { $0.id == "kinds" })
        guard case .menu(let itemsAfter) = kinds.kind else { return XCTFail("expected a menu") }
        let daemonAfter = try XCTUnwrap(itemsAfter.first { $0.id == StaleKind.launchDaemon.rawValue })
        XCTAssertFalse(daemonAfter.isOn, "the menu must read the kind as unchecked once it is hidden")
    }

    // MARK: - Picking "all"

    /// **Picking "all" sets `showAll` and runs `dropHiddenSelections`** — red
    /// with the `.onChange` this pass moved out of the old in-page switcher
    /// and onto the page body removed.
    func testPickingAllSetsShowAllAndDropsHiddenSelections() async throws {
        let orphan = item("/tmp/orphan.plist", status: .orphaned)
        let inUse = item("/tmp/inuse.plist", status: .inUse)
        let transport = LeftoversWire(items: [orphan, inUse])
        let vm = ModuleViewModel(transport: transport)
        let lvm = LeftoversViewModel.shared(vm: vm)
        await lvm.scan()
        XCTAssertFalse(lvm.showAll, "precondition: leftovers-only is the default filter")
        XCTAssertFalse(lvm.visibleItems.contains(inUse), "precondition: the in-use row is hidden by default")
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        let declared = try XCTUnwrap(declaredContent(channel))
        let selectedTab = try XCTUnwrap(declared.selectedTab)
        selectedTab.wrappedValue = "all"
        mounted.settle(30)

        XCTAssertTrue(lvm.showAll, "picking \"all\" must flip the status filter")
        XCTAssertTrue(lvm.visibleItems.contains(inUse), "the in-use row must now be shown")

        // Now the reverse: tick a row only "all" shows, switch back to
        // "onlyLeftovers" and the tick on a row that is no longer visible
        // must be dropped — the same guard the switcher's own `.onChange` gave.
        lvm.selected = [inUse.path]
        selectedTab.wrappedValue = "onlyLeftovers"
        mounted.settle(30)
        XCTAssertTrue(lvm.selected.isEmpty, """
            switching back to "onlyLeftovers" must drop a tick on a row the filter now hides — \
            this is what the moved `.onChange(of: lvm.showAll)` guards
            """)
    }

    // MARK: - Nothing found

    /// **A scan that found nothing draws no tabs — there is nothing to
    /// filter — and Scan stays in the toolbar**, since the found-nothing
    /// empty state offers no verb of its own (`LeftoversEmpty.invites`).
    func testAScanThatFoundNothingHasNoTabsAndKeepsScanVisible() async throws {
        let transport = LeftoversWire(items: [])
        let vm = ModuleViewModel(transport: transport)
        let lvm = LeftoversViewModel.shared(vm: vm)
        await lvm.scan()
        XCTAssertEqual(lvm.nothingToShow, .nothingFound, "precondition: the scan found nothing")
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        let declared = try XCTUnwrap(declaredContent(channel))
        XCTAssertTrue(declared.tabs.isEmpty, "nothing was found — there is nothing to filter")
        let scan = try XCTUnwrap(declared.actions.first { $0.id == "scan" })
        XCTAssertTrue(scan.isVisible, "the found-nothing screen has no verb of its own — the toolbar's Scan must stay")
        mounted.settle(30)
    }
}
