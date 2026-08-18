import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import Module_Disk_UI
import Module_Duplicates_UI
import Module_Homebrew_UI
import Module_KeepAwake_UI
import Module_Layout_UI
import Module_Leftovers_UI
import Module_Uninstaller_UI
// `@testable` for the same reason VPN needs it below, one line down from the
// same door: `HostsViewModel` and its `shared(vm:)` are internal to the
// module's UI target.
@testable import Module_Hosts_UI
// `@testable` for one reason: `VPNDescriptor.viewModel(_:)` is internal, and it
// is the only door to VPN's cache — the module keys its instance on the
// descriptor rather than on a static, so `shared(vm:)`'s question has to be
// asked through the descriptor here.
@testable import Module_VPN_UI

/// Switching a module off must give its transport subscriber back.
///
/// A module that caches its view model across page teardown registers with
/// `ModuleUICache.dropWhenDisabled`, and every one of those closures releases
/// the instance and nothing else. Whether that is enough is not a question the
/// closure answers: the view model's event loop is a `Task` over
/// `LocalTransport.events`, the stream nothing ever calls `finish()` on, and
/// the *only* thing that prunes `subscribers` is `continuation.onTermination`
/// — which fires when that task is cancelled. Cancelling is `deinit`'s job, and
/// `deinit` can only run if the task does not hold the object it belongs to.
///
/// So the drop is sound exactly when the loop was written to re-acquire `self`
/// per event (`for await … { guard let self else { break } }`) and inert when it
/// was written as `await self?.observeEvents()`, which resolves the weak capture
/// once and then holds `self` for a call that never returns. Both shapes compile,
/// both look right, and the difference is invisible from every screen in the app.
///
/// `SubscriberPruningTests` already pins that shape in the abstract — a
/// hand-rolled task over a bare `LocalTransport`. What it cannot see is whether
/// the modules use it, or whether the notification that drops a cache reaches
/// them at all. This asks the real `shared(vm:)` of every caching module, over
/// the real notification `ModuleHost.disable` posts, and reads the count that a
/// leak makes climb.
///
/// **The count is asserted at 1 before it is asserted at 0.** A subscriber that
/// never registered would pass an assertion about its absence, which is the
/// vacuous shape CLAUDE.md names: assert first that the thing happened. That
/// alone was not enough — the subscriber registers before the loop that consumes
/// it runs at all, so the gate stood open on a module that had not started;
/// `letTheLoopStart()` below has the measurement.
@MainActor
final class ASwitchedOffModuleLetsItsSubscriberGoTests: XCTestCase {

    // MARK: - The modules

    /// One entry per module that caches a view model **and** subscribes to
    /// events. `build` deliberately returns nothing: the point of the check is
    /// that the module's own cache is the last strong reference, so the test
    /// must not become one itself.
    private struct Cached {
        let module: String
        let id: String
        let build: @MainActor (ModuleViewModel) -> Void
    }

    /// Held for the whole check: VPN keeps its cached model on the descriptor
    /// and its drop closure captures the descriptor weakly, so a descriptor
    /// nobody holds takes the cache with it and the notification would be
    /// dropping something already gone.
    private let vpn = VPNDescriptor()

    private var subscribing: [Cached] {
        [
            Cached(module: "Disk", id: DiskDescriptor.id.rawValue) {
                _ = DiskViewModel.shared(vm: $0)
            },
            Cached(module: "Duplicates", id: DuplicatesDescriptor.id.rawValue) {
                // Both ports named. The store is in memory because a test leaves
                // nothing behind, and `settings:` is a double because its
                // production default is the login keychain — `init` reads the
                // keep policy, and an empty store spends `establishKey()` on the
                // way out.
                _ = DuplicatesViewModel.shared(
                    vm: $0,
                    store: NamespacedStore(namespace: "test.duplicates.subscriber",
                                           backing: InMemoryKeyValueStore()),
                    settings: SettingGuard(keys: SealKeyProbe()))
            },
            Cached(module: "Homebrew", id: HomebrewDescriptor.id.rawValue) {
                _ = HomebrewViewModel.shared(vm: $0)
            },
            Cached(module: "Hosts", id: HostsDescriptor.id.rawValue) {
                _ = HostsViewModel.shared(vm: $0)
            },
            Cached(module: "KeepAwake", id: KeepAwakeDescriptor.id.rawValue) {
                _ = KeepAwakeViewModel.shared(vm: $0)
            },
            Cached(module: "Layout", id: LayoutDescriptor.id.rawValue) {
                _ = LayoutViewModel.shared(vm: $0)
            },
            Cached(module: "VPN", id: VPNDescriptor.id.rawValue) { [vpn] in
                _ = vpn.viewModel($0)
            },
        ]
    }

    /// Modules that cache a view model and consume no events at all, so there is
    /// no subscriber for switching them off to give back. They are named rather
    /// than omitted: the coverage check below reads this list, so a module that
    /// grows an event loop later has to be moved rather than forgotten.
    private let holdingNoSubscriber = ["Leftovers", "Uninstaller"]

    // MARK: - The rule

