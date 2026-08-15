import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The transports this module's page tests are written against, and the store
/// and waits that go with them.
///
/// **There are two kinds on purpose.** `OneAnswerTransport` answers on the
/// spot; `HeldTransport` parks every "find" until a test releases it. A fake
/// that answers synchronously is over before the code under test is reached, so
/// nothing about a search *in flight* — a cancellation, an older answer landing
/// after a newer one, a page that goes away mid-search — can be written down
/// against it. Merging the two would make `DuplicateSearchRaceTests` and
/// `SharedViewModelTests` vacuous rather than shorter.
///
/// Each was spelled twice before it moved here. The one difference between the
/// two `HeldTransport`s was a list of the command names it had been sent, which
/// no test in this target ever read — a recorder nobody reads is not richer
/// behaviour, so it did not survive the merge.

// MARK: - Answers on the spot

/// Returns the same groups to every "find" and nothing to anything else.
final class OneAnswerTransport: EngineTransport, @unchecked Sendable {
    private let groups: [DuplicateGroup]
    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(groups: [DuplicateGroup]) { self.groups = groups }

    func send(_ command: EngineCommand) async throws -> Data {
        guard command.name == "find" else { return Data() }
        return searchReply(groups)
    }
}

/// A search reply, spelled once for every fake in this file.
///
/// **The type, not a shape retyped here.** A fake that encodes the reply itself
/// is a second spelling of a wire the engine also spells, and the two parted
/// company once already: `find` began answering `DuplicateFindings` where the
/// page still asked for `[DuplicateGroup]`, every search decoded as nothing, and
/// nothing in this target could tell — because every fake here was still
/// speaking the old shape and agreeing with the page about it.
/// `TheEngineAnswersWhatThePageReadsTests` drives the real engine for
/// that reason; this keeps the fakes from being wrong in the meantime.
func searchReply(_ groups: [DuplicateGroup], unreadable: Int = 0,
                 librariesSkipped: Int = 0) -> Data {
    (try? JSONEncoder().encode(DuplicateFindings(groups: groups, unreadable: unreadable,
                                                 librariesSkipped: librariesSkipped))) ?? Data()
}

// MARK: - Parks until released

/// Parks every "find" until the test releases it, so the interleaving is chosen
/// rather than raced. An assertion that holds only for a lucky delay is not a
/// test.
final class HeldTransport: EngineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Data, Never>] = []

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    func send(_ command: EngineCommand) async throws -> Data {
        guard command.name == "find" else { return Data() }
        return await withCheckedContinuation { park($0) }
    }

    // Locking lives in a non-async helper: taking an NSLock across a suspension
    // point is what the compiler is objecting to, and it is right to.
    private func park(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock(); parked.append(continuation); lock.unlock()
    }

    var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

    /// Releases the request parked at `index` with a group named after `folder`,
    /// so a test can tell whose answer landed.
    func release(_ index: Int, folder: String) {
        lock.lock()
        guard parked.indices.contains(index) else { lock.unlock(); return }
        let continuation = parked.remove(at: index)
        lock.unlock()
        let group = DuplicateGroup(bytes: 1_000_000,
                                   paths: ["/\(folder)/a", "/\(folder)/b"])
        continuation.resume(returning: searchReply([group]))
    }
}

// MARK: - The removal side of the wire

/// The wire the removal tests are drawn against: a search reply, a removal
/// reply, and the four things the transport behind the real page can do with a
/// request.
///
/// **The two fakes above cannot be silent, and that made two states in the tree
/// unrepresentable.** `OneAnswerTransport` and `HeldTransport` answer `Data()`
/// to everything but "find", so no test that drives a removal through them ever
/// reached the wire at all; `RemovingTransport` in
/// `DuplicateRemovalOutcomeTests` always encodes a `DuplicateRemoval`. So «the
/// engine did not answer the removal» — which
/// `DuplicatesEngine.wireTransport` returns for a deallocated engine, for a
/// command name it cannot parse and for a payload that will not decode, and
/// which `DuplicatesViewModel.shared(vm:store:)`'s own comment says a cached
/// model outliving its engine gets *from then on* — was a state no test in this
/// target could write down. Nor could a throw: `EngineTransport.send` is
/// declared `throws` and nothing here has ever thrown.
///
/// And it can **park**, for the same reason `HeldTransport` exists one section
/// up: a removal that answers on the spot is over before any control the page
/// leaves live during it can be pressed, so every question about what happens
/// *while* a removal is in flight would pass with the guard deleted.
final class DuplicatesWire: EngineTransport, @unchecked Sendable {

    /// What the engine behind this wire does with a request.
    enum Answer: Equatable {
        /// The reply the fixture holds: an engine that is there and answers.
        case reply
        /// `send` throws, which `TransportClient.request` turns into the same nil
        /// as a reply that will not decode.
        case refuse
        /// Empty `Data` — an engine that is gone, or a command it does not know.
        case nothing
        /// Held until the test releases it, so the interleaving is chosen rather
        /// than raced.
        case park
    }

