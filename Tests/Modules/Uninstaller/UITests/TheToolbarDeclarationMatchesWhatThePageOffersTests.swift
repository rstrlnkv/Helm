import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **What `UninstallerSettingsPage` declares onto the window's own toolbar —
/// read off `HelmWindowToolbarChannel`, never off a rendered `NSToolbar`.**
///
/// A module's own `UITests` target has no way to build a `SettingsToolbar` —
/// that type is `HelmApp`-only, per `LivePageToolbarFixture`'s own header —
/// but the page's declaration itself crosses no such boundary: it is
/// `HelmPageToolbarContent`, published through the same
/// `HelmWindowToolbarChannel` `MountedRender`'s own `channel:` parameter
/// already wires in. What a live bar draws from a menu form or a capsule
/// model is `HelmApp`'s to prove (`Tests/HelmAppTests`); this file is about
/// the one fact this page owns outright — what it *says*, not what AppKit
/// makes of it.
@MainActor
final class TheToolbarDeclarationMatchesWhatThePageOffersTests: XCTestCase {

    private static let apps = [
        InstalledApp(name: "Alpha", bundleID: "com.example.alpha",
                     path: "/Applications/Alpha.app", sizeBytes: 4_096),
    ]

    /// Hangs on `.listApps` until released — the fixture the "Refresh tracks
    /// loading" case needs, since `UninstallerWire` always answers at once.
    private final class HeldListApps: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private let lock = NSLock()
        private var count = 0
        var listAppsRequests: Int { lock.withLock { count } }
        private let released = AsyncStream<Void>.makeStream()

        func release() { released.continuation.finish() }