    func testEveryCachingModuleGivesItsSubscriberBackWhenSwitchedOff() async {
        for module in subscribing {
            let transport = LocalTransport()
            let vm = ModuleViewModel(transport: transport)
            module.build(vm)

            await settle(transport, until: 1)
            XCTAssertEqual(transport.subscriberCount, 1, """
                \(module.module) never registered a subscriber, so the assertion below would \
                pass on a module that had done nothing — if this module has stopped consuming \
                events, move it to `holdingNoSubscriber`; if it has not, the event task is not \
                starting and every event this module draws is being missed.
                """)
            await letTheLoopStart()

            NotificationCenter.default.post(name: .helmModuleDisabled, object: module.id)
            await settle(transport, until: 0)

            XCTAssertEqual(transport.subscriberCount, 0, """
                \(module.module) kept its transport subscriber after the module was switched \
                off. Its `ModuleUICache.dropWhenDisabled` closure released the cached view \
                model and the view model outlived the release, so `deinit` never ran and \
                `eventsTask?.cancel()` never fired — the loop is holding the object it belongs \
                to. That is the shape `Task { [weak self] in await self?.observe() }` produces: \
                the weak capture is resolved once and the call it makes never returns. Write the \
                loop as `for await … { guard let self else { break } }` over a stream captured \
                before the task, or give the model a `stop()` the drop closure calls.
                """)
        }
    }

    /// A module that starts caching its view model arrives in the table above,
    /// or the table is a comment.
    ///
    /// Derived from the source rather than from a list beside the list:
    /// `dropWhenDisabled` is what makes a module's instance outlive its page, so
    /// every call to it under `Sources/Modules` is a subject, and the module is
    /// the directory the call is in.
    func testEveryModuleThatCachesAViewModelIsCovered() throws {
        let registered = try Self.modulesRegisteringADrop()
        XCTAssertGreaterThanOrEqual(registered.count, 7, """
            the scan found \(registered.count) modules calling \
            `ModuleUICache.dropWhenDisabled` — the tree has at least seven, so the walk or the \
            match has stopped reading Sources and this check is guarding nothing.
            """)

        let covered = Set(subscribing.map(\.module)).union(holdingNoSubscriber)
        XCTAssertEqual(registered.subtracting(covered).sorted(), [], """
            these modules cache a view model past the module being switched off and no check \
            here says whether the cache's release actually ends the event loop. Add each to \
            `subscribing`, or — if it consumes no events — to `holdingNoSubscriber`.
            """)
        XCTAssertEqual(covered.subtracting(registered).sorted(), [], """
            these are checked here and no longer call `ModuleUICache.dropWhenDisabled`, so the \
            check is asking about a cache that is gone.
            """)
    }

    // MARK: - Reading the tree

    private static func modulesRegisteringADrop() throws -> Set<String> {
        let modules = RepoSource.root.appendingPathComponent("Sources/Modules")
        var found: Set<String> = []
        for name in try FileManager.default.contentsOfDirectory(atPath: modules.path) {
            let ui = modules.appendingPathComponent(name).appendingPathComponent("UI")
            guard let files = FileManager.default.enumerator(atPath: ui.path) else { continue }
            for case let file as String in files where file.hasSuffix(".swift") {
                let source = try String(contentsOf: ui.appendingPathComponent(file),
                                        encoding: .utf8)
                // The call, not the word: this file and `ModuleUICache` itself
                // both name the symbol in prose, and a match on the bare name
                // would count a doc comment as a registration.
                if source.contains("ModuleUICache.dropWhenDisabled(") { found.insert(name) }
            }
        }
        return found
    }

    // MARK: - Waiting

    /// Lets the event loop actually start and park on its stream.
    ///
    /// **Not a courtesy wait — without it this check cannot see half the defect
    /// it exists for.** `LocalTransport.events` registers its continuation
    /// inside `AsyncStream`'s builder, which runs the moment `init` touches the
    /// property — so the subscriber is there *before* the task that consumes it
    /// has run a single line. A gate that waits for the count to reach 1 is
    /// therefore already open at `init`, and a view model written as
    /// `Task { [weak self] in await self?.observeEvents(events) }` would be
    /// dropped before its task first ran: `self?` resolves to nil, no strong
    /// reference is ever taken, and the module looks clean. Measured — that
    /// mutation passed three runs in a row until this wait was added. The
    /// retain only exists once the loop is inside the call, which is the state a
    /// page open for a moment is always in.
    ///
    /// Sleeping rather than yielding: the loop starts on the concurrency pool,
    /// and yielding from the main actor hands the turn to main-actor work.
    private func letTheLoopStart() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Waits for the count, rather than yielding a fixed number of times.
    ///
    /// `Task.sleep` and not `Task.yield`: the drop closure is registered on
    /// `OperationQueue.main`, so the notification is delivered by the main queue
    /// rather than by the concurrency pool, and a loop that only yields to other
    /// tasks can spin without the main queue ever getting a turn. Returning
    /// early is safe — the assertion is at the call site, so a wait that gives
    /// up reports the count it actually saw.
    private func settle(_ transport: LocalTransport, until count: Int) async {
        for _ in 0..<400 {
            if transport.subscriberCount == count { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
