import Foundation
import HelmRuntime
import HelmTestSupport
import Module_Duplicates_Engine
import XCTest
@testable import Module_Duplicates_UI

// The engine's place in this module's page tests, and the store and waits that
// go with it.
//
// **There are two kinds on purpose.** `AnsweringWork` answers on the spot, or
// parks a `find` or a `trash` until a test releases it; `HeldWork` parks every
// `find` and lets the test pick which one to release. A fake that answers
// synchronously is over before the code under test is reached, so nothing about
// a search *in flight* — a cancellation, an older answer landing after a newer
// one, a page that goes away mid-search — can be written down against it.
// Merging the two would make `DuplicateSearchRaceTests` vacuous rather than
// shorter.

extension DuplicateGroup {
    /// A group where every copy occupies the same amount.
    init(bytes: Int, paths: [String]) {
        self.init(copies: paths.map { Copy(path: $0, bytes: bytes) })
    }
}

// MARK: - Answers, or parks

/// A search or a removal as the work saw it.
struct SearchAsked: Equatable {
    let keepPolicy: KeepPolicy
}

/// What reached the work, in order — so a test can assert that the act it is
/// about really was attempted before asserting what was said about it. An
/// assertion about an absence passes when the subject never happened.
enum Call: Equatable { case find, cancel, trash, stopRemoval, backgroundScan }

/// The engine's place: the same groups to every `find`, the same removal to
/// every `trash`, and either can be held until the test lets it go.
///
/// It can **park**: a removal that answers on the spot is over before any
/// control the page leaves live during it can be pressed, so every question about
/// what happens *while* a removal is in flight would pass with the guard deleted.
final class AnsweringWork: DuplicatesWork, @unchecked Sendable {

    /// What the work does with a call.
    enum Answer: Equatable {
        /// An engine that is there and answers.
        case reply
        /// Held until the test releases it, so the interleaving is chosen rather
        /// than raced.
        case park
    }

    private let lock = NSLock()
    private let groups: [DuplicateGroup]
    private let librariesSkipped: Int
    private let removal: DuplicateRemoval
    private let ticks: [DuplicateProgress]
    private let removalTicks: [DuplicateProgress]
    private let movingWhileParked: Bool
    private var answer: Answer
    /// What one call gets, where that differs from what the work is doing — the
    /// removal that is parked while the search answers.
    private var overrides: [Call: Answer] = [:]
    private var seen: [Call] = []
    private var searched: [SearchAsked] = []
    /// The removals that reached the work: a plan names the copy that goes and
    /// the copy it duplicates, and «the survivor was never sent» is a claim about
    /// the payload rather than about the call.
    ///
    /// With the list of what stays: what a removal frees is arithmetic over the
    /// copies that *stay*, and a fake that dropped that list could not tell a page
    /// that names them from one that leaves the engine to guess.
    private var planned: [(plans: [DuplicatePlan], staying: [String])] = []
    private var held: [(call: Call, continuation: CheckedContinuation<Void, Never>)] = []

    /// - Parameters:
    ///   - ticks: the progress a search reports before it answers.
    ///   - removalTicks: the progress a removal reports before it answers. Its own
    ///     list, so a test can tell whose tick is on the bar.
    ///   - movingWhileParked: the removal reports `.moving` — the Trash has the
    ///     batch — before it parks.
    init(groups: [DuplicateGroup],
         librariesSkipped: Int = 0,
         removal: DuplicateRemoval = DuplicateRemoval(removed: [], refused: [], freedBytes: 0),
         ticks: [DuplicateProgress] = [],
         removalTicks: [DuplicateProgress] = [],
         movingWhileParked: Bool = false,
         answering answer: Answer = .reply) {
        self.groups = groups
        self.librariesSkipped = librariesSkipped
        self.removal = removal
        self.ticks = ticks
        self.removalTicks = removalTicks
        self.movingWhileParked = movingWhileParked
        self.answer = answer
    }