        func send(_ command: EngineCommand) async throws -> Data {
            guard UninstallerCommand(rawValue: command.name) == .listApps else { return Data() }
            lock.withLock { count += 1 }
            for await _ in released.stream {}
            return (try? JSONEncoder().encode([InstalledApp]())) ?? Data()
        }
    }

    private var render: MountedRender?

    override func tearDown() {
        render?.drop()
        render = nil
        super.tearDown()
    }

    private func declaredContent(_ channel: HelmWindowToolbarChannel) -> HelmPageToolbarContent? {
        channel.content(for: UninstallerDescriptor.id.rawValue)
    }

    private func mountPage(_ vm: ModuleViewModel, channel: HelmWindowToolbarChannel) -> MountedRender {
        let mounted = MountedRender(UninstallerSettingsPage(vm: vm), width: 900, height: 700,
                                    appearance: .aqua, channel: channel)
        mounted.settle(30)
        render = mounted
        return mounted
    }

    // MARK: - Tabs

    /// **The two tabs, in the order the switcher shows them, carrying the
    /// module's own strings — in every language.** A visible string gets one
    /// English key and eight translations (`CLAUDE.md`'s own rule), so a
    /// check of it has to run in all eight or it is a check of one.
    func testTheTwoTabsCarryTheirOwnIdsAndTitlesInEveryLanguage() async {
        let wire = UninstallerWire(apps: Self.apps, answering: .reply)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()

        AppLanguage.each { language in
            let channel = HelmWindowToolbarChannel()
            let mounted = MountedRender(UninstallerSettingsPage(vm: vm), width: 900, height: 700,
                                        appearance: .aqua, channel: channel)
            mounted.settle(30)
            defer { mounted.drop() }
            guard let declared = declaredContent(channel) else {
                XCTFail("\(language): the page declared nothing")
                return
            }
            XCTAssertEqual(declared.tabs.map(\.id), ["apps", "orphans"], "\(language)")
            XCTAssertEqual(declared.tabs.map(\.title), [UnStr.tabApps, UnStr.tabOrphans], "\(language)")
        }
    }

    /// **Dims rather than disables per tab, and only during review** —
    /// switching tabs mid-review would abandon it, and `HelmPageToolbarContent`
    /// has no way to disable one tab and leave the other live.
    func testTabsEnabledIsFalseOnlyDuringReview() async throws {
        let wire = UninstallerWire(apps: Self.apps, answering: .reply)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        XCTAssertTrue(declared.tabsEnabled, "the switcher must not start out dimmed, on the pick step")

        uvm.setChecked(Self.apps[0].bundleID, true)
        await uvm.prepareReview()
        XCTAssertEqual(uvm.step, .review, "precondition: the scan did not reach the review step")
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        XCTAssertFalse(declared.tabsEnabled, "the switcher still reads enabled while a removal is under review")
    }

    // MARK: - Refresh

    /// **On the Apps tab, off Leftovers** — Orphans has its own scan and its
    /// own Rescan button, so a Refresh there would spin an icon and change
    /// nothing anybody could see.
    func testRefreshIsVisibleOnAppsAndHiddenOnOrphans() async throws {
        let wire = UninstallerWire(apps: Self.apps, answering: .reply)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var refresh = try XCTUnwrap(declared.actions.first { $0.id == "refresh" })
        XCTAssertTrue(refresh.isVisible, "Refresh must show on the Apps tab")

        let selectedTab = try XCTUnwrap(declared.selectedTab, "no tab binding to switch with")
        selectedTab.wrappedValue = "orphans"
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        refresh = try XCTUnwrap(declared.actions.first { $0.id == "refresh" })
        XCTAssertFalse(refresh.isVisible, "Refresh must not show on the Leftovers tab")
    }

    /// **`isEnabled == !loading` and `isBusy == loading`, read while a real
    /// request is actually out** — not inferred from the code, measured with
    /// a transport that will not answer until told to.
    func testRefreshTracksLoadingWithAHeldTransport() async throws {
        let transport = HeldListApps()
        let vm = ModuleViewModel(transport: transport)
        let uvm = UninstallerViewModel.shared(vm: vm)

        let loadTask = Task { await uvm.loadAppsIfNeeded() }
        for _ in 0..<200 where transport.listAppsRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.listAppsRequests, 1, "precondition: the list request never reached the transport")
        XCTAssertTrue(uvm.loadingApps, "precondition: the view model does not think it is loading")

        let channel = HelmWindowToolbarChannel()
        let mounted = mountPage(vm, channel: channel)

        var declared = try XCTUnwrap(declaredContent(channel))
        var refresh = try XCTUnwrap(declared.actions.first { $0.id == "refresh" })
        XCTAssertEqual(refresh.isEnabled, false, "Refresh must be dimmed while the list is loading")
        XCTAssertEqual(refresh.isBusy, true, "Refresh must spin while the list is loading")

        transport.release()
        await loadTask.value
        mounted.settle(30)

        declared = try XCTUnwrap(declaredContent(channel))
        refresh = try XCTUnwrap(declared.actions.first { $0.id == "refresh" })
        XCTAssertEqual(refresh.isEnabled, true, "Refresh stayed dimmed after the list answered")
        XCTAssertEqual(refresh.isBusy, false, "Refresh kept spinning after the list answered")
    }

    // MARK: - Search

    /// **The prompt is the page's own string, and there is no `onSubmit`** —
    /// the term filters the Apps list live, on every keystroke, exactly as it
    /// did through `.helmSearchable` before, so a Return that also asked
    /// again would be a second, redundant way to do the same thing.
    func testTheSearchPromptHasNoOnSubmitInEveryLanguage() async {
        let wire = UninstallerWire(apps: Self.apps, answering: .reply)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()

        AppLanguage.each { language in
            let channel = HelmWindowToolbarChannel()
            let mounted = MountedRender(UninstallerSettingsPage(vm: vm), width: 900, height: 700,
                                        appearance: .aqua, channel: channel)
            mounted.settle(30)
            defer { mounted.drop() }
            guard let declared = declaredContent(channel) else {
                XCTFail("\(language): the page declared nothing")
                return
            }
            XCTAssertEqual(declared.search?.prompt, UnStr.searchApps, "\(language)")
            XCTAssertNil(declared.search?.onSubmit, """
                \(language): the field must only filter live — an `onSubmit` here would ask a \
                second, redundant way to do what every keystroke already does
                """)
        }
    }
}
