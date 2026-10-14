import XCTest
import SwiftUI
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI

/// `ModuleUICache.dropWhenDisabled` is how a module lets go of what it cached
/// when it is switched off, and a module may cache in more than one place:
/// Screenshots keeps a page model in one file and a capture controller in
/// another, both under the one module id.
///
/// Every registration has to run when the module is disabled. A registry that
/// keeps one closure per id and ignores the next leaves the second place
/// caching for a module that is off, and with it that model's subscriber on its
/// transport.
///
/// The models of the first row (`Subscribed`) stand for the real ones in the one
/// way that matters: each holds its event loop in a task that does not hold the
/// model (`[weak self]`, `self` taken again per event) and cancels it in
/// `deinit`, so releasing the model is exactly what returns the subscriber, as
/// `= nil` does for the modules' own drops. Each place keeps its model the way a
/// module's static does, and the drop it registers is the module's own shape:
/// release and nothing else. The models of every other row (`Listening`) hold an
/// `EventSubscription` and have no `deinit` of their own.
///
/// **The registry is process-wide**, and the next switch-off of an id runs
/// every registration made under it, whoever made it. An id another test has
/// registered under would have this test's disable run that test's closures.
/// The id is therefore made fresh for each test, from a `UUID`, and shared
/// with no module.
@MainActor
final class ModuleUICacheTests: XCTestCase {

    // MARK: - A place that caches

    /// Stands for one module static: holds a model, counts the drops that ran.
    @MainActor
    private final class Place {
        var model: Subscribed?
        private(set) var dropsRun = 0

        init(model: Subscribed) { self.model = model }

        func register(under id: String) {
            ModuleUICache.dropWhenDisabled(id) { [self] in
                dropsRun += 1
                model = nil
            }
        }
    }

    /// A model with an event loop over a transport it was given.
    @MainActor
    private final class Subscribed {
        private var eventsTask: Task<Void, Never>?

        init(transport: LocalTransport) {
            let events = transport.events
            eventsTask = Task { [weak self] in
                for await _ in events {
                    guard self != nil else { break }
                }
            }
        }

        deinit { eventsTask?.cancel() }
    }

    // MARK: - The rule

    func testTwoRegistrationsUnderOneIDAreBothDroppedWhenTheModuleIsDisabled() async {
        let id = "test.module-ui-cache.\(UUID().uuidString)"

        // The transports are held by the test; the models are held by their
        // places alone, so a release is the last reference going.
        let firstTransport = LocalTransport()
        let secondTransport = LocalTransport()
        let first = Place(model: Subscribed(transport: firstTransport))
        let second = Place(model: Subscribed(transport: secondTransport))
        first.register(under: id)
        second.register(under: id)

        // The subject has to exist before its absence means anything: a model
        // that never subscribed would read zero after the disable all the same.
        await settle { firstTransport.subscriberCount == 1 && secondTransport.subscriberCount == 1 }
        XCTAssertEqual(firstTransport.subscriberCount, 1,
                       "the first model never subscribed, so the count after the disable proves nothing")
        XCTAssertEqual(secondTransport.subscriberCount, 1,
                       "the second model never subscribed, so the count after the disable proves nothing")
        XCTAssertNotNil(first.model, "the first place lost its model before the disable")
        XCTAssertNotNil(second.model, "the second place lost its model before the disable")
        await letTheLoopsStart()

        NotificationCenter.default.post(name: .helmModuleDisabled, object: id)
        await settle {
            first.dropsRun + second.dropsRun == 2
                && firstTransport.subscriberCount == 0 && secondTransport.subscriberCount == 0
        }

        XCTAssertEqual(first.dropsRun, 1, "the first registration's drop did not run when the module was disabled")
        XCTAssertEqual(second.dropsRun, 1, "the second registration's drop did not run when the module was disabled")
        XCTAssertEqual(firstTransport.subscriberCount, 0,
                       "the first model is still subscribed after its module was disabled")
        XCTAssertEqual(secondTransport.subscriberCount, 0,
                       "the second model is still subscribed after its module was disabled")
    }

    // MARK: - The cache: one model per module id, type and view model

    /// A model that listens to a transport through an `EventSubscription`. The tag
    /// makes two of them two types, which is how the cache tells them apart.
    @MainActor
    private final class Listening<Tag> {
        let transport: LocalTransport
        var subscription: EventSubscription?
        private(set) var seen = 0
        var tornDown = 0