    /// The engine answering again, or holding what it is asked. A port that can
    /// change while the app runs hands that state back rather than being fixed at
    /// init (ARCHITECTURE.md § Ports and logic).
    func answers(_ next: Answer) { lock.withLock { answer = next } }

    /// The same, for one call only.
    func answers(_ next: Answer, to call: Call) { lock.withLock { overrides[call] = next } }

    var calls: [Call] { lock.withLock { seen } }

    /// What each search asked for, in order.
    var searches: [SearchAsked] { lock.withLock { searched } }

    /// What each removal asked for, in order.
    var removals: [[DuplicatePlan]] { lock.withLock { planned.map(\.plans) } }

    /// What each removal said would stay, in order.
    var staying: [[String]] { lock.withLock { planned.map(\.staying) } }

    var parkedCount: Int { lock.withLock { held.count } }

    /// Lets every parked call through, each with the reply its own call would
    /// have had.
    func releaseParked() {
        let waiting = lock.withLock { () -> [(call: Call, continuation: CheckedContinuation<Void, Never>)] in
            let taken = held
            held = []
            return taken
        }
        for one in waiting { one.continuation.resume() }
    }

    func find(under path: String, keeping policy: KeepPolicy,
              progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateFindings? {
        lock.withLock {
            seen.append(.find)
            searched.append(SearchAsked(keepPolicy: policy))
        }
        for tick in ticks { progress?(tick) }
        await parkIfAsked(.find)
        return DuplicateFindings(groups: groups, unreadable: 0, librariesSkipped: librariesSkipped)
    }

    func cancel() { lock.withLock { seen.append(.cancel) } }

    func trash(_ plans: [DuplicatePlan], staying: [String],
               progress: (@Sendable (RemovalTick) -> Void)?) async -> DuplicateRemoval {
        lock.withLock {
            seen.append(.trash)
            planned.append((plans, staying))
        }
        for tick in removalTicks { progress?(.verified(tick)) }
        if movingWhileParked { progress?(.moving) }
        await parkIfAsked(.trash)
        return removal
    }

    func stopRemoval() { lock.withLock { seen.append(.stopRemoval) } }

    func backgroundScan() async -> ScanReport? {
        lock.withLock { seen.append(.backgroundScan) }
        return ScanReport(bytes: 0, count: 0, items: [])
    }

    /// Decided under the lock and waited outside it: a continuation must not be
    /// awaited while the lock is held.
    private func parkIfAsked(_ call: Call) async {
        let parks = lock.withLock { (overrides[call] ?? answer) == .park }
        guard parks else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock { held.append((call, continuation)) }
        }
    }
}

// MARK: - Parks every search until released