    private let lock = NSLock()
    private var groups: [DuplicateGroup]
    /// What the walk behind this wire could not look at. **A real search answers
    /// with these and no fake here could**, so «the page is showing the last
    /// walk's refusal» — the state the counts exist for — was one no test could
    /// write down.
    private let unreadable: Int
    private let librariesSkipped: Int
    private var removal: DuplicateRemoval
    private var answer: Answer
    /// What one command gets, where that differs from what the wire is doing —
    /// the removal that is parked while the search answers.
    private var overrides: [DuplicatesCommand: Answer] = [:]
    private var seen: [DuplicatesCommand] = []
    /// The searches that reached the wire, as the engine would decode them.
    ///
    /// The policy the page is showing travels in the request, and a request is
    /// the one place a test can see it before the engine has it — a fake that
    /// only counted its commands could not tell a search that carries the popup's
    /// answer from one that carries nothing and leaves the engine on what it had
    /// stored.
    private var searched: [DuplicateSearchRequest] = []
    /// The removals that reached the wire, likewise: a plan names the copy that
    /// goes and the copy it duplicates, and «the survivor was never sent» is a
    /// claim about the payload rather than about the command.
    private var planned: [[DuplicatePlan]] = []
    private var held: [(command: DuplicatesCommand, continuation: CheckedContinuation<Data, Never>)] = []

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(groups: [DuplicateGroup],
         unreadable: Int = 0,
         librariesSkipped: Int = 0,
         removal: DuplicateRemoval = DuplicateRemoval(removed: [], refused: [], freedBytes: 0),
         answering answer: Answer = .reply) {
        self.groups = groups
        self.unreadable = unreadable
        self.librariesSkipped = librariesSkipped
        self.removal = removal
        self.answer = answer
    }

    /// The engine going away under the page, or coming back. A port that can
    /// change while the app runs hands that state back rather than being fixed at
    /// init (CLAUDE.md § Anything that can stop being true on its own).
    func answers(_ next: Answer) { lock.withLock { answer = next } }

    /// The same, for one command only.
    func answers(_ next: Answer, to command: DuplicatesCommand) {
        lock.withLock { overrides[command] = next }
    }

    /// Which commands reached the wire, in order — so a test can assert that the
    /// act it is about really was attempted before asserting what was said about
    /// it. An assertion about an absence passes when the subject never happened.
    var commands: [DuplicatesCommand] { lock.withLock { seen } }

    /// What each search asked for, in order.
    var searches: [DuplicateSearchRequest] { lock.withLock { searched } }

    /// What each removal asked for, in order.
    var removals: [[DuplicatePlan]] { lock.withLock { planned } }

    var parkedCount: Int { lock.withLock { held.count } }

    /// The whole answer a search gets, counts and all. Taken under the lock the
    /// two callers already hold, so what is parked and what is answered on the
    /// spot cannot be two different replies.
    private var findReply: Data {
        searchReply(groups, unreadable: unreadable, librariesSkipped: librariesSkipped)
    }

    /// Lets every parked request through, each with the reply its own command
    /// would have had.
    func releaseParked() {
        let waiting: [(command: DuplicatesCommand, continuation: CheckedContinuation<Data, Never>)]
        let answers: (find: Data, removal: DuplicateRemoval)
        (waiting, answers) = lock.withLock {
            let taken = held
            held = []
            return (taken, (findReply, removal))
        }
        for one in waiting {
            switch one.command {
            case .find:
                one.continuation.resume(returning: answers.find)
            case .trash:
                one.continuation.resume(returning: (try? JSONEncoder().encode(answers.removal)) ?? Data())
            case .cancel, .stopRemoval, .backgroundScan:
                one.continuation.resume(returning: Data())
            }
        }
    }

    /// The enum, not a literal: a fake answering names of its own goes on
    /// answering after the module renames one, and what it answers then is
    /// `Data()` — which this codebase spells «the module could not answer».
    func send(_ command: EngineCommand) async throws -> Data {
        let name = DuplicatesCommand(rawValue: command.name)
        let reply: Reply = lock.withLock {
            record(name, command.payload)
            let answer = name.flatMap { overrides[$0] } ?? answer
            switch (answer, name) {
            case (.refuse, _): return .refuse
            case (.nothing, _), (_, .none), (_, .cancel), (_, .stopRemoval),
                 (_, .backgroundScan): return .empty
            case (.park, .find), (.park, .trash): return .park(name!)
            case (.reply, .find): return .data(self.findReply)
            case (.reply, .trash): return .data((try? JSONEncoder().encode(removal)) ?? Data())
            }
        }
        switch reply {
        case .refuse: throw CancellationError()
        case .empty: return Data()
        case .data(let data): return data
        case .park(let command): return await withCheckedContinuation { park(command, $0) }
        }
    }