        init(transport: LocalTransport, subscribed: Bool = true) {
            self.transport = transport
            if subscribed { subscribe() }
        }

        /// Takes a subscription now, replacing whatever the model held.
        func subscribe() {
            subscription = EventSubscription(transport.events) { [weak self] _ in self?.seen += 1 }
        }
    }

    private enum Page {}
    private enum Controller {}
    private typealias PageModel = Listening<Page>
    private typealias ControllerModel = Listening<Controller>

    /// A descriptor that overrides only the argument-less hook.
    @MainActor
    private final class ArgumentlessOnly: ModuleDescriptor {
        static let id = ModuleID("test.module-ui-cache.argumentless")
        static let metadata = ModuleMetadata(id: id, name: "Argumentless", summary: "",
                                             sfSymbol: "gear", permissions: [])
        static let category: ModuleCategory = .utilities
        static let tint: ModuleTint = .keyboard
        static let glyph: ShellGlyph = .disk

        var attached = 0

        func makeEngine(store: NamespacedStore) -> any ModuleEngine { Idle() }
        func attachMenuBarPresence() { attached += 1 }
        func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }
        func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(EmptyView()) }
    }

    /// A descriptor that overrides the hook that takes the view model.
    @MainActor
    private final class WithViewModel: ModuleDescriptor {
        static let id = ModuleID("test.module-ui-cache.with-view-model")
        static let metadata = ModuleMetadata(id: id, name: "With view model", summary: "",
                                             sfSymbol: "gear", permissions: [])
        static let category: ModuleCategory = .utilities
        static let tint: ModuleTint = .keyboard
        static let glyph: ShellGlyph = .disk

        var received: [ModuleViewModel] = []
        var argumentless = 0

        func makeEngine(store: NamespacedStore) -> any ModuleEngine { Idle() }
        func attachMenuBarPresence() { argumentless += 1 }
        func attachMenuBarPresence(_ vm: ModuleViewModel) { received.append(vm) }
        func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { nil }
        func settingsPage(_ vm: ModuleViewModel) -> AnyView { AnyView(EmptyView()) }
    }

    private final class Idle: ModuleEngine {
        let transport: EngineTransport = LocalTransport()
        func activate() {}
        func deactivate() {}
    }

    private func freshID() -> String { "test.module-ui-cache.\(UUID().uuidString)" }

    /// What the host posts when a module is switched off, and the proof that the
    /// observer has run: a second id, posted after the first, whose drop must have
    /// run before a row reads anything.
    private func disable(_ id: String) async {
        let sentinel = freshID()
        var delivered = false
        ModuleUICache.dropWhenDisabled(sentinel) { delivered = true }
        NotificationCenter.default.post(name: .helmModuleDisabled, object: id)
        NotificationCenter.default.post(name: .helmModuleDisabled, object: sentinel)
        await settleOrFail("the notification for \(id) was never delivered") { delivered }
    }

    func testTheSameViewModelGetsTheSameModelAndAnotherOneGetsANewModel() {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        var builds = 0
        func ask(_ vm: ModuleViewModel, _ id: String) -> PageModel {
            ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
                builds += 1
                return PageModel(transport: transport)
            }
        }

        let first = ask(vm, id)
        XCTAssertEqual(builds, 1, "the first call did not build a model, so nothing below says anything")
        XCTAssertTrue(ask(vm, id) === first, "the same view model and id were handed a second model")
        XCTAssertEqual(builds, 1, "the same view model and id built again")

        let other = ModuleViewModel(transport: transport)
        let second = ask(other, id)
        XCTAssertFalse(second === first, "another view model was handed the model of the first")
        XCTAssertEqual(builds, 2, "another view model did not build a model of its own")
        XCTAssertTrue(ask(other, id) === second, "after the replacement the new view model's model was not kept")

        let elsewhere = ask(other, freshID())
        XCTAssertFalse(elsewhere === second, "another module id was handed the model of the first id")
        XCTAssertEqual(builds, 3, "another module id did not build a model of its own")
    }

    func testADroppedModelIsUnsubscribedWhileTheTestStillHoldsIt() async {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        weak var probe = model
        await settleOrFail("the model never subscribed") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1, "the model never subscribed, so the count after the drop proves nothing")
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("the dropped model is still subscribed") { transport.subscriberCount == 0 }

        XCTAssertNotNil(probe, "the model was released, so the count says nothing about the cache's own drop")
        XCTAssertEqual(transport.subscriberCount, 0,
                       "the dropped model, which the test still holds, is still subscribed to its transport")
        let rebuilt = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        XCTAssertFalse(rebuilt === model, "a model dropped by the switch-off was handed out again")
        withExtendedLifetime(model) {}
    }

    func testAReplacedModelIsUnsubscribedWhileTheTestStillHoldsIt() async {
        let id = freshID()
        let firstTransport = LocalTransport()
        let secondTransport = LocalTransport()
        let firstVM = ModuleViewModel(transport: firstTransport)
        let secondVM = ModuleViewModel(transport: secondTransport)
        let first = ModuleUICache.shared(vm: firstVM, id: id, events: { $0.subscription }) {
            PageModel(transport: firstTransport)
        }
        weak var probe = first
        await settleOrFail("the first model never subscribed") { firstTransport.subscriberCount == 1 }
        XCTAssertEqual(firstTransport.subscriberCount, 1, "the first model never subscribed, so the count after the replacement proves nothing")
        await letTheLoopsStart()

        let second = ModuleUICache.shared(vm: secondVM, id: id, events: { $0.subscription }) {
            PageModel(transport: secondTransport)
        }
        await settleOrFail("the replaced model is still subscribed") { firstTransport.subscriberCount == 0 }

        XCTAssertFalse(second === first, "the replacement handed out the old model")
        XCTAssertNotNil(probe, "the replaced model was released, so the count says nothing about the cache's own cancel")
        XCTAssertEqual(firstTransport.subscriberCount, 0,
                       "the replaced model, which the test still holds, is still subscribed to its transport")
        await settleOrFail("the replacement never subscribed") { secondTransport.subscriberCount == 1 }
        XCTAssertEqual(secondTransport.subscriberCount, 1, "the replacing model lost its subscription with the old one")
        withExtendedLifetime((first, second)) {}
    }

    /// A page model and a capture controller: two types, one module id, both
    /// asked of the cache.
    func testTwoTypesUnderOneIDAreBothReleasedWhenTheModuleIsDisabled() async {
        let id = freshID()
        let pageTransport = LocalTransport()
        let controllerTransport = LocalTransport()
        let vm = ModuleViewModel(transport: pageTransport)
        let page = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: pageTransport)
        }
        let controller = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            ControllerModel(transport: controllerTransport)
        }
        XCTAssertFalse((page as AnyObject) === (controller as AnyObject), "two types under one id were handed one model")
        await settleOrFail("the models never subscribed") {
            pageTransport.subscriberCount == 1 && controllerTransport.subscriberCount == 1
        }
        XCTAssertEqual(pageTransport.subscriberCount, 1, "the page model never subscribed")
        XCTAssertEqual(controllerTransport.subscriberCount, 1, "the controller never subscribed")
        let again = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: pageTransport)
        }
        XCTAssertTrue(again === page, "asking for the second type replaced the first")
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("a model of the module is still subscribed after the switch-off") {
            pageTransport.subscriberCount == 0 && controllerTransport.subscriberCount == 0
        }

        XCTAssertEqual(pageTransport.subscriberCount, 0, "the page model is still subscribed after its module was disabled")
        XCTAssertEqual(controllerTransport.subscriberCount, 0, "the controller is still subscribed after its module was disabled")
        withExtendedLifetime((page, controller)) {}
    }

    func testATeardownRunsOnTheDropAndOnTheReplacementOnceEach() async {
        let id = freshID()
        let transport = LocalTransport()
        let firstVM = ModuleViewModel(transport: transport)
        let secondVM = ModuleViewModel(transport: transport)
        func ask(_ vm: ModuleViewModel) -> PageModel {
            ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription },
                                 teardown: { $0.tornDown += 1 }) {
                PageModel(transport: transport)
            }
        }

        let first = ask(firstVM)
        XCTAssertEqual(first.tornDown, 0, "the teardown ran when the model was built")
        XCTAssertTrue(ask(firstVM) === first, "the same view model was handed another model")
        XCTAssertEqual(first.tornDown, 0, "the teardown ran on a call that only returned the held model")

        let second = ask(secondVM)
        XCTAssertFalse(second === first, "the replacement handed out the old model")
        XCTAssertEqual(first.tornDown, 1, "the replaced model's teardown did not run once on the replacement")
        XCTAssertEqual(second.tornDown, 0, "the replacing model was torn down on its own build")

        await disable(id)
        XCTAssertEqual(second.tornDown, 1, "the dropped model's teardown did not run once on the drop")
        XCTAssertEqual(first.tornDown, 1, "the replaced model was torn down again on the drop")
    }

    func testTheNewHookReachesAnArgumentlessOverrideAndTheViewModelReachesItsOwn() {
        let vm = ModuleViewModel(transport: LocalTransport())

        let argumentless = ArgumentlessOnly()
        let throughTheProtocol: any ModuleDescriptor = argumentless
        XCTAssertEqual(argumentless.attached, 0, "the descriptor was attached before the call")
        throughTheProtocol.attachMenuBarPresence(vm)
        XCTAssertEqual(argumentless.attached, 1,
                       "a descriptor that overrides only the argument-less hook was not reached through the new one")

        let withViewModel = WithViewModel()
        let other: any ModuleDescriptor = withViewModel
        other.attachMenuBarPresence(vm)
        XCTAssertEqual(withViewModel.received.count, 1, "the hook that takes the view model was not reached")
        XCTAssertTrue(withViewModel.received.first === vm, "the hook was handed another view model")
        XCTAssertEqual(withViewModel.argumentless, 0, "the argument-less hook ran beside the one that takes the view model")
    }

    // MARK: - EventSubscription

    func testCancelEndsTheSubscriberAndNothingAfterItIsHandled() async {
        let transport = LocalTransport()
        let model = PageModel(transport: transport)
        await settleOrFail("the subscription never registered") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1, "nothing was subscribed, so the count after cancel proves nothing")
        await letTheLoopsStart()
        transport.emit(EngineEvent(name: "before"))
        await settleOrFail("a live subscription never handled an event") { model.seen == 1 }
        XCTAssertEqual(model.seen, 1)

        model.subscription?.cancel()
        await settleOrFail("the cancelled subscription is still on the transport") { transport.subscriberCount == 0 }
        transport.emit(EngineEvent(name: "after"))
        await grace()

        XCTAssertEqual(transport.subscriberCount, 0, "cancel left the subscriber on the transport while the token is held")
        XCTAssertEqual(model.seen, 1, "an event sent after cancel was handled")
    }

    func testCancellingTwiceIsHarmless() async {
        let transport = LocalTransport()
        let model = PageModel(transport: transport)
        await settleOrFail("the subscription never registered") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1, "nothing was subscribed, so the second cancel proves nothing")
        await letTheLoopsStart()

        model.subscription?.cancel()
        model.subscription?.cancel()
        await settleOrFail("the cancelled subscription is still on the transport") { transport.subscriberCount == 0 }
        model.subscription?.cancel()
        XCTAssertEqual(transport.subscriberCount, 0)
    }

    func testReleasingTheTokenEndsTheSubscriber() async {
        let transport = LocalTransport()
        var token: EventSubscription? = EventSubscription(transport.events) { _ in }
        await settleOrFail("the subscription never registered") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1, "nothing was subscribed, so the count after the release proves nothing")
        await letTheLoopsStart()

        token = nil
        await settleOrFail("the released token's subscriber is still on the transport") { transport.subscriberCount == 0 }
        XCTAssertEqual(transport.subscriberCount, 0, "a token that was released left its subscriber on the transport")
        XCTAssertNil(token)
    }

    // MARK: - The store of a view model

    func testTheStoreOfAViewModelBuiltWithoutOneIsInMemoryAndItsOwn() {
        let key = "test-module-ui-cache-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: "module.unhosted.\(key)") }
        let first = ModuleViewModel(transport: LocalTransport())
        let second = ModuleViewModel(transport: LocalTransport())
        XCTAssertEqual(first.store.int(key, default: -1), -1, "the key was set before the write, so the read back proves nothing")

        first.store.set(42, for: key)

        XCTAssertEqual(first.store.int(key, default: -1), 42, "a write was not read back through the same view model")
        XCTAssertEqual(second.store.int(key, default: -1), -1, "a second view model saw the first one's write")
        XCTAssertNil(UserDefaults.standard.object(forKey: "module.unhosted.\(key)"),
                     "a view model built without a store wrote to UserDefaults.standard")
    }

    func testTheStoreOfAViewModelBuiltWithOneIsThatStore() {
        let backing = InMemoryKeyValueStore()
        let named = NamespacedStore(namespace: "test.module-ui-cache", backing: backing)
        let vm = ModuleViewModel(transport: LocalTransport(), store: named)
        XCTAssertNil(backing.object(forKey: "module.test.module-ui-cache.k"), "the key was set before the write")

        vm.store.set("through the view model", for: "k")
        XCTAssertEqual(backing.object(forKey: "module.test.module-ui-cache.k") as? String, "through the view model",
                       "a write through the view model did not reach the store it was built with")

        named.set("through the store", for: "k")
        XCTAssertEqual(vm.store.string("k", default: ""), "through the store",
                       "a write through the store the view model was built with was not read back through it")
    }

    // MARK: - Inputs nobody fed in

    /// A model that takes its subscription after it was built: a cache that asks for it once, when the model is built, finds none and cancels nothing at the drop.
    func testASubscriptionTakenAfterTheModelWasBuiltIsUnsubscribedByTheDrop() async {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport, subscribed: false)
        }
        XCTAssertEqual(transport.subscriberCount, 0, "the model subscribed when it was built, so it is not the late kind")
        model.subscribe()
        await settleOrFail("the late subscription never registered") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1, "the late subscription never registered, so the drop proves nothing")
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("the late subscription is still on the transport") { transport.subscriberCount == 0 }

        XCTAssertEqual(transport.subscriberCount, 0,
                       "a model that took its subscription after it was built is still subscribed after the drop")
        withExtendedLifetime(model) {}
    }

    /// A model that replaces its subscription with a new one after it was built.
    func testASubscriptionTheModelReplacedIsUnsubscribedByTheDrop() async {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        await settleOrFail("the model never subscribed") { transport.subscriberCount == 1 }
        await letTheLoopsStart()
        model.subscribe()
        await settleOrFail("the first subscription was not let go by the replacement") { transport.subscriberCount == 1 }
        await letTheLoopsStart()
        XCTAssertEqual(transport.subscriberCount, 1, "the replacement subscription is not the one subscriber, so the drop proves nothing")

        await disable(id)
        await settleOrFail("the replacing subscription is still on the transport") { transport.subscriberCount == 0 }

        XCTAssertEqual(transport.subscriberCount, 0,
                       "a model that replaced its subscription is still subscribed after the drop")
        withExtendedLifetime(model) {}
    }

    /// A drop that registers again and asks for a model while it runs.
    func testADropThatRegistersAgainAndAsksForAModelFindsTheTableAsItWillStay() async {
        let id = freshID()
        let transport = LocalTransport()
        let rebuiltTransport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        var reRegisteredRuns = 0
        var rebuilt: PageModel?
        ModuleUICache.dropWhenDisabled(id) {
            ModuleUICache.dropWhenDisabled(id) { reRegisteredRuns += 1 }
            rebuilt = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
                PageModel(transport: rebuiltTransport)
            }
        }
        await settleOrFail("the model never subscribed") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1)
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("the drop never ran") { rebuilt != nil }
        XCTAssertEqual(reRegisteredRuns, 0, "a closure registered while the drop ran was run by that same disable")
        XCTAssertFalse(rebuilt === model, "a drop that asked for a model was handed the one being dropped")
        await settleOrFail("the model built during the drop never subscribed") { rebuiltTransport.subscriberCount == 1 }
        XCTAssertEqual(rebuiltTransport.subscriberCount, 1)
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("the next disable left the registered closure and the rebuilt model") {
            reRegisteredRuns == 1 && rebuiltTransport.subscriberCount == 0
        }
        XCTAssertEqual(reRegisteredRuns, 1, "the closure registered during a drop did not run at the next disable")
        XCTAssertEqual(rebuiltTransport.subscriberCount, 0, "the model built during a drop survived the next disable")
        withExtendedLifetime((model, rebuilt)) {}
    }

    func testADisableForAnIDNobodyRegisteredUnderChangesNothing() async {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        await settleOrFail("the model never subscribed") { transport.subscriberCount == 1 }
        XCTAssertEqual(transport.subscriberCount, 1)
        await letTheLoopsStart()

        await disable(freshID())

        XCTAssertEqual(transport.subscriberCount, 1, "a disable for another module id dropped this module's model")
        let again = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            PageModel(transport: transport)
        }
        XCTAssertTrue(again === model, "a disable for another module id released this module's model")
    }

    func testASecondDisableOfTheSameIDRunsNothingAgain() async {
        let id = freshID()
        let transport = LocalTransport()
        let vm = ModuleViewModel(transport: transport)
        var drops = 0
        let model = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription },
                                         teardown: { $0.tornDown += 1 }) {
            PageModel(transport: transport)
        }
        ModuleUICache.dropWhenDisabled(id) { drops += 1 }
        XCTAssertEqual(drops + model.tornDown, 0, "something ran before the first disable")

        await disable(id)
        XCTAssertEqual(drops, 1, "the first disable did not run the registered drop")
        XCTAssertEqual(model.tornDown, 1, "the first disable did not tear the model down")

        await disable(id)
        XCTAssertEqual(drops, 1, "a second disable ran the drop again")
        XCTAssertEqual(model.tornDown, 1, "a second disable tore the model down again")
    }

    /// The entry holds the view model weakly: a view model that is gone leaves a
    /// model nobody can be handed.
    func testAViewModelThatIsGoneIsReplacedWhenTheCacheIsAskedWithANewOne() async {
        let id = freshID()
        let goneTransport = LocalTransport()
        let newTransport = LocalTransport()
        weak var gone: ModuleViewModel?
        var first: PageModel?
        do {
            let vm = ModuleViewModel(transport: goneTransport)
            gone = vm
            first = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
                PageModel(transport: goneTransport)
            }
        }
        XCTAssertNil(gone, "the first view model is still alive, so the cache was not asked after it was gone")
        await settleOrFail("the first model never subscribed") { goneTransport.subscriberCount == 1 }
        XCTAssertEqual(goneTransport.subscriberCount, 1)
        await letTheLoopsStart()

        let newVM = ModuleViewModel(transport: newTransport)
        let second = ModuleUICache.shared(vm: newVM, id: id, events: { $0.subscription }) {
            PageModel(transport: newTransport)
        }
        await settleOrFail("the model of the gone view model is still subscribed") { goneTransport.subscriberCount == 0 }

        XCTAssertFalse(second === first, "a new view model was handed the model of one that is gone")
        XCTAssertEqual(goneTransport.subscriberCount, 0, "the model of a gone view model, which the test holds, is still subscribed")
        withExtendedLifetime((first, second)) {}
    }

    /// A `make` that asks the cache for another type under the same id.
    func testAModelBuiltInsideAnotherModelsMakeIsKeptAndReleasedToo() async {
        let id = freshID()
        let pageTransport = LocalTransport()
        let controllerTransport = LocalTransport()
        let vm = ModuleViewModel(transport: pageTransport)
        var controller: ControllerModel?
        let page: PageModel = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
            controller = ModuleUICache.shared(vm: vm, id: id, events: { $0.subscription }) {
                ControllerModel(transport: controllerTransport)
            }
            return PageModel(transport: pageTransport)
        }
        await settleOrFail("the models never subscribed") {
            pageTransport.subscriberCount == 1 && controllerTransport.subscriberCount == 1
        }
        XCTAssertEqual(pageTransport.subscriberCount, 1)
        XCTAssertEqual(controllerTransport.subscriberCount, 1)
        await letTheLoopsStart()

        await disable(id)
        await settleOrFail("a model built inside another's make is still subscribed") {
            pageTransport.subscriberCount == 0 && controllerTransport.subscriberCount == 0
        }

        XCTAssertEqual(pageTransport.subscriberCount, 0, "the outer model is still subscribed after the drop")
        XCTAssertEqual(controllerTransport.subscriberCount, 0, "the model built inside the other's make is still subscribed after the drop")
        withExtendedLifetime((page, controller)) {}
    }

    // MARK: - Waiting

    /// The subscriber is registered while the transport's stream is built, before
    /// the task that consumes it has run a line; a release that comes before the
    /// loop is inside its first wait would find a model nothing holds yet.
    private func letTheLoopsStart() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Waits as `settle(until:)` below does, and fails with `what` when the
    /// condition never held.
    private func settleOrFail(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                              _ done: () -> Bool) async {
        await settle(until: done)
        XCTAssertTrue(done(), "never reached: \(what)", file: file, line: line)
    }

    /// Waits for the condition and gives up after two seconds; the assertion is
    /// at the call site, so a wait that gives up reports what it actually saw.
    /// A sleep and not a yield, because the drop is delivered by the main queue.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<400 {
            if done() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