/// Parks every `find` until the test releases it, so the interleaving is chosen
/// rather than raced. An assertion that holds only for a lucky delay is not a
/// test.
final class HeldWork: DuplicatesWork, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<DuplicateFindings?, Never>] = []

    var parkedCount: Int { lock.withLock { parked.count } }

    func find(under path: String, keeping policy: KeepPolicy,
              progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateFindings? {
        await withCheckedContinuation { continuation in
            lock.withLock { parked.append(continuation) }
        }
    }

    /// Releases the search parked at `index` with a group named after `folder`,
    /// so a test can tell whose answer landed.
    func release(_ index: Int, folder: String) {
        let continuation: CheckedContinuation<DuplicateFindings?, Never>? = lock.withLock {
            parked.indices.contains(index) ? parked.remove(at: index) : nil
        }
        let group = DuplicateGroup(bytes: 1_000_000, paths: ["/\(folder)/a", "/\(folder)/b"])
        continuation?.resume(returning: DuplicateFindings(groups: [group]))
    }

    func cancel() {}
    func trash(_ plans: [DuplicatePlan], staying: [String],
               progress: (@Sendable (RemovalTick) -> Void)?) async -> DuplicateRemoval {
        DuplicateRemoval(removed: [], refused: [], freedBytes: 0)
    }
    func stopRemoval() {}
    func backgroundScan() async -> ScanReport? { nil }
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

/// A view model over `work`, with a folder remembered, that has appeared as the
/// page does.
///
/// **The one place the seal key is injected, and it is not the person's.** The
/// view model reads the keep policy through the same guard the engine reads it
/// with, so a fixture left on the default would have every test in this target
/// reach into the login keychain for `com.helm.app / settings-seal` and create
/// it where it is absent. The machine is a boundary of its own, and a test does
/// not write to it.
///
/// **Behind `SealKeyCache`, because the page reads through `keyIfWarm()`.** A
/// bare `SealKeyProbe` takes `SealKeyPort`'s default `keyIfWarm() -> nil`, so
/// `SettingGuard.isWarm` is false for ever and `keepPolicyIfWarm` never answers
/// — a keychain permanently mid-answer, which is a state the real one is never
/// permanently in, and it made «the page opened on what is stored» unwritable
/// through the shared fixture. The cache is what turns the one round trip
/// `firstLoad` makes into a warm read, exactly as
/// `DuplicatesSettings.guardOfScanSettings` does in the app.
/// - Parameter store: for the tests that have to put something in it first — a
///   sealed keep policy is written before the page exists, the way an earlier
///   run of the app would have left it. Left out, the fixture builds its own.
@MainActor
func duplicatesModel(over work: any DuplicatesWork,
                     folder: String = "\(home)/Downloads",
                     store: NamespacedStore? = nil,
                     chooseFolder: @escaping @MainActor () -> URL? = { nil }) -> DuplicatesViewModel {
    let dvm = DuplicatesViewModel(work: work,
                                  store: store ?? duplicatesStore(folder: folder),
                                  settings: SettingGuard(keys: SealKeyCache(SealKeyProbe(firstUse: false))),
                                  chooseFolder: chooseFolder)
    dvm.appear()
    return dvm
}

/// A view model that has already searched, with `groups` as the answer.
@MainActor
func searchedModel(_ groups: [DuplicateGroup], file: StaticString = #filePath,
                   line: UInt = #line) async -> DuplicatesViewModel {
    await searchedModel(over: AnsweringWork(groups: groups), file: file, line: line)
}

/// A view model that has already searched over a work the test goes on
/// steering — the removal answers, or does not.
///
/// **A search that never answers fails here**, naming the wait, and not at the
/// first assertion that reads a page which never got its result.
@MainActor
func searchedModel(over work: any DuplicatesWork, file: StaticString = #filePath,
                   line: UInt = #line) async -> DuplicatesViewModel {
    let dvm = duplicatesModel(over: work)
    dvm.search()
    for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
    if dvm.phase != .result {
        XCTFail("never reached: the search answered and the page shows its result", file: file, line: line)
    }
    return dvm
}

/// A view model whose searches will park, for the tests about a search in
/// flight.
@MainActor
func heldModel(_ work: HeldWork) -> DuplicatesViewModel {
    // The folder nothing walks: a search that parks never reaches it.
    duplicatesModel(over: work, folder: "/some/folder")
}

/// Room for the tasks already scheduled to land, **before an assertion that
/// something did not happen**. It proves nothing by itself; a wait for something to
/// appear is `waitUntil`, which fails when the thing never comes.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Waits for the search tasks to actually reach the work. Yielding a fixed
/// number of times is a guess about scheduling; this is the condition the test
/// depends on. Fails, naming the count, when the searches never get there.
@MainActor
func untilParked(_ work: HeldWork, count: Int, file: StaticString = #filePath,
                 line: UInt = #line) async {
    await waitUntilWithin("\(count) search(es) parked on the work", .seconds(5), file: file, line: line) {
        work.parkedCount >= count
    }
}