    /// What reached the wire, decoded the way the engine would decode it: a test
    /// asks whether the *policy* travelled with the search and whether the
    /// survivor stayed out of the plans, and both are facts about the payload.
    ///
    /// Called with the lock already held, from `send`.
    private func record(_ name: DuplicatesCommand?, _ payload: Data) {
        guard let name else { return }
        seen.append(name)
        switch name {
        case .find:
            if let request = try? JSONDecoder().decode(DuplicateSearchRequest.self,
                                                       from: payload) {
                searched.append(request)
            }
        case .trash:
            if let plans = try? JSONDecoder().decode([DuplicatePlan].self, from: payload) {
                planned.append(plans)
            }
        case .cancel, .stopRemoval, .backgroundScan:
            break
        }
    }

    private func park(_ command: DuplicatesCommand,
                      _ continuation: CheckedContinuation<Data, Never>) {
        lock.withLock { held.append((command, continuation)) }
    }

    /// Decided under the lock and delivered outside it — a `throw` cannot happen
    /// inside `withLock` without carrying the lock into the error path, and a
    /// continuation must not be awaited while it is held.
    private enum Reply {
        case refuse, empty
        case data(Data)
        case park(DuplicatesCommand)
    }
}

// MARK: - The key a setting is sealed with

/// A seal key that is the same on both sides of the boundary.
///
/// **Not the login keychain**, which is what `DuplicatesSettings.guardOfScanSettings`
/// reaches: a test that stores a policy through the real guard writes an item
/// into the person's own keychain, and the machine is a boundary of its own.
///
/// It can also stop answering, because the real one does — a locked keychain at
/// login returns nil, and `SettingGuard.seal` then hands back nothing while the
/// value is still written. A fake that always has a key cannot be in that state,
/// and «the policy was saved unsealed» is exactly what the engine refuses.
final class PlantedSealKey: SealKeyPort, @unchecked Sendable {
    private let lock = NSLock()
    private var material: Data?
    private let firstUse: Bool

    init(firstUse: Bool = false, available: Bool = true) {
        self.firstUse = firstUse
        self.material = available ? Data(repeating: 0x24, count: 32) : nil
    }

    /// The keychain going away under the app — or coming back.
    func becomes(available: Bool) {
        lock.withLock { material = available ? Data(repeating: 0x24, count: 32) : nil }
    }

    func key() -> SealKey? {
        guard let material = lock.withLock({ material }) else { return nil }
        return SealKey(material: material, firstUse: firstUse)
    }
}

// MARK: - Fixtures and waits

/// Fixtures live under the home directory because `UserFileScope` judges the
/// real path, and one in `/tmp` would be refused for the wrong reason.
var home: String { NSHomeDirectory() }

/// **In memory, never `UserDefaults.standard`.** The real store is the person's
/// remembered folder; the runner's domain is `com.apple.dt.xctest.tool`, shared
/// with every package tested on this machine, and 3028 keys had accumulated
/// there before these tests stopped writing to it.
///
/// The default folder is one nothing walks: a search that parks never reaches
/// it, so only the fixtures that let a search finish name a real path.
func duplicatesStore(folder: String = "/some/folder") -> NamespacedStore {
    let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
    store.set(folder, for: "folder")
    return store
}

/// A view model over `transport`, with a folder remembered.
///
/// **The one place the seal key is injected, and it is not the person's.** The
/// view model reads the keep policy at `init` — through the same guard the
/// engine reads it with — so a fixture left on the default would have every test
/// in this target reach into the login keychain for `com.helm.app / settings-seal`
/// and create it where it is absent. The machine is a boundary of its own, and a
/// test does not write to it.
@MainActor
func duplicatesModel(over transport: EngineTransport,
                     folder: String = "\(home)/Downloads") -> DuplicatesViewModel {
    DuplicatesViewModel(vm: ModuleViewModel(transport: transport),
                        store: duplicatesStore(folder: folder),
                        settings: SettingGuard(keys: PlantedSealKey()))
}

/// A view model that has already searched, with `groups` as the answer.
@MainActor
func searchedModel(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
    await searchedModel(over: OneAnswerTransport(groups: groups))
}

/// A view model that has already searched over a wire the test goes on
/// steering — the removal answers, or does not.
@MainActor
func searchedModel(over transport: EngineTransport) async -> DuplicatesViewModel {
    let dvm = duplicatesModel(over: transport)
    dvm.search()
    for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
    return dvm
}

/// A view model whose searches will park, for the tests about a search in
/// flight.
@MainActor
func heldModel(_ transport: HeldTransport) -> DuplicatesViewModel {
    // The folder nothing walks: a search that parks never reaches it.
    duplicatesModel(over: transport, folder: "/some/folder")
}

/// Room for the tasks already scheduled to land. Spelled three times in
/// `DuplicateSearchRaceTests` as twenty yields; fifty, because every use is
/// either waiting for something to appear or asserting that it did not, and
/// both are stronger the longer they wait.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Waits for the request tasks to actually reach the transport. Yielding a
/// fixed number of times is a guess about scheduling; this is the condition the
/// test depends on.
@MainActor
func untilParked(_ transport: HeldTransport, count: Int) async {
    for _ in 0..<1000 where transport.parkedCount < count { await Task.yield() }
}
