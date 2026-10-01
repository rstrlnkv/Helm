import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The view model's half of sorting: the sizes and dates arrive apart from the
/// list, "not measured" is not zero, the menu is the toolbar's own flat list of
/// three, and the remembered order goes to the engine.
@MainActor
final class TheAppsAreSortedAndDatedTests: XCTestCase {

    private static let apps = [
        InstalledApp(name: "Beta", bundleID: "com.x.beta", path: "/Applications/Beta.app", sizeBytes: 0),
        InstalledApp(name: "Alpha", bundleID: "com.x.alpha", path: "/Applications/Alpha.app", sizeBytes: 5),
        InstalledApp(name: "Gamma", bundleID: "com.x.gamma", path: "/Applications/Gamma.app", sizeBytes: 900),
    ]
    private var render: MountedRender?
    override func tearDown() { render?.drop(); render = nil; super.tearDown() }

    private func model(_ wire: UninstallerWire) -> UninstallerViewModel {
        UninstallerViewModel(vm: ModuleViewModel(transport: wire))
    }

    func testTheListIsByNameAndNothingIsMeasuredUntilTheSizesArrive() async {
        let wire = UninstallerWire(apps: Self.apps)
        wire.answers(.nothing, to: .appSizes)
        let uvm = model(wire)
        await uvm.setSortOrder(.size)
        await uvm.loadAppsIfNeeded()
        XCTAssertTrue(wire.commands.contains(.appSizes), "the sizes were never asked for")
        XCTAssertTrue(uvm.measuredSizes.isEmpty)
        XCTAssertEqual(uvm.sortedApps.map(\.name), ["Alpha", "Beta", "Gamma"])
    }

    func testMeasuredSizesReorderBySizeAndZeroIsMeasuredNotAbsent() async {
        let wire = UninstallerWire(apps: [Self.apps[0], Self.apps[1], Self.apps[2]])
        let uvm = model(wire)
        await uvm.setSortOrder(.size)
        await uvm.loadAppsIfNeeded()
        // The fixture measures each app at its own `sizeBytes`: Beta at zero.
        XCTAssertEqual(uvm.measuredSizes["/Applications/Beta.app"], 0)
        XCTAssertEqual(uvm.sortedApps.map(\.name), ["Gamma", "Alpha", "Beta"])
    }

    func testDatesOrderTheListAndAnAppWithoutOneLeads() async {
        let wire = UninstallerWire(apps: Self.apps)
        wire.setOpened(["/Applications/Alpha.app": Date(timeIntervalSinceNow: -9_000),
                        "/Applications/Gamma.app": Date(timeIntervalSinceNow: -60)])
        let uvm = model(wire)
        await uvm.setSortOrder(.dateLastOpened)
        await uvm.loadAppsIfNeeded()
        XCTAssertEqual(uvm.sortedApps.map(\.name), ["Beta", "Alpha", "Gamma"])
        XCTAssertEqual(uvm.effectiveSortOrder, .dateLastOpened)
    }

    /// Spotlight answered for nobody: the stored date order is drawn as the name
    /// order, and stays stored.
    func testSpotlightSilentForEveryAppShowsTheNameOrderAndKeepsTheChoice() async {
        let wire = UninstallerWire(apps: Self.apps)
        let uvm = model(wire)
        await uvm.setSortOrder(.dateLastOpened)
        await uvm.loadAppsIfNeeded()
        XCTAssertNotNil(uvm.lastOpened, "precondition: the dates were never read")
        XCTAssertFalse(uvm.dateOrderAvailable)
        XCTAssertEqual(uvm.effectiveSortOrder, .name)
        XCTAssertEqual(uvm.sortOrder, .dateLastOpened)
        XCTAssertEqual(uvm.sortedApps.map(\.name), ["Alpha", "Beta", "Gamma"])
    }

    func testALostDatesReplyLeavesTheReadingUnknownNotEmpty() async {
        let wire = UninstallerWire(apps: Self.apps)
        wire.answers(.nothing, to: .lastOpened)
        let uvm = model(wire)
        await uvm.loadAppsIfNeeded()
        XCTAssertTrue(wire.commands.contains(.lastOpened))
        XCTAssertNil(uvm.lastOpened)
    }

    func testAChoiceIsSentToTheEngineAndReadBack() async throws {
        let wire = UninstallerWire(apps: Self.apps)
        let uvm = model(wire)
        await uvm.setSortOrder(.size)
        let sent = try XCTUnwrap(wire.payload(of: .setSortOrder))
        XCTAssertEqual(try JSONDecoder().decode(AppSortOrder.self, from: sent), .size)
        wire.setOrder(.dateLastOpened)
        await uvm.refreshSortOrder()
        XCTAssertEqual(uvm.sortOrder, .dateLastOpened)
    }

    // MARK: - The toolbar

    private func declare(_ wire: UninstallerWire) async throws -> (HelmPageToolbarContent, HelmWindowToolbarChannel) {
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let channel = HelmWindowToolbarChannel()
        let mounted = MountedRender(UninstallerSettingsPage(vm: vm), width: 900, height: 700,
                                    appearance: .aqua, channel: channel)
        mounted.settle(30)
        render = mounted
        return (try XCTUnwrap(channel.content(for: UninstallerDescriptor.id.rawValue)), channel)
    }

    /// One action, a flat menu of the three orders, the current one ticked, in
    /// the capsule left of Refresh — the Login Items filter's own shape.
    func testTheSortMenuIsTheToolbarsOwnFlatListOfThree() async throws {
        let wire = UninstallerWire(apps: Self.apps)
        wire.setOpened(["/Applications/Alpha.app": Date(timeIntervalSinceNow: -60)])
        let (content, _) = try await declare(wire)
        let ids = content.actions.map(\.id)
        XCTAssertEqual(ids, ["sort", "refresh"])
        let sort = try XCTUnwrap(content.actions.first { $0.id == "sort" })
        XCTAssertEqual(sort.title, UnStr.sortBy)
        XCTAssertTrue(sort.isVisible)
        XCTAssertTrue(sort.isEnabled)
        let items = try XCTUnwrap(menuItems(sort))
        XCTAssertEqual(items.map(\.id), ["name", "size", "dateLastOpened"])
        XCTAssertEqual(items.map(\.isOn), [true, false, false])
        XCTAssertTrue(items.allSatisfy(\.isEnabled))
    }

    func testTheDateItemIsDimmedWhenSpotlightAnsweredForNobody() async throws {
        let (content, _) = try await declare(UninstallerWire(apps: Self.apps))
        let items = try XCTUnwrap(menuItems(try XCTUnwrap(content.actions.first { $0.id == "sort" })))
        XCTAssertEqual(items.map(\.isEnabled), [true, true, false])
    }

    func testTheSortMenuIsHiddenOnTheLeftoversTab() async throws {
        let (content, channel) = try await declare(UninstallerWire(apps: Self.apps))
        try XCTUnwrap(content.selectedTab).wrappedValue = "orphans"
        render?.settle(30)
        let after = try XCTUnwrap(channel.content(for: UninstallerDescriptor.id.rawValue))
        XCTAssertFalse(try XCTUnwrap(after.actions.first { $0.id == "sort" }).isVisible)
    }

    private func menuItems(_ action: HelmToolbarAction) -> [HelmToolbarMenuItem]? {
        if case .menu(let items) = action.kind { return items }
        return nil
    }
}
